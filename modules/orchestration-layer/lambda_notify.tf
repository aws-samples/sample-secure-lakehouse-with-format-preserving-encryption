# =============================================================================
# Orchestration Layer — Notification Formatter Lambda
# Formats detailed success/failure emails and publishes them to the SNS topic.
# =============================================================================

resource "aws_lambda_function" "notify" {
  function_name = var.notify_lambda_name
  role          = aws_iam_role.notify_lambda.arn
  handler       = "main.handler"
  runtime       = var.notify_lambda_runtime
  timeout       = var.notify_lambda_timeout
  memory_size   = var.notify_lambda_memory_size

  filename         = data.archive_file.notify_lambda.output_path
  source_code_hash = data.archive_file.notify_lambda.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.pipeline_failure.arn
    }
  }
}
