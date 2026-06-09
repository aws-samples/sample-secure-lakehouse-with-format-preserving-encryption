"""One-shot Lambda that seeds AWS Secrets Manager with FPE material.

Generates:
- tweak:    8 bytes hex-encoded (FF3-1 mandatory tweak length)
- password: 16 random URL-safe bytes
- salt:     16 random URL-safe bytes

Idempotent: if the secret already contains all three keys, it is left untouched
unless the invocation event sets ``{"force": true}``.
"""

import json
import logging
import os
import secrets
import string

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

SECRET_NAME = os.environ["SECRET_NAME"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

_SECRETS_CLIENT = boto3.client("secretsmanager", region_name=AWS_REGION)

_ALPHABET = string.ascii_letters + string.digits


def _random_string(length: int) -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(length))


def _generate_material() -> dict:
    return {
        "password": _random_string(16),
        "salt": _random_string(16),
        # FF3-1 tweak must be exactly 8 bytes -> 16 hex chars.
        "tweak": secrets.token_bytes(8).hex(),
    }


def _current_secret() -> dict:
    try:
        response = _SECRETS_CLIENT.get_secret_value(SecretId=SECRET_NAME)
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ResourceNotFoundException":
            return {}
        raise

    raw = response.get("SecretString")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def handler(event, _context):
    """Lambda entry point — generate and store FPE key material."""
    force = bool((event or {}).get("force"))
    existing = _current_secret()
    required = {"password", "salt", "tweak"}

    if not force and required.issubset(existing.keys()):
        LOGGER.info("FPE material already present in %s; skipping.", SECRET_NAME)
        return {
            "status": "skipped",
            "secretName": SECRET_NAME,
            "reason": "already seeded",
        }

    material = _generate_material()
    try:
        _SECRETS_CLIENT.put_secret_value(
            SecretId=SECRET_NAME,
            SecretString=json.dumps(material),
        )
    except ClientError as exc:
        LOGGER.error("Failed to seed FPE material into %s: %s", SECRET_NAME, exc)
        return {"status": "error", "secretName": SECRET_NAME, "error": str(exc)}

    LOGGER.info("Seeded FPE material into %s.", SECRET_NAME)
    return {"status": "ok", "secretName": SECRET_NAME}
