"""Lambda Trigger — polls SQS FIFO and starts Step Functions execution."""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn_client = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ.get("STATE_MACHINE_ARN")
if not STATE_MACHINE_ARN:
    raise RuntimeError("STATE_MACHINE_ARN environment variable is not set")

GLUE_JOB_NAME = os.environ.get("GLUE_JOB_NAME")
if not GLUE_JOB_NAME:
    raise RuntimeError("GLUE_JOB_NAME environment variable is not set")

# The source bucket/key are derived from each SQS message body (the EventBridge
# "Object Created" event), so QUARANTINE_BUCKET is no longer required here.


def _extract_source(body):
    """Extract the source bucket and object key from an SQS message body.

    The body is the EventBridge "Object Created" event delivered via SQS, whose
    shape is:
        {"detail": {"bucket": {"name": ...}, "object": {"key": ...}}}

    Returns:
        (source_bucket, source_key) tuple.

    Raises:
        ValueError: if either the bucket name or the object key is missing.
    """
    detail = body.get("detail", {})
    source_bucket = detail.get("bucket", {}).get("name")
    source_key = detail.get("object", {}).get("key")

    if not source_bucket:
        raise ValueError("source bucket name missing from message body")
    if not source_key:
        raise ValueError("source object key missing from message body")

    return source_bucket, source_key


def handler(event, context):
    """Process SQS messages and start Step Functions executions."""
    logger.info("Received %d record(s) from SQS", len(event.get("Records", [])))

    batch_item_failures = []

    for record in event.get("Records", []):
        message_id = record.get("messageId")
        logger.info("Processing message: %s", message_id)

        try:
            body = json.loads(record.get("body", "{}"))
            logger.info("Message body: %s", json.dumps(body))

            # Derive the source bucket and key strictly from the SQS message body.
            source_bucket, source_key = _extract_source(body)

            logger.info("Starting Step Functions execution for s3://%s/%s", source_bucket, source_key)

            # Start Step Functions execution
            sfn_input = json.dumps({
                "source_bucket": source_bucket,
                "source_key": source_key,
                "glue_job_name": GLUE_JOB_NAME,
            })

            logger.info(f"Input passed to stepfunction is {sfn_input}")

            response = sfn_client.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                input=sfn_input,
            )

            logger.info(
                "Started execution %s for message %s",
                response.get("executionArn"),
                message_id,
            )

        except ValueError as exc:
            logger.error("Invalid message %s: %s", message_id, exc)
            batch_item_failures.append({"itemIdentifier": message_id})

        except (ClientError, json.JSONDecodeError, KeyError) as exc:
            logger.error("Failed to process message %s: %s", message_id, exc)
            batch_item_failures.append({"itemIdentifier": message_id})

    logger.info("Batch complete. Failures: %d", len(batch_item_failures))

    return {"batchItemFailures": batch_item_failures}
