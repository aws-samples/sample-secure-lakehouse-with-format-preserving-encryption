# =============================================================================
# Common Layer — Outputs
# =============================================================================

# --- VPC ---

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

# --- Security Groups ---

output "lambda_security_group_id" {
  description = "ID of the Lambda security group"
  value       = aws_security_group.lambda.id
}

output "glue_security_group_id" {
  description = "ID of the Glue security group"
  value       = aws_security_group.glue.id
}

output "endpoints_security_group_id" {
  description = "ID of the VPC Endpoints security group"
  value       = aws_security_group.endpoints.id
}

# --- KMS ---

output "kms_key_arn" {
  description = "ARN of the shared KMS CMK"
  value       = aws_kms_key.shared.arn
}

output "kms_key_id" {
  description = "ID of the shared KMS CMK"
  value       = aws_kms_key.shared.key_id
}

# --- CloudWatch ---

output "log_group_arn" {
  description = "ARN of the centralized CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.pipeline.arn
}

output "log_group_name" {
  description = "Name of the centralized CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.pipeline.name
}

output "cloudwatch_write_policy_arn" {
  description = "ARN of the shared CloudWatch write policy"
  value       = aws_iam_policy.cloudwatch_write.arn
}

# --- VPC Endpoints ---

output "execute_api_vpc_endpoint_id" {
  description = "ID of the execute-api VPC endpoint"
  value       = aws_vpc_endpoint.interface["execute-api"].id
}

output "vpc_endpoints_ready" {
  depends_on = [
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3
  ]
  description = "Signals that all VPC endpoints are provisioned (use as depends_on anchor)"
  value       = true
}
