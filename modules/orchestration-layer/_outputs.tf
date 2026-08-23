# =============================================================================
# Orchestration Layer — Outputs
# =============================================================================

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for pipeline failure notifications"
  value       = aws_sns_topic.pipeline_failure.arn
}
