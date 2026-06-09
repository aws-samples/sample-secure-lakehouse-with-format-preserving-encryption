# =============================================================================
# Root Module — Outputs
# Exposes key resource identifiers from child modules
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.common_layer.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.common_layer.private_subnet_ids
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the shared KMS CMK"
  value       = module.common_layer.kms_key_arn
}

# -----------------------------------------------------------------------------
# S3 — Quarantine
# -----------------------------------------------------------------------------

output "quarantine_bucket_arn" {
  description = "ARN of the quarantine S3 bucket"
  value       = module.quarantine_layer.quarantine_bucket_arn
}

output "quarantine_bucket_name" {
  description = "Name of the quarantine S3 bucket"
  value       = module.quarantine_layer.quarantine_bucket_name
}

# -----------------------------------------------------------------------------
# S3 — Landing
# -----------------------------------------------------------------------------

output "landing_bucket_arn" {
  description = "ARN of the landing S3 bucket"
  value       = module.landing_layer.landing_bucket_arn
}

output "landing_bucket_name" {
  description = "Name of the landing S3 bucket"
  value       = module.landing_layer.landing_bucket_name
}

# -----------------------------------------------------------------------------
# Lambda
# -----------------------------------------------------------------------------

output "copy_lambda_arn" {
  description = "ARN of the Copy Lambda function"
  value       = module.landing_layer.copy_lambda_arn
}

output "lambda_trigger_arn" {
  description = "ARN of the Lambda Trigger function"
  value       = module.ingestion_layer.lambda_trigger_arn
}

# -----------------------------------------------------------------------------
# SQS
# -----------------------------------------------------------------------------

output "sqs_queue_arn" {
  description = "ARN of the SQS FIFO queue"
  value       = module.ingestion_layer.sqs_queue_arn
}

output "sqs_queue_url" {
  description = "URL of the SQS FIFO queue"
  value       = module.ingestion_layer.sqs_queue_url
}

output "dlq_arn" {
  description = "ARN of the SQS Dead Letter Queue"
  value       = module.ingestion_layer.dlq_arn
}

# -----------------------------------------------------------------------------
# Glue
# -----------------------------------------------------------------------------

output "glue_job_arn" {
  description = "ARN of the Glue encryption job"
  value       = module.ingestion_layer.glue_job_arn
}

output "glue_job_name" {
  description = "Name of the Glue encryption job"
  value       = module.ingestion_layer.glue_job_name
}

# -----------------------------------------------------------------------------
# Step Functions
# -----------------------------------------------------------------------------

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = module.orchestration_layer.state_machine_arn
}

# -----------------------------------------------------------------------------
# Vault Transform Service
# -----------------------------------------------------------------------------

output "api_invoke_url" {
  description = "Invoke URL for the vault transform private API"
  value       = module.vault_transform_service.api_invoke_url
}

output "glue_connection_name" {
  description = "Name of the Glue NETWORK connection for VPC access"
  value       = module.vault_transform_service.glue_connection_name
}

output "assets_bucket_name" {
  description = "Name of the S3 assets bucket for Glue scripts"
  value       = module.vault_transform_service.assets_bucket_name
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------

output "log_group_arn" {
  description = "ARN of the centralized CloudWatch Log Group"
  value       = module.common_layer.log_group_arn
}

output "cloudwatch_write_policy_arn" {
  description = "ARN of the shared CloudWatch write policy"
  value       = module.common_layer.cloudwatch_write_policy_arn
}
