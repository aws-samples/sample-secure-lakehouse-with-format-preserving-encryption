# =============================================================================
# Monitoring Layer — Input Variables
# =============================================================================

variable "project_name" {
  type        = string
  description = "Project name prefix (e.g. enc-blog)"
}

# -----------------------------------------------------------------------------
# Alarm action target
# -----------------------------------------------------------------------------

variable "sns_topic_arn" {
  type        = string
  description = "ARN of the SNS topic alarms publish to (reuses the pipeline notification topic)"
}

# -----------------------------------------------------------------------------
# Resource identifiers (from other layers) used as alarm dimensions
# -----------------------------------------------------------------------------

variable "dlq_name" {
  type        = string
  description = "Name of the SQS FIFO Dead Letter Queue"
}

variable "state_machine_arn" {
  type        = string
  description = "ARN of the Step Functions state machine"
}

variable "glue_job_name" {
  type        = string
  description = "Name of the Glue encryption job"
}

variable "encryption_api_lambda_name" {
  type        = string
  description = "Function name of the encryption API Lambda"
}

variable "copy_lambda_name" {
  type        = string
  description = "Function name of the Copy Lambda"
}

variable "lambda_trigger_name" {
  type        = string
  description = "Function name of the Lambda Trigger"
}

variable "api_gateway_name" {
  type        = string
  description = "Name of the vault REST API (ApiName dimension)"
}

variable "api_gateway_stage_name" {
  type        = string
  description = "Deployed stage name of the vault REST API (Stage dimension)"
}

# -----------------------------------------------------------------------------
# Alarm thresholds / evaluation configuration
# -----------------------------------------------------------------------------

variable "alarm_period_seconds" {
  type        = number
  description = "Evaluation period in seconds for the metric alarms"
}

variable "alarm_evaluation_periods" {
  type        = number
  description = "Number of periods over which data is evaluated before alarming"
}

variable "dlq_depth_threshold" {
  type        = number
  description = "Alarm when the DLQ has at least this many visible messages (poison/failed events)"
}

variable "sfn_failed_threshold" {
  type        = number
  description = "Alarm when the number of failed Step Functions executions reaches this value"
}

variable "glue_failed_threshold" {
  type        = number
  description = "Alarm when the number of failed Glue task runs reaches this value"
}

variable "lambda_error_threshold" {
  type        = number
  description = "Alarm when a Lambda reports at least this many errors in a period"
}

variable "lambda_throttle_threshold" {
  type        = number
  description = "Alarm when a Lambda reports at least this many throttles in a period"
}

variable "encryption_lambda_duration_threshold_ms" {
  type        = number
  description = "Alarm when the encryption API Lambda average duration (ms) exceeds this value. Keep below the API Gateway 29s integration timeout."
}

variable "apigw_5xx_threshold" {
  type        = number
  description = "Alarm when the vault API reports at least this many 5XX responses in a period"
}

variable "apigw_latency_threshold_ms" {
  type        = number
  description = "Alarm when the vault API average latency (ms) exceeds this value"
}
