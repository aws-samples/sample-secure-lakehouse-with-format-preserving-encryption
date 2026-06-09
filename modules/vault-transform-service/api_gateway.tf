# =============================================================================
# Vault Transform Service — Private API Gateway
# =============================================================================

# -----------------------------------------------------------------------------
# REST API (Private)
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "vault" {
  name = "${var.project_name}-apigw-vault-encrypt-api"

  endpoint_configuration {
    types = ["PRIVATE"]
  }
}

# -----------------------------------------------------------------------------
# Resource Policy — Restrict access to VPC endpoint only
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api_policy" "vault" {
  rest_api_id = aws_api_gateway_rest_api.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.vault.execution_arn}/*"
        Condition = {
          StringEquals = {
            "aws:sourceVpce" = var.execute_api_vpc_endpoint_id
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# API Resources — /transform/encrypt
# -----------------------------------------------------------------------------

resource "aws_api_gateway_resource" "transform" {
  rest_api_id = aws_api_gateway_rest_api.vault.id
  parent_id   = aws_api_gateway_rest_api.vault.root_resource_id
  path_part   = "transform"
}

resource "aws_api_gateway_resource" "encrypt" {
  rest_api_id = aws_api_gateway_rest_api.vault.id
  parent_id   = aws_api_gateway_resource.transform.id
  path_part   = "encrypt"
}

# -----------------------------------------------------------------------------
# Method — POST /transform/encrypt
# -----------------------------------------------------------------------------

resource "aws_api_gateway_method" "encrypt_post" {
  rest_api_id   = aws_api_gateway_rest_api.vault.id
  resource_id   = aws_api_gateway_resource.encrypt.id
  http_method   = "POST"
  authorization = "NONE"
}

# -----------------------------------------------------------------------------
# Integration — AWS_PROXY to encryption_api Lambda
# -----------------------------------------------------------------------------

resource "aws_api_gateway_integration" "encrypt_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.vault.id
  resource_id             = aws_api_gateway_resource.encrypt.id
  http_method             = aws_api_gateway_method.encrypt_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.encryption_api.invoke_arn
}

# -----------------------------------------------------------------------------
# Deployment and Stage
# -----------------------------------------------------------------------------

resource "aws_api_gateway_deployment" "vault" {
  rest_api_id = aws_api_gateway_rest_api.vault.id

  depends_on = [
    aws_api_gateway_integration.encrypt_lambda
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.transform.id,
      aws_api_gateway_resource.encrypt.id,
      aws_api_gateway_method.encrypt_post.id,
      aws_api_gateway_integration.encrypt_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.vault.id
  deployment_id = aws_api_gateway_deployment.vault.id
  stage_name    = "v1"

  access_log_settings {
    destination_arn = var.log_group_arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  depends_on = [aws_api_gateway_account.this]
}

# -----------------------------------------------------------------------------
# API Gateway Account — enables CloudWatch logging for API Gateway
# -----------------------------------------------------------------------------

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
}
