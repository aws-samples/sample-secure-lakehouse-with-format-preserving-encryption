# =============================================================================
# Terraform Variable Values
# All resource configuration values — zero hardcoded values in .tf files.
# =============================================================================

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

aws_region = "us-east-1"

# -----------------------------------------------------------------------------
# Common Layer
# -----------------------------------------------------------------------------

project_name          = "enc-blog"
vpc_cidr              = "10.0.0.0/16"
az_count              = 2
kms_key_alias         = "enc-blog-kms-s3-encryption-key"
log_group_name        = "enc-blog-cw-pipeline-log-group"
log_retention_in_days = 30

# -----------------------------------------------------------------------------
# Quarantine Layer
# -----------------------------------------------------------------------------

# Note: account-id is appended at runtime via aws_caller_identity data source
quarantine_bucket_name = "enc-blog-s3-quarantine-bucket"

# Lifecycle: bound how long raw (plaintext) data may persist in the CDE bucket.
# 1 day expiration keeps unprocessed PANs from lingering; noncurrent versions
# are purged shortly after they are superseded.
quarantine_expiration_days            = 1
quarantine_noncurrent_expiration_days = 1

# Ops Admin (break-glass) cleanup role — time-bound access to the CDE bucket.
# Rotate the external ID per engagement; 1-hour (3600s) session cap.
ops_admin_external_id          = "enc-blog-quarantine-cleanup"
ops_admin_max_session_duration = 3600

# -----------------------------------------------------------------------------
# Landing Layer
# -----------------------------------------------------------------------------

# Note: account-id is appended at runtime via aws_caller_identity data source
landing_bucket_name = "enc-blog-s3-landing-bucket"

# -----------------------------------------------------------------------------
# Ingestion Layer — SQS
# -----------------------------------------------------------------------------

sqs_queue_name         = "enc-blog-sqs-pipeline-queue"
sqs_visibility_timeout = 300
sqs_message_retention  = 345600
sqs_max_receive_count  = 3

# EventBridge only triggers the pipeline for objects under this key prefix.
event_object_key_prefix = "transaction/data/"

# -----------------------------------------------------------------------------
# Ingestion Layer — Lambda Trigger
# -----------------------------------------------------------------------------

lambda_trigger_name        = "enc-blog-lambda-trigger-function"
lambda_trigger_runtime     = "python3.12"
lambda_trigger_timeout     = 60
lambda_trigger_memory_size = 128

# -----------------------------------------------------------------------------
# Orchestration Layer — Step Functions
# -----------------------------------------------------------------------------

state_machine_name = "enc-blog-sfn-pipeline-workflow"

# SNS topic for pipeline failure notifications
sns_topic_name     = "enc-blog-sns-pipeline-failure-topic"
notification_email = "iamsudh@amazon.com"

# Notification formatter Lambda
notify_lambda_name        = "enc-blog-lambda-notification-function"
notify_lambda_runtime     = "python3.12"
notify_lambda_timeout     = 30
notify_lambda_memory_size = 128

# -----------------------------------------------------------------------------
# Ingestion Layer — Glue
# -----------------------------------------------------------------------------

glue_job_name          = "enc-blog-glue-encryption-job"
glue_worker_type       = "G.1X"
glue_number_of_workers = 2
glue_timeout           = 60
glue_max_retries       = 0

# Card values batched into each encryption API request. Raise gradually during load
# testing, keeping p99 Lambda duration well under the API Gateway integration timeout.
encryption_chunk_size = 15000

# -----------------------------------------------------------------------------
# Landing Layer — Copy Lambda
# -----------------------------------------------------------------------------

copy_lambda_name        = "enc-blog-lambda-copy-function"
copy_lambda_runtime     = "python3.12"
copy_lambda_timeout     = 60
copy_lambda_memory_size = 128

# -----------------------------------------------------------------------------
# Vault Transform Service — Lambda
# -----------------------------------------------------------------------------

lambda_runtime     = "python3.12"
lambda_memory_size = 256

# Strictly below the 29s API Gateway integration timeout so the Lambda fails first and
# records its own timeout, rather than being cut off mid-execution while still billing.
encryption_lambda_timeout = 28

# One-shot key material seeding; completes in well under a second.
secret_generator_lambda_timeout = 30

# -----------------------------------------------------------------------------
# Packager Layer — Dependency Packager
# -----------------------------------------------------------------------------

# requirements.txt lives under the packager-layer assets; shared modules are
# bundled from the ingestion-layer glue assets. The archive is uploaded to the
# quarantine bucket under the artifacts/ prefix.
# All *.py in packager_shared_modules_dir (except packager_main_script_name) are
# bundled; editing/adding/removing any of them re-triggers packaging on apply.
packager_requirements_path  = "modules/packager-layer/assets/requirements.txt"
packager_shared_modules_dir = "modules/ingestion-layer/assets/glue_encryption"
packager_main_script_name   = "encryption.py"
packager_artifacts_prefix   = "artifacts"

# BIN file: uploaded to the assets bucket under the bin_file/ prefix. Any edit to
# the local file re-uploads it on the next apply (etag = filemd5).
packager_bin_file_path   = "modules/ingestion-layer/assets/data/bin-file.csv"
packager_bin_file_prefix = "bin_file"

# -----------------------------------------------------------------------------
# Monitoring Layer — CloudWatch Alarms
# -----------------------------------------------------------------------------

# Common evaluation window: 5-minute periods, single period to breach.
alarm_period_seconds     = 300
alarm_evaluation_periods = 1

# Any parked event in the DLQ, any failed workflow/Glue task, and any Lambda
# error or throttle is worth a notification in this pipeline.
dlq_depth_threshold       = 1
sfn_failed_threshold      = 1
glue_failed_threshold     = 1
lambda_error_threshold    = 1
lambda_throttle_threshold = 1

# Encryption API Lambda duration: warn well before the 28s Lambda timeout / 29s
# API Gateway integration timeout (25s = 25000 ms).
encryption_lambda_duration_threshold_ms = 25000

# Vault API: any 5XX is notable; average latency budget 10s (10000 ms).
apigw_5xx_threshold        = 1
apigw_latency_threshold_ms = 10000
