# =============================================================================
# Orchestration Layer — SNS Topic for Pipeline Notifications
# =============================================================================
# Notifications are published by the notification formatter Lambda
# (see lambda_notify.tf). The Lambda is invoked by the state machine on both
# success and failure, so exactly one email is sent per execution outcome.
# =============================================================================

# -----------------------------------------------------------------------------
# SNS Topic: Pipeline success/failure notifications
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "pipeline_failure" {
  name              = var.sns_topic_name
  kms_master_key_id = var.kms_key_arn
}

# -----------------------------------------------------------------------------
# SNS Subscription: Email notification endpoint
# -----------------------------------------------------------------------------

# One subscription per address. Each recipient receives an SNS confirmation
# email and gets no notifications until they confirm it.
resource "aws_sns_topic_subscription" "email_notification" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.pipeline_failure.arn
  protocol  = "email"
  endpoint  = each.value
}
