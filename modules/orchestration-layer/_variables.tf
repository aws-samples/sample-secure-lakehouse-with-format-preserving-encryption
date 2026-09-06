# =============================================================================
# Orchestration Layer — Input Variables
# =============================================================================

variable "glue_job_arn" {
  type        = string
  description = "Glue Job ARN from ingestion layer"
}

variable "glue_job_name" {
  type        = string
  description = "Glue Job name from ingestion layer"
}

variable "copy_lambda_arn" {
  type        = string
  description = "Copy Lambda ARN from landing layer"
}

variable "copy_lambda_function_name" {
  type        = string
  description = "Copy Lambda function name from landing layer"
}

variable "log_group_arn" {
  type        = string
  description = "CloudWatch log group ARN"
}

variable "state_machine_name" {
  type        = string
  description = "Step Functions state machine name"
}

variable "cloudwatch_write_policy_arn" {
  type        = string
  description = "ARN of shared CloudWatch write policy"
}

# -----------------------------------------------------------------------------
# SNS — Failure Notifications
# -----------------------------------------------------------------------------

variable "sns_topic_name" {
  type        = string
  description = "Name of the SNS topic for pipeline failure notifications"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting the SNS topic at rest"
}

variable "notification_email" {
  type        = string
  description = "Email address to receive pipeline failure notifications via SNS"
}

# -----------------------------------------------------------------------------
# Notification Formatter Lambda
# -----------------------------------------------------------------------------

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the notification Lambda VPC configuration"
}

variable "lambda_security_group_id" {
  type        = string
  description = "Security group ID for the notification Lambda"
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
