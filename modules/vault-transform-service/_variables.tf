# =============================================================================
# Vault Transform Service — Input Variables
# =============================================================================

variable "vpc_id" {
  type        = string
  description = "VPC ID from common layer"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from common layer"
}

variable "lambda_security_group_id" {
  type        = string
  description = "Lambda SG ID from common layer"
}

variable "glue_security_group_id" {
  type        = string
  description = "Glue SG ID from common layer"
}

variable "endpoints_security_group_id" {
  type        = string
  description = "Endpoints SG ID from common layer"
}

variable "execute_api_vpc_endpoint_id" {
  type        = string
  description = "execute-api VPC endpoint ID from common layer"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN from common layer"
}

variable "log_group_arn" {
  type        = string
  description = "CloudWatch log group ARN from common layer"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "lambda_runtime" {
  type        = string
  description = "Lambda runtime version"
}

variable "lambda_timeout" {
  type        = number
  description = "Lambda timeout in seconds"
}

variable "lambda_memory_size" {
  type        = number
  description = "Lambda memory in MB"
}

variable "cloudwatch_write_policy_arn" {
  type        = string
  description = "ARN of shared CloudWatch write policy from common layer"
}
