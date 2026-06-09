# =============================================================================
# Common Layer — Input Variables
# =============================================================================

variable "project_name" {
  type        = string
  description = "Project name prefix for resource naming"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones for private subnets"
}

variable "kms_key_alias" {
  type        = string
  description = "Alias for the shared KMS CMK (without the alias/ prefix)"
}

variable "log_group_name" {
  type        = string
  description = "Name of the centralized CloudWatch Log Group for pipeline logging"
}

variable "log_retention_in_days" {
  type        = number
  description = "Number of days to retain logs in the CloudWatch Log Group"
}
