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
    copy_lambda_arn = var.copy_lambda_arn
    glue_job_arn    = var.glue_job_arn
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
