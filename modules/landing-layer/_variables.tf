# =============================================================================
# Landing Layer — Input Variables
# =============================================================================

variable "landing_bucket_name" {
  type        = string
  description = "Name of the landing S3 bucket"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the shared CMK from common layer"
}

variable "quarantine_bucket_arn" {
  type        = string
  description = "ARN of the quarantine bucket (for Copy Lambda read/delete)"
}

variable "quarantine_bucket_name" {
  type        = string
  description = "Name of the quarantine bucket (for Copy Lambda env var)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for Lambda VPC config"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for Lambda ENIs"
}

variable "lambda_security_group_id" {
  type        = string
  description = "Lambda security group ID"
}

variable "log_group_arn" {
  type        = string
  description = "CloudWatch log group ARN"
}

variable "cloudwatch_write_policy_arn" {
  type        = string
  description = "ARN of shared CloudWatch write policy"
}

variable "copy_lambda_name" {
  type        = string
  description = "Name of the Copy Lambda function"
}

variable "copy_lambda_runtime" {
  type        = string
  description = "Runtime for Copy Lambda"
}

variable "copy_lambda_timeout" {
  type        = number
  description = "Timeout in seconds"
}

variable "copy_lambda_memory_size" {
  type        = number
  description = "Memory in MB"
}
