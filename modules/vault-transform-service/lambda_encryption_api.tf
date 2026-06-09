# =============================================================================
# Vault Transform Service — Encryption API Lambda Function
# =============================================================================

data "archive_file" "encryption_api" {
  type        = "zip"
  source_dir  = "${path.module}/assets/encryption_api"
  output_path = "${path.module}/assets/encryption_api.zip"
}

resource "aws_lambda_function" "encryption_api" {
  function_name = "${var.project_name}-lambda-encryption-api-function"
  role          = aws_iam_role.encryption_api.arn
  handler       = "main.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.encryption_api.output_path
  source_code_hash = data.archive_file.encryption_api.output_base64sha256

  layers = [aws_lambda_layer_version.fpe_dependencies.arn]

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

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.encryption_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.vault.execution_arn}/*/*"
}
