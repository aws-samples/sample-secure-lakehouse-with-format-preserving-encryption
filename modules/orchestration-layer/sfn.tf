# =============================================================================
# Orchestration Layer — Step Functions State Machine
# =============================================================================

resource "aws_sfn_state_machine" "pipeline" {
  name     = var.state_machine_name
  role_arn = aws_iam_role.sfn_execution.arn

  logging_configuration {
    log_destination        = "${var.log_group_arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "Orchestrates Glue encryption job followed by Copy Lambda"
    StartAt = "RunGlueJob"
    States = {
      RunGlueJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          "JobName.$" = "$.glue_job_name"
          Arguments = {
            "--source_bucket.$" = "$.source_bucket"
            "--source_key.$"    = "$.source_key"
          }
        }
        ResultPath = "$.glue_result"
        Retry = [
          {
            # Only retry transient Glue failures. Permanent errors (bad script,
            # missing dependency archive, IAM) fall straight through to Catch.
            ErrorEquals = [
              "Glue.ConcurrentRunsExceededException",
              "Glue.OperationTimeoutException",
              "States.TaskFailed"
            ]
            IntervalSeconds = 10
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error_info"
            Next        = "NotifyFailure"
          }
        ]
        Next = "InvokeCopyLambda"
      }
      InvokeCopyLambda = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.copy_lambda_function_name
          Payload = {
            "source_bucket.$" = "$.source_bucket"
            "source_key.$"    = "$.source_key"
          }
        }
        ResultPath = "$.copy_result"
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 5
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error_info"
            Next        = "NotifyFailure"
          }
        ]
        Next = "NotifySuccess"
      }
      NotifySuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.notify.arn
          Payload = {
            "status"           = "SUCCESS"
            "source_bucket.$"  = "$.source_bucket"
            "source_key.$"     = "$.source_key"
            "execution_name.$" = "$$.Execution.Name"
            "execution_id.$"   = "$$.Execution.Id"
            "start_time.$"     = "$$.Execution.StartTime"
            "state_machine.$"  = "$$.StateMachine.Name"
          }
        }
        ResultPath = "$.notify_result"
        End        = true
      }
      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.notify.arn
          Payload = {
            "status"           = "FAILED"
            "source_bucket.$"  = "$.source_bucket"
            "source_key.$"     = "$.source_key"
            "execution_name.$" = "$$.Execution.Name"
            "execution_id.$"   = "$$.Execution.Id"
            "start_time.$"     = "$$.Execution.StartTime"
            "state_machine.$"  = "$$.StateMachine.Name"
            "error_info.$"     = "$.error_info"
          }
        }
        ResultPath = "$.notify_result"
        Next       = "FailState"
      }
      FailState = {
        Type  = "Fail"
        Error = "PipelineFailed"
        Cause = "The pipeline failed after retries — see SNS notification for details"
      }
    }
  })
}
