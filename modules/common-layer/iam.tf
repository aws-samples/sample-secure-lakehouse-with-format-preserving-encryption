# =============================================================================
# Common Layer — Shared IAM Policies
# =============================================================================

resource "aws_iam_policy" "cloudwatch_write" {
  name        = "${var.project_name}-iam-cloudwatch-write-policy"
  description = "Allows writing logs to the centralized CloudWatch Log Group"

  policy = templatefile("${path.module}/iam-policies/cloudwatch-write/resource-policy.json", {
    log_group_arn = aws_cloudwatch_log_group.pipeline.arn
  })
}
