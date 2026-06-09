# =============================================================================
# Landing Layer — Outputs
# =============================================================================

output "landing_bucket_arn" {
  description = "ARN of the landing S3 bucket"
  value       = aws_s3_bucket.landing.arn
}

output "landing_bucket_name" {
  description = "Name of the landing S3 bucket"
  value       = aws_s3_bucket.landing.id
}

output "copy_lambda_arn" {
  description = "ARN of the Copy Lambda function"
  value       = aws_lambda_function.copy.arn
}

output "copy_lambda_function_name" {
  description = "Function name of the Copy Lambda"
  value       = aws_lambda_function.copy.function_name
}
