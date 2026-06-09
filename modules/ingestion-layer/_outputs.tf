# =============================================================================
# Ingestion Layer — Outputs
# =============================================================================

output "sqs_queue_arn" {
  description = "ARN of the SQS FIFO queue"
  value       = aws_sqs_queue.pipeline_fifo.arn
}

output "sqs_queue_url" {
  description = "URL of the SQS FIFO queue"
  value       = aws_sqs_queue.pipeline_fifo.url
}

output "dlq_arn" {
  description = "ARN of the SQS Dead Letter Queue"
  value       = aws_sqs_queue.pipeline_dlq.arn
}

output "lambda_trigger_arn" {
  description = "ARN of the Lambda Trigger function"
  value       = aws_lambda_function.trigger.arn
}

output "glue_job_arn" {
  description = "ARN of the Glue encryption job"
  value       = aws_glue_job.encryption.arn
}

output "glue_job_name" {
  description = "Name of the Glue encryption job"
  value       = aws_glue_job.encryption.name
}
