# =============================================================================
# Quarantine Layer — Outputs
# =============================================================================

output "quarantine_bucket_arn" {
  description = "ARN of the quarantine S3 bucket"
  value       = aws_s3_bucket.quarantine.arn
}

output "quarantine_bucket_name" {
  description = "Name of the quarantine S3 bucket"
  value       = aws_s3_bucket.quarantine.id
}
