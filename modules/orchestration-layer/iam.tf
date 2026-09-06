# =============================================================================
# Orchestration Layer — IAM Roles
# =============================================================================

# -----------------------------------------------------------------------------
# Step Functions State Machine Execution Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sfn_execution" {
  name               = "enc-blog-iam-sfn-execution-role"
  assume_role_policy = file("${path.module}/iam-policies/sfn-execution/trust-policy.json")
}

# -----------------------------------------------------------------------------
# Inline Policy: Lambda Invoke (scoped to Copy Lambda ARN)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "sfn_execution" {
  name = "enc-blog-iam-sfn-execution-policy"
  role = aws_iam_role.sfn_execution.id

  policy = templatefile("${path.module}/iam-policies/sfn-execution/resource-policy.json", {
    copy_lambda_arn   = var.copy_lambda_arn
    glue_job_arn      = var.glue_job_arn
    notify_lambda_arn = aws_lambda_function.notify.arn
  })
}

# -----------------------------------------------------------------------------
# Inline Policy: Step Functions Logging
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "sfn_logging" {
  name = "enc-blog-iam-sfn-logging-policy"
  role = aws_iam_role.sfn_execution.id

  policy = templatefile("${path.module}/iam-policies/sfn-execution/logging-policy.json", {
    log_group_arn = var.log_group_arn
  })
}

# -----------------------------------------------------------------------------
# Policy Attachment: Shared CloudWatch Write Policy
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "sfn_cloudwatch" {
  role       = aws_iam_role.sfn_execution.name
  policy_arn = var.cloudwatch_write_policy_arn
}

# -----------------------------------------------------------------------------
# Notification Formatter Lambda Execution Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "notify_lambda" {
  name               = "enc-blog-iam-notification-role"
  assume_role_policy = file("${path.module}/iam-policies/notify-lambda/trust-policy.json")
}

# -----------------------------------------------------------------------------
# Inline Policy: SNS Publish + KMS (for the KMS-encrypted topic)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "notify_lambda" {
  name = "enc-blog-iam-notification-resource-policy"
  role = aws_iam_role.notify_lambda.id

  policy = templatefile("${path.module}/iam-policies/notify-lambda/resource-policy.json", {
    sns_topic_arn = aws_sns_topic.pipeline_failure.arn
    kms_key_arn   = var.kms_key_arn
  })
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: Shared CloudWatch write policy
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "notify_lambda_cloudwatch" {
  role       = aws_iam_role.notify_lambda.name
  policy_arn = var.cloudwatch_write_policy_arn
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: VPC access execution role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "notify_lambda_vpc" {
  role       = aws_iam_role.notify_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
