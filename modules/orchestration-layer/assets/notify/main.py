"""
Notification formatter Lambda.

Invoked by the Step Functions pipeline workflow at the end of a run (success or
failure). Builds a human-readable, detailed email body from the execution
context and publishes it to the pipeline SNS topic.

Expected event shape (supplied by the state machine):
    {
        "status": "SUCCESS" | "FAILED",
        "source_bucket": "<bucket>",
        "source_key": "<key>",
        "execution_name": "<sfn execution name>",
        "execution_id": "<sfn execution arn>",
        "start_time": "<iso8601>",
        "state_machine": "<state machine name>",
        "error_info": { ... }        # present only when status == FAILED
    }
"""

import json
import os

import boto3

sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

# Ordered list of the steps the pipeline performs, surfaced in the success mail
# so the recipient understands exactly what happened to their file.
PIPELINE_STEPS = [
    "Glue job detected PCI-sensitive fields (Luhn check + BIN lookup + regex)",
    "Format-Preserving Encryption (FF3-1) applied to sensitive columns",
    "Encrypted output written to the quarantine bucket under /encrypted",
    "Copy Lambda moved the encrypted file to the landing bucket",
    "Original source file removed from the quarantine bucket",
]


def _divider(char="=", width=60):
    return char * width


def _kv(label, value, pad=16):
    return f"{label.ljust(pad)}{value}"


def _build_success_message(event):
    lines = [
        _divider(),
        "  FPE ENCRYPTION PIPELINE - EXECUTION REPORT",
        _divider(),
        "",
        "Status: SUCCESS",
        "",
        "-- Execution --",
        _kv("State Machine:", event.get("state_machine", "n/a")),
        _kv("Execution:", event.get("execution_name", "n/a")),
        _kv("Started:", event.get("start_time", "n/a")),
        "",
        "-- Input File --",
        _kv("Source Bucket:", event.get("source_bucket", "n/a")),
        _kv("Source Key:", event.get("source_key", "n/a")),
        "",
        "-- Steps Completed --",
    ]
    for idx, step in enumerate(PIPELINE_STEPS, start=1):
        lines.append(f"  {idx}. {step}")
    lines += [
        "",
        "No action required. The encrypted file is available in the landing",
        "bucket and ready for downstream Lakehouse consumption.",
        "",
        _divider(),
    ]
    return "\n".join(lines)


def _parse_error(error_info):
    """
    Reduce the raw Catch payload to a few human-readable fields.

    Step Functions delivers errors as {"Error": ..., "Cause": ...} where Cause is
    usually a JSON-encoded string. For the Glue .sync integration that Cause is
    the full job-run object, whose useful signal is the ErrorMessage plus a
    handful of identifiers. We surface those and drop the rest of the noise.
    """
    error_type = "Unknown"
    message = ""
    details = {}

    if not isinstance(error_info, dict):
        return error_type, str(error_info), details

    error_type = error_info.get("Error", "Unknown")
    cause_raw = error_info.get("Cause", "")

    cause_obj = cause_raw
    if isinstance(cause_raw, str):
        try:
            cause_obj = json.loads(cause_raw)
        except (ValueError, TypeError):
            cause_obj = cause_raw

    if isinstance(cause_obj, dict):
        # Glue job-run shape: pull the error message and key identifiers.
        message = cause_obj.get("ErrorMessage") or cause_obj.get("errorMessage") or ""
        for label, key in (
            ("Glue Job", "JobName"),
            ("Job Run ID", "Id"),
            ("Job State", "JobRunState"),
        ):
            if cause_obj.get(key):
                details[label] = cause_obj[key]
        # Non-Glue causes: fall back to the whole object when no message found.
        if not message:
            message = json.dumps(cause_obj, indent=2)
    else:
        message = str(cause_obj)

    return error_type, message.strip(), details


def _build_failure_message(event):
    error_type, error_message, error_details = _parse_error(event.get("error_info", {}))

    lines = [
        _divider(),
        "  FPE ENCRYPTION PIPELINE - EXECUTION REPORT",
        _divider(),
        "",
        "Status: FAILED",
        "",
        "-- Execution --",
        _kv("State Machine:", event.get("state_machine", "n/a")),
        _kv("Execution:", event.get("execution_name", "n/a")),
        _kv("Started:", event.get("start_time", "n/a")),
        "",
        "-- Input File --",
        _kv("Source Bucket:", event.get("source_bucket", "n/a")),
        _kv("Source Key:", event.get("source_key", "n/a")),
        "",
        "-- Error --",
        _kv("Type:", error_type),
    ]
    for label, value in error_details.items():
        lines.append(_kv(f"{label}:", value))
    lines += [
        "",
        "Message:",
        error_message or "  (no error message provided)",
        "",
        "Action required: the source file remains in the quarantine bucket and",
        "was NOT delivered to the landing bucket. Review the Step Functions",
        "execution and CloudWatch Logs, then re-upload the file to retry.",
        "",
        _divider(),
    ]
    return "\n".join(lines)


def handler(event, context):
    status = (event.get("status") or "").upper()
    source_key = event.get("source_key", "n/a")

    if status == "SUCCESS":
        subject = "[SUCCESS] FPE Pipeline - File Encrypted"
        message = _build_success_message(event)
    else:
        subject = "[FAILED] FPE Pipeline - Execution Error"
        message = _build_failure_message(event)

    # SNS subjects are capped at 100 chars and cannot contain newlines.
    subject = subject[:100]

    response = sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject,
        Message=message,
    )

    return {
        "published": True,
        "message_id": response.get("MessageId"),
        "status": status,
        "source_key": source_key,
    }
