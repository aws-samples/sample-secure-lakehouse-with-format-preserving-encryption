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
        Retry      = []
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "FailState"
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
        End = true
      }
      FailState = {
        Type  = "Fail"
        Error = "GlueJobFailed"
        Cause = "The Glue encryption job failed after retries"
      }
    }
  })
}
