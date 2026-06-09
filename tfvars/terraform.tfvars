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

# -----------------------------------------------------------------------------
# Ingestion Layer — Glue
# -----------------------------------------------------------------------------

glue_job_name          = "enc-blog-glue-encryption-job"
glue_worker_type       = "G.1X"
glue_number_of_workers = 2
glue_timeout           = 60
glue_max_retries       = 0

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
lambda_timeout     = 30
lambda_memory_size = 256

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
