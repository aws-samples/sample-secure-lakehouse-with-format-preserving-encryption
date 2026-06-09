# =============================================================================
# Ingestion Layer — Input Variables
# =============================================================================

# --- Project ---

variable "project_name" {
  type        = string
  description = "Project name prefix for resource naming"
}

# --- Upstream module outputs ---

variable "quarantine_bucket_arn" {
  type        = string
  description = "ARN of the quarantine S3 bucket (from quarantine layer)"
}

variable "quarantine_bucket_name" {
  type        = string
  description = "Name of the quarantine S3 bucket (from quarantine layer)"
}

variable "event_object_key_prefix" {
  type        = string
  description = "S3 object key prefix that the EventBridge rule filters on (e.g. transaction/data/) so only objects under this prefix trigger the pipeline"
}

variable "metadata_bucket_arn" {
  type        = string
  description = "ARN of the metadata S3 bucket (contract)"
}

variable "metadata_bucket_name" {
  type        = string
  description = "Name of the metadata S3 bucket (contract)"
}

variable "object_key" {
  type        = string
  description = "csv file object key"
  default     = "cards/cards.csv"
}

variable "state_machine_arn" {
  type        = string
  description = "ARN of the Step Functions state machine (from orchestration layer)"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for SQS encryption (from common layer)"
}

variable "log_group_arn" {
  type        = string
  description = "ARN of the centralized CloudWatch Log Group (from common layer)"
}

variable "cloudwatch_write_policy_arn" {
  type        = string
  description = "ARN of the shared CloudWatch write policy (from common layer)"
}

# --- Network Configuration ---

variable "vpc_id" {
  type        = string
  description = "VPC ID for Lambda VPC config (from common layer)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for Lambda and Glue ENIs (from common layer)"
}

variable "lambda_security_group_id" {
  type        = string
  description = "Lambda security group ID (from common layer)"
}

# --- Vault Transform Service ---

variable "glue_connection_name" {
  type        = string
  description = "Glue connection name (from vault-transform-service)"
}

variable "vault_api_invoke_url" {
  type        = string
  description = "Vault transform service API invoke URL (from vault-transform-service)"
}

variable "vault_api_execution_arn" {
  type        = string
  description = "Vault API execution ARN for IAM scoping (from vault-transform-service)"
}

variable "assets_bucket_name" {
  type        = string
  description = "S3 assets bucket name from vault-transform-service for Glue scripts"
}

variable "dependency_archive_uri" {
  type        = string
  description = "S3 URI of the dependency archive (requirements.zip) for the Glue job --extra-py-files (from packager-layer)"
}

variable "bin_file_key" {
  type        = string
  description = "S3 key of the BIN file in the assets bucket (from packager-layer), passed to the Glue job as --bin_file_path"
}

# --- SQS Configuration ---

variable "sqs_queue_name" {
  type        = string
  description = "Base name for the SQS FIFO queue"
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
  description = "Maximum number of receives before routing to DLQ"
}

# --- Lambda Trigger Configuration ---

variable "lambda_trigger_name" {
  type        = string
  description = "Name of the Lambda Trigger function"
}

variable "lambda_trigger_runtime" {
  type        = string
  description = "Runtime for the Lambda Trigger function (e.g. python3.12)"
}

variable "lambda_trigger_timeout" {
  type        = number
  description = "Timeout in seconds for the Lambda Trigger function"
}

variable "lambda_trigger_memory_size" {
  type        = number
  description = "Memory allocation in MB for the Lambda Trigger function"
}

# --- Glue Job Configuration ---

variable "glue_job_name" {
  type        = string
  description = "Name of the Glue encryption job"
}

variable "glue_worker_type" {
  type        = string
  description = "Glue worker type (e.g. G.1X, G.2X)"
}

variable "glue_number_of_workers" {
  type        = number
  description = "Number of Glue workers"
}

variable "glue_timeout" {
  type        = number
  description = "Glue job timeout in minutes"
}

variable "glue_max_retries" {
  type        = number
  description = "Glue job max retries"
}
