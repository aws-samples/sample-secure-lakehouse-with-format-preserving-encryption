# =============================================================================
# Vault Transform Service — Outputs
# =============================================================================

output "api_invoke_url" {
  description = "Invoke URL for the vault transform private API"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "glue_connection_name" {
  description = "Name of the Glue NETWORK connection for VPC access"
  value       = aws_glue_connection.network.name
}

output "assets_bucket_name" {
  description = "Name of the S3 assets bucket for Glue scripts"
  value       = aws_s3_bucket.assets.id
}

output "api_execution_arn" {
  description = "Execution ARN of the vault REST API (for IAM scoping in ingestion layer)"
  value       = aws_api_gateway_rest_api.vault.execution_arn
}

output "encryption_api_lambda_name" {
  description = "Function name of the encryption API Lambda (for CloudWatch alarm dimensions)"
  value       = aws_lambda_function.encryption_api.function_name
}

output "api_gateway_name" {
  description = "Name of the vault REST API (for CloudWatch ApiGateway alarm dimensions)"
  value       = aws_api_gateway_rest_api.vault.name
}

output "api_gateway_stage_name" {
  description = "Deployed stage name of the vault REST API (for CloudWatch ApiGateway alarm dimensions)"
  value       = aws_api_gateway_stage.prod.stage_name
}
