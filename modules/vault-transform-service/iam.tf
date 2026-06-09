# =============================================================================
# Vault Transform Service — IAM Roles and Policies
# =============================================================================

# =============================================================================
# 1. encryption_api Lambda Role
# =============================================================================

resource "aws_iam_role" "encryption_api" {
  name               = "${var.project_name}-iam-encryption-api-role"
  assume_role_policy = file("${path.module}/iam-policies/encryption-api/trust-policy.json")
}

resource "aws_iam_role_policy" "encryption_api_secrets" {
  name = "${var.project_name}-iam-encryption-api-secrets-policy"
  role = aws_iam_role.encryption_api.id

  policy = templatefile("${path.module}/iam-policies/encryption-api/resource-policy.json", {
    fpe_secret_arn = aws_secretsmanager_secret.fpe_key.arn
    kms_key_arn    = var.kms_key_arn
  })
}

resource "aws_iam_role_policy_attachment" "encryption_api_vpc" {
  role       = aws_iam_role.encryption_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "encryption_api_cloudwatch" {
  role       = aws_iam_role.encryption_api.name
  policy_arn = var.cloudwatch_write_policy_arn
}

# =============================================================================
# 2. secret_generator Lambda Role
# =============================================================================

resource "aws_iam_role" "secret_generator" {
  name               = "${var.project_name}-iam-secret-generator-role"
  assume_role_policy = file("${path.module}/iam-policies/secret-generator/trust-policy.json")
}

resource "aws_iam_role_policy" "secret_generator_secrets" {
  name = "${var.project_name}-iam-secret-generator-secrets-policy"
  role = aws_iam_role.secret_generator.id

  policy = templatefile("${path.module}/iam-policies/secret-generator/resource-policy.json", {
    fpe_secret_arn = aws_secretsmanager_secret.fpe_key.arn
    kms_key_arn    = var.kms_key_arn
  })
}

resource "aws_iam_role_policy_attachment" "secret_generator_basic" {
  role       = aws_iam_role.secret_generator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# =============================================================================
# 3. Glue Role
# =============================================================================

resource "aws_iam_role" "vault_glue" {
  name               = "${var.project_name}-iam-vault-glue-role"
  assume_role_policy = file("${path.module}/iam-policies/vault-glue/trust-policy.json")
}

resource "aws_iam_role_policy" "vault_glue_inline" {
  name = "${var.project_name}-iam-vault-glue-resource-policy"
  role = aws_iam_role.vault_glue.id

  policy = templatefile("${path.module}/iam-policies/vault-glue/resource-policy.json", {
    assets_bucket_arn = aws_s3_bucket.assets.arn
    api_execution_arn = aws_api_gateway_rest_api.vault.execution_arn
  })
}

resource "aws_iam_role_policy_attachment" "vault_glue_service" {
  role       = aws_iam_role.vault_glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "vault_glue_cloudwatch" {
  role       = aws_iam_role.vault_glue.name
  policy_arn = var.cloudwatch_write_policy_arn
}

# =============================================================================
# 4. API Gateway CloudWatch Role
# =============================================================================

resource "aws_iam_role" "apigw_cloudwatch" {
  name               = "${var.project_name}-iam-apigw-cloudwatch-role"
  assume_role_policy = file("${path.module}/iam-policies/apigw-cloudwatch/trust-policy.json")
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}
