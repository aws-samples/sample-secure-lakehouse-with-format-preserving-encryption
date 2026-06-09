"""Copy Lambda — moves encrypted files from quarantine to landing bucket.

Spark writes output as a directory with part files:
  s3://quarantine/<parent>/encrypted/<filename>/part-00000-xxxxx.csv.bz2

This Lambda:
1. Lists objects under the encrypted prefix
2. Finds the actual data file (ignores _SUCCESS, _committed, etc.)
3. Copies it to landing as <parent>/<filename>.bz2
4. Cleans up quarantine (encrypted dir + original file)
"""

import os
import logging

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")

# Validate required environment variables at cold start
QUARANTINE_BUCKET = os.environ.get("QUARANTINE_BUCKET")
LANDING_BUCKET = os.environ.get("LANDING_BUCKET")

if not QUARANTINE_BUCKET:
    raise RuntimeError("QUARANTINE_BUCKET environment variable is not set")
if not LANDING_BUCKET:
    raise RuntimeError("LANDING_BUCKET environment variable is not set")


def _find_data_file(bucket, prefix):
    """List objects under prefix and return the actual data file key (the part file).

    Skips Spark metadata files like _SUCCESS, _committed_*, .crc files.
    """
    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    contents = response.get("Contents", [])

    skip_patterns = ("_SUCCESS", "_committed", "_started", ".crc")

    for obj in contents:
        key = obj["Key"]
        filename = key.split("/")[-1]
        if not any(filename.startswith(p) or filename.endswith(p) for p in skip_patterns):
            return key

    return None


def _delete_prefix(bucket, prefix):
    """Delete all objects under a prefix (Spark output directory cleanup)."""
    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    contents = response.get("Contents", [])

    if contents:
        delete_objects = [{"Key": obj["Key"]} for obj in contents]
        s3_client.delete_objects(Bucket=bucket, Delete={"Objects": delete_objects})
        logger.info("Deleted %d objects under s3://%s/%s", len(delete_objects), bucket, prefix)


def handler(event, context):
    """Copy encrypted file from quarantine to landing, then clean up quarantine."""
    source_bucket = event.get("source_bucket", QUARANTINE_BUCKET)
    source_key = event.get("source_key")

    if not source_key:
        raise ValueError("source_key is required in the event payload")

    # Derive the encrypted output prefix (Spark directory)
    path_parts = source_key.split("/")
    file_name = path_parts[-1]
    parent_path = "/".join(path_parts[:-1])
    encrypted_prefix = f"{parent_path}/encrypted/{file_name}/" if parent_path else f"encrypted/{file_name}/"

    logger.info("Looking for encrypted output under s3://%s/%s", source_bucket, encrypted_prefix)

    try:
        # Find the actual data file in the Spark output directory
        data_file_key = _find_data_file(source_bucket, encrypted_prefix)

        if not data_file_key:
            raise FileNotFoundError(f"No data file found under s3://{source_bucket}/{encrypted_prefix}")

        logger.info("Found data file: s3://%s/%s", source_bucket, data_file_key)

        # Determine the landing key — strip the original extension, add .bz2
        base_name = file_name.rsplit(".", 1)[0] if "." in file_name else file_name
        landing_key = f"{parent_path}/{base_name}.csv.bz2" if parent_path else f"{base_name}.csv.bz2"

        logger.info("Copying to s3://%s/%s", LANDING_BUCKET, landing_key)

        # Copy encrypted part file to landing with clean name
        s3_client.copy_object(
            Bucket=LANDING_BUCKET,
            Key=landing_key,
            CopySource={"Bucket": source_bucket, "Key": data_file_key},
        )

        # Clean up: delete the entire Spark output directory
        _delete_prefix(source_bucket, encrypted_prefix)

        # Clean up: delete the original unencrypted file
        s3_client.delete_object(Bucket=source_bucket, Key=source_key)

    except (ClientError, FileNotFoundError) as exc:
        logger.error("Failed for source_key %s: %s", source_key, exc)
        raise

    logger.info("Successfully moved encrypted data to s3://%s/%s and cleaned up quarantine", LANDING_BUCKET, landing_key)

    return {
        "statusCode": 200,
        "body": f"Copied encrypted {source_key} to s3://{LANDING_BUCKET}/{landing_key}",
    }
