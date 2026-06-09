# =============================================================================
# Ingestion Layer — Lambda Trigger Function
# =============================================================================

resource "aws_lambda_function" "trigger" {
  function_name = var.lambda_trigger_name
  role          = aws_iam_role.lambda_trigger.arn
  handler       = "main.handler"
  runtime       = var.lambda_trigger_runtime
  timeout       = var.lambda_trigger_timeout
  memory_size   = var.lambda_trigger_memory_size

  filename         = data.archive_file.lambda_trigger.output_path
  source_code_hash = data.archive_file.lambda_trigger.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      STATE_MACHINE_ARN = var.state_machine_arn
      QUARANTINE_BUCKET = var.quarantine_bucket_name
      GLUE_JOB_NAME     = var.glue_job_name
    }
  }
}

# =============================================================================
# Event Source Mapping — SQS FIFO → Lambda Trigger
# =============================================================================

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn        = aws_sqs_queue.pipeline_fifo.arn
  function_name           = aws_lambda_function.trigger.arn
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]
}
