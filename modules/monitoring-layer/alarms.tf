# =============================================================================
# Monitoring Layer — CloudWatch Metric Alarms
# =============================================================================
# Addresses observability gaps: without these, failed events silently pile up
# in the DLQ, failed Step Functions / Glue runs go unnoticed, and API/Lambda
# latency or throttling is invisible. Every alarm publishes to the shared SNS
# topic so operators are notified on the same channel as pipeline failures.
#
# All alarms treat missing data as "not breaching" — a quiet pipeline (no
# invocations) must not raise false alarms.
# =============================================================================

# -----------------------------------------------------------------------------
# SQS Dead Letter Queue — depth
# Messages here mean events exhausted their retries and were parked. Any
# sustained depth needs operator attention (lost/blocked file events).
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.project_name}-cw-dlq-depth-alarm"
  alarm_description   = "SQS DLQ has messages: pipeline events exhausted retries and were parked."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.dlq_depth_threshold
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# -----------------------------------------------------------------------------
# Step Functions — failed executions
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "sfn_failed_executions" {
  alarm_name          = "${var.project_name}-cw-sfn-failed-executions-alarm"
  alarm_description   = "Step Functions pipeline workflow reported failed executions."
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.sfn_failed_threshold
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.state_machine_arn
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# -----------------------------------------------------------------------------
# AWS Glue — failed tasks on the encryption job
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "glue_failed_tasks" {
  alarm_name          = "${var.project_name}-cw-glue-failed-tasks-alarm"
  alarm_description   = "Glue encryption job reported failed tasks."
  namespace           = "Glue"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.glue_failed_threshold
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = var.glue_job_name
    Type    = "count"
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# -----------------------------------------------------------------------------
# API Gateway — 5XX errors on the vault encrypt API
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "${var.project_name}-cw-apigw-5xx-alarm"
  alarm_description   = "Vault encrypt API returned server-side (5XX) errors."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.apigw_5xx_threshold
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
    Stage   = var.api_gateway_stage_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# -----------------------------------------------------------------------------
# API Gateway — latency on the vault encrypt API
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "apigw_latency" {
  alarm_name          = "${var.project_name}-cw-apigw-latency-alarm"
  alarm_description   = "Vault encrypt API average latency exceeded threshold."
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.apigw_latency_threshold_ms
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = var.api_gateway_name
    Stage   = var.api_gateway_stage_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# -----------------------------------------------------------------------------
# Lambda — errors, throttles, and (encryption API) duration
# One error + one throttle alarm per function; a duration alarm on the
# encryption API Lambda since it gates the API Gateway integration timeout.
# -----------------------------------------------------------------------------

locals {
  # Functions that get error + throttle alarms.
  monitored_lambdas = {
    encryption_api = var.encryption_api_lambda_name
    copy           = var.copy_lambda_name
    trigger        = var.lambda_trigger_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.monitored_lambdas

  alarm_name          = "${var.project_name}-cw-lambda-${each.key}-errors-alarm"
  alarm_description   = "Lambda ${each.value} reported errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.lambda_error_threshold
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = local.monitored_lambdas

  alarm_name          = "${var.project_name}-cw-lambda-${each.key}-throttles-alarm"
  alarm_description   = "Lambda ${each.value} was throttled."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.lambda_throttle_threshold
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "encryption_lambda_duration" {
  alarm_name          = "${var.project_name}-cw-lambda-encryption-api-duration-alarm"
  alarm_description   = "Encryption API Lambda average duration is approaching the API Gateway integration timeout."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.encryption_lambda_duration_threshold_ms
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.encryption_api_lambda_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}
