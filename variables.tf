# =============================================================================
# Root Module Variables
# All values supplied via terraform.tfvars — no defaults declared.
# =============================================================================

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS region for provider configuration and resource deployment"
}

# -----------------------------------------------------------------------------
# Common Layer
# -----------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Project name prefix for resource naming (e.g. enc-blog)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones for private subnets"
}

variable "log_group_name" {
  type        = string
  description = "Name of the centralized CloudWatch Log Group for pipeline logging"
}

variable "log_retention_in_days" {
  type        = number
  description = "Number of days to retain logs in the CloudWatch Log Group"
}

variable "kms_key_alias" {
  type        = string
  description = "Alias for the KMS Customer Managed Key used for S3 SSE-KMS encryption"
}

# -----------------------------------------------------------------------------
# Quarantine Layer
# -----------------------------------------------------------------------------

variable "quarantine_bucket_name" {
  type        = string
  description = "Name of the S3 quarantine bucket where raw files are deposited for processing"
}

variable "quarantine_expiration_days" {
  type        = number
  description = "Days after creation before objects in the quarantine bucket expire, bounding the plaintext-persistence window"
}

variable "quarantine_noncurrent_expiration_days" {
  type        = number
  description = "Days before noncurrent object versions in the quarantine bucket are permanently deleted"
}

# -----------------------------------------------------------------------------
# Quarantine Ops Admin (break-glass cleanup) Role
# -----------------------------------------------------------------------------

variable "ops_admin_external_id" {
  type        = string
  description = "External ID required to assume the quarantine Ops Admin cleanup role"
}

variable "ops_admin_max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds for the quarantine Ops Admin role (time-bound access)"
}

# -----------------------------------------------------------------------------
# Landing Layer
# -----------------------------------------------------------------------------

variable "landing_bucket_name" {
  type        = string
  description = "Name of the S3 landing bucket where encrypted files are stored for downstream consumption"
}

# -----------------------------------------------------------------------------
# Ingestion Layer — SQS
# -----------------------------------------------------------------------------

variable "sqs_queue_name" {
  type        = string
  description = "Base name for the SQS FIFO queue used to buffer S3 event notifications"
}

variable "sqs_visibility_timeout" {
  type        = number
  description = "Visibility timeout in seconds for the SQS FIFO queue"
}

variable "sqs_message_retention" {
  type        = number
  description = "Message retention period in seconds for the SQS FIFO queue"
}

variable "sqs_max_receive_count" {
  type        = number
  description = "Maximum number of receives before a message is sent to the dead-letter queue"
}

# -----------------------------------------------------------------------------
# Ingestion Layer — Lambda Trigger
# -----------------------------------------------------------------------------

variable "event_object_key_prefix" {
  type        = string
  description = "S3 object key prefix the EventBridge rule filters on (e.g. transaction/data/) so only objects under this prefix trigger the pipeline"
}

variable "lambda_trigger_name" {
  type        = string
  description = "Name of the Lambda function that polls SQS and starts Step Functions execution"
}

variable "lambda_trigger_runtime" {
  type        = string
  description = "Runtime identifier for the Lambda Trigger function (e.g. python3.12)"
}

variable "lambda_trigger_timeout" {
  type        = number
  description = "Timeout in seconds for the Lambda Trigger function"
}

variable "lambda_trigger_memory_size" {
  type        = number
  description = "Memory allocation in MB for the Lambda Trigger function"
}

# -----------------------------------------------------------------------------
# Orchestration Layer — Step Functions
# -----------------------------------------------------------------------------

variable "state_machine_name" {
  type        = string
  description = "Name of the Step Functions state machine that orchestrates the pipeline"
}

variable "sns_topic_name" {
  type        = string
  description = "Name of the SNS topic for pipeline failure notifications"
}

variable "notification_email" {
  type        = string
  description = "Email address to receive pipeline failure notifications"
}

variable "notify_lambda_name" {
  type        = string
  description = "Name of the notification formatter Lambda function"
}

variable "notify_lambda_runtime" {
  type        = string
  description = "Runtime identifier for the notification Lambda (e.g. python3.12)"
}

variable "notify_lambda_timeout" {
  type        = number
  description = "Timeout in seconds for the notification Lambda"
}

variable "notify_lambda_memory_size" {
  type        = number
  description = "Memory allocation in MB for the notification Lambda"
}

# -----------------------------------------------------------------------------
# Ingestion Layer — Glue
# -----------------------------------------------------------------------------

variable "glue_job_name" {
  type        = string
  description = "Name of the AWS Glue job for sensitive data detection and FPE encryption"
}

variable "glue_worker_type" {
  type        = string
  description = "Worker type for the Glue job (e.g. G.1X, G.2X)"
}

variable "glue_number_of_workers" {
  type        = number
  description = "Number of workers allocated to the Glue job"
}

variable "glue_timeout" {
  type        = number
  description = "Timeout in minutes for the Glue job execution"
}

variable "encryption_chunk_size" {
  type        = number
  description = "Number of card values batched into each encryption API request. Tune against measured p99 Lambda duration so a chunk completes well inside the API Gateway integration timeout."
}

variable "glue_max_retries" {
  type        = number
  description = "Maximum number of retries for the Glue job on failure"
}

# -----------------------------------------------------------------------------
# Landing Layer — Copy Lambda
# -----------------------------------------------------------------------------

variable "copy_lambda_name" {
  type        = string
  description = "Name of the Copy Lambda function that moves encrypted files to the landing bucket"
}

variable "copy_lambda_runtime" {
  type        = string
  description = "Runtime identifier for the Copy Lambda function (e.g. python3.12)"
}

variable "copy_lambda_timeout" {
  type        = number
  description = "Timeout in seconds for the Copy Lambda function"
}

variable "copy_lambda_memory_size" {
  type        = number
  description = "Memory allocation in MB for the Copy Lambda function"
}

# -----------------------------------------------------------------------------
# Vault Transform Service — Lambda
# -----------------------------------------------------------------------------

variable "lambda_runtime" {
  type        = string
  description = "Runtime identifier for Vault Transform Service Lambda functions (e.g. python3.12)"
}

variable "encryption_lambda_timeout" {
  type        = number
  description = "Timeout in seconds for the encryption API Lambda. Keep this strictly below the API Gateway integration timeout (29s by default) so the function fails first and records its own timeout instead of being cut off mid-execution."
}

variable "secret_generator_lambda_timeout" {
  type        = number
  description = "Timeout in seconds for the one-shot secret generator Lambda, which only writes FPE key material to Secrets Manager"
}

variable "lambda_memory_size" {
  type        = number
  description = "Memory allocation in MB for Vault Transform Service Lambda functions"
}

# -----------------------------------------------------------------------------
# Packager Layer — Dependency Packager
# -----------------------------------------------------------------------------

variable "packager_requirements_path" {
  type        = string
  description = "Path (relative to repo root) to the requirements.txt bundled by the dependency packager"
}

variable "packager_shared_modules_dir" {
  type        = string
  description = "Directory (relative to repo root) holding the shared Python modules bundled into the dependency archive. All *.py here (except the main job script) are bundled, and any change re-triggers packaging."
}

variable "packager_main_script_name" {
  type        = string
  description = "Name of the main Glue job script within packager_shared_modules_dir to exclude from the bundled archive (delivered separately as the job script_location)."
}

variable "packager_artifacts_prefix" {
  type        = string
  description = "S3 key prefix under which the dependency archive is uploaded"
}

variable "packager_bin_file_path" {
  type        = string
  description = "Path (relative to repo root) to the BIN list file uploaded to the assets bucket for the Glue job"
}

variable "packager_bin_file_prefix" {
  type        = string
  description = "S3 key prefix under which the BIN file is uploaded in the assets bucket"
}

# -----------------------------------------------------------------------------
# Monitoring Layer — CloudWatch Alarms
# -----------------------------------------------------------------------------

variable "alarm_period_seconds" {
  type        = number
  description = "Evaluation period in seconds for CloudWatch metric alarms"
}

variable "alarm_evaluation_periods" {
  type        = number
  description = "Number of periods evaluated before a CloudWatch alarm changes state"
}

variable "dlq_depth_threshold" {
  type        = number
  description = "Alarm when the SQS DLQ has at least this many visible messages"
}

variable "sfn_failed_threshold" {
  type        = number
  description = "Alarm when Step Functions failed executions reach this value in a period"
}

variable "glue_failed_threshold" {
  type        = number
  description = "Alarm when Glue failed tasks reach this value in a period"
}

variable "lambda_error_threshold" {
  type        = number
  description = "Alarm when a Lambda reports at least this many errors in a period"
}

variable "lambda_throttle_threshold" {
  type        = number
  description = "Alarm when a Lambda reports at least this many throttles in a period"
}

variable "encryption_lambda_duration_threshold_ms" {
  type        = number
  description = "Alarm when the encryption API Lambda average duration (ms) exceeds this value. Keep below the API Gateway 29s integration timeout."
}

variable "apigw_5xx_threshold" {
  type        = number
  description = "Alarm when the vault API reports at least this many 5XX responses in a period"
}

variable "apigw_latency_threshold_ms" {
  type        = number
  description = "Alarm when the vault API average latency (ms) exceeds this value"
}
