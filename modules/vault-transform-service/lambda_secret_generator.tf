# =============================================================================
# Vault Transform Service — Secret Generator Lambda Function
# =============================================================================

data "archive_file" "secret_generator" {
  type        = "zip"
  source_dir  = "${path.module}/assets/secret_generator"
  output_path = "${path.module}/assets/secret_generator.zip"
}

resource "aws_lambda_function" "secret_generator" {
  function_name = "${var.project_name}-lambda-secret-generator-function"
  role          = aws_iam_role.secret_generator.arn
  handler       = "main.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.secret_generator.output_path
  source_code_hash = data.archive_file.secret_generator.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.fpe_key.name
    }
  }
}
