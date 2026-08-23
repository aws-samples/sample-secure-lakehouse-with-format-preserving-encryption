"""One-shot Lambda that seeds AWS Secrets Manager with FPE material.

Generates:
- key:   32 random bytes hex-encoded (AES-256 key for FF3-1)
- tweak: 7 random bytes hex-encoded (FF3-1 56-bit tweak)

The key is high-entropy random material generated directly with ``secrets``,
so no password-based key derivation (PBKDF2) is needed or used.

Idempotent: if the secret already contains both keys, it is left untouched
unless the invocation event sets ``{"force": true}``.
"""

import json
import logging
import os
import secrets

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

SECRET_NAME = os.environ["SECRET_NAME"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

_SECRETS_CLIENT = boto3.client("secretsmanager", region_name=AWS_REGION)


def _generate_material() -> dict:
    return {
        # AES-256 key, hex-encoded (32 bytes -> 64 hex chars).
        "key": secrets.token_bytes(32).hex(),
        # FF3-1 tweak is 56 bits -> 7 bytes -> 14 hex chars
        # (NIST SP 800-38G Rev. 1). A 64-bit/8-byte tweak selects the
        # withdrawn FF3 algorithm, not FF3-1.
        "tweak": secrets.token_bytes(7).hex(),
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
    required = {"key", "tweak"}

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
