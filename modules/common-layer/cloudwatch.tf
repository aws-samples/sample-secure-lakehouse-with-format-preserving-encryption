# =============================================================================
# Common Layer — CloudWatch Log Group
# =============================================================================

resource "aws_cloudwatch_log_group" "pipeline" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_in_days

  tags = {
    Project = var.project_name
  }
}
