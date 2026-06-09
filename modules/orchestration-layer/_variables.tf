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
