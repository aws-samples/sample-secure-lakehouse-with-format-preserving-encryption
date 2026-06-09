# =============================================================================
# Landing Layer — IAM Roles and Policies (Copy Lambda)
# =============================================================================

# -----------------------------------------------------------------------------
# Copy Lambda Execution Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "copy_lambda" {
  name               = local.copy_lambda_role_name
  assume_role_policy = file("${path.module}/iam-policies/copy-lambda/trust-policy.json")
}

# -----------------------------------------------------------------------------
# Inline Policy: S3 + KMS permissions
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "copy_lambda" {
  name = "enc-blog-iam-copy-lambda-resource-policy"
  role = aws_iam_role.copy_lambda.id

  policy = templatefile("${path.module}/iam-policies/copy-lambda/resource-policy.json", {
    quarantine_bucket_arn = var.quarantine_bucket_arn
    landing_bucket_arn    = aws_s3_bucket.landing.arn
    kms_key_arn           = var.kms_key_arn
  })
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: Shared CloudWatch write policy
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "copy_lambda_cloudwatch" {
  role       = aws_iam_role.copy_lambda.name
  policy_arn = var.cloudwatch_write_policy_arn
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: VPC access execution role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "copy_lambda_vpc" {
  role       = aws_iam_role.copy_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
