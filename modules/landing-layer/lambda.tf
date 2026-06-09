# =============================================================================
# Landing Layer — Copy Lambda Function
# =============================================================================

resource "aws_lambda_function" "copy" {
  function_name = var.copy_lambda_name
  role          = aws_iam_role.copy_lambda.arn
  handler       = "main.handler"
  runtime       = var.copy_lambda_runtime
  timeout       = var.copy_lambda_timeout
  memory_size   = var.copy_lambda_memory_size

  filename         = data.archive_file.copy_lambda.output_path
  source_code_hash = data.archive_file.copy_lambda.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      QUARANTINE_BUCKET = var.quarantine_bucket_name
      LANDING_BUCKET    = aws_s3_bucket.landing.id
    }
  }
}
