# =============================================================================
# Monitoring Layer — Outputs
# =============================================================================

output "alarm_names" {
  description = "Names of all CloudWatch metric alarms created by this layer"
  value = concat(
    [
      aws_cloudwatch_metric_alarm.dlq_depth.alarm_name,
      aws_cloudwatch_metric_alarm.sfn_failed_executions.alarm_name,
      aws_cloudwatch_metric_alarm.glue_failed_tasks.alarm_name,
      aws_cloudwatch_metric_alarm.apigw_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.apigw_latency.alarm_name,
      aws_cloudwatch_metric_alarm.encryption_lambda_duration.alarm_name,
    ],
    [for a in aws_cloudwatch_metric_alarm.lambda_errors : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.lambda_throttles : a.alarm_name],
  )
}
