"""Vault-Transform-compatible encryption Lambda.

Receives a Vault-style request from API Gateway (Lambda Proxy integration),
retrieves FPE key material from AWS Secrets Manager, performs FF3-1
encryption, and returns a Vault-compatible response.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError
from ff3 import FF3Cipher
from passlib.utils.pbkdf2 import pbkdf2

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

SECRET_NAME = os.environ["SECRET_NAME"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

_SECRETS_CLIENT = boto3.client("secretsmanager", region_name=AWS_REGION)

# Cache the cipher between invocations on warm Lambdas.
_CIPHER_CACHE = {"cipher": None, "version_id": None}


def _load_cipher() -> FF3Cipher:
    """Fetch FPE material from Secrets Manager and build an FF3Cipher.

    The cipher is cached per Secrets Manager version so rotations are picked up
    without restarting the Lambda.
    """
    try:
        response = _SECRETS_CLIENT.get_secret_value(SecretId=SECRET_NAME)
    except ClientError as exc:
        LOGGER.error("Failed to retrieve secret %s: %s", SECRET_NAME, exc)
        raise

    version_id = response.get("VersionId")

    if _CIPHER_CACHE["cipher"] is not None and _CIPHER_CACHE["version_id"] == version_id:
        return _CIPHER_CACHE["cipher"]

    try:
        material = json.loads(response["SecretString"])
    except (json.JSONDecodeError, KeyError) as exc:
        LOGGER.error("Secret %s contains invalid JSON: %s", SECRET_NAME, exc)
        raise ValueError(f"Secret {SECRET_NAME} has invalid format") from exc

    try:
        password = material["password"]
        salt = material["salt"]
        tweak = material["tweak"]
    except KeyError as exc:
        LOGGER.error("Invalid secret format — missing key: %s", exc)
        raise ValueError(f"Secret {SECRET_NAME} has invalid format: missing {exc}") from exc

    key = pbkdf2(
        password.encode("utf-8") if isinstance(password, str) else password,
        salt.encode("utf-8") if isinstance(salt, str) else salt,
        1024,
        keylen=32,
        prf="hmac-sha512",
    ).hex()

    cipher = FF3Cipher(key, tweak)
    _CIPHER_CACHE["cipher"] = cipher
    _CIPHER_CACHE["version_id"] = version_id
    return cipher


def _normalize_batch_input(payload: dict) -> list:
    """Accept either native Vault batch_input or the test_vault.py shape.

    - Native Vault shape: ``{"batch_input": [{"transformation": "...", "value": "..."}]}``
    - test_vault.py shape: ``{"transformationType": "...", "vaules": ["...", "..."]}``
    """
    if "batch_input" in payload and isinstance(payload["batch_input"], list):
        return payload["batch_input"]

    values = payload.get("vaules") or payload.get("values") or []
    transformation = payload.get("transformationType", "")
    return [{"transformation": transformation, "value": v} for v in values]


def encryption_handler(payload: dict, headers: dict) -> dict:
    """Perform FPE encryption on the supplied batch.

    Returns an API-Gateway Lambda-proxy response.
    """
    # Informational Vault headers (accepted but not validated per the spec).
    LOGGER.info(
        "Vault headers: namespace=%s token=%s request=%s",
        headers.get("X-Vault-Namespace") or headers.get("x-vault-namespace"),
        "***" if (headers.get("X-Vault-Token") or headers.get("x-vault-token")) else None,
        headers.get("X-Vault-Request") or headers.get("x-vault-request"),
    )

    batch_input = _normalize_batch_input(payload)
    if not batch_input:
        return _response(400, {"error": "batch_input is empty"})

    try:
        cipher = _load_cipher()
    except ClientError:
        return _response(500, {"error": "failed to retrieve encryption key material"})

    batch_results = []
    for item in batch_input:
        plaintext = str(item.get("value", ""))
        if not plaintext:
            return _response(400, {"error": "value missing from batch item"})
        try:
            ciphertext = cipher.encrypt(plaintext)
        except Exception as exc:
            LOGGER.exception("FF3 encryption failed")
            return _response(400, {"error": f"encryption failed: {exc}"})
        batch_results.append(ciphertext)

    body = {
        "encryptedData": {
            "data": {
                "batch_results": batch_results,
            }
        }
    }
    return _response(200, body)


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    """Lambda entry point."""
    headers = event.get("headers") or {}
    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError as exc:
        LOGGER.warning("Invalid JSON body: %s", exc)
        return _response(400, {"error": "invalid json body"})

    return encryption_handler(payload, headers)
