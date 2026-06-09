# =============================================================================
# Ingestion Layer — IAM Roles and Policies
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Trigger Execution Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_trigger" {
  name               = local.lambda_trigger_role_name
  assume_role_policy = file("${path.module}/iam-policies/lambda-trigger/trust-policy.json")
}

# -----------------------------------------------------------------------------
# Inline Policy: Lambda Trigger — SQS + Step Functions
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_trigger" {
  name = local.lambda_trigger_policy_name
  role = aws_iam_role.lambda_trigger.id

  policy = templatefile("${path.module}/iam-policies/lambda-trigger/resource-policy.json", {
    sqs_queue_arn     = aws_sqs_queue.pipeline_fifo.arn
    kms_key_arn       = var.kms_key_arn
    state_machine_arn = var.state_machine_arn
  })
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: Lambda Trigger — VPC Access
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "lambda_trigger_vpc" {
  role       = aws_iam_role.lambda_trigger.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: Lambda Trigger — CloudWatch Write
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "lambda_trigger_cloudwatch" {
  role       = aws_iam_role.lambda_trigger.name
  policy_arn = var.cloudwatch_write_policy_arn
}

# -----------------------------------------------------------------------------
# Glue Job Execution Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "glue_job" {
  name               = local.glue_execution_role_name
  assume_role_policy = file("${path.module}/iam-policies/glue-job/trust-policy.json")
}

# -----------------------------------------------------------------------------
# Inline Policy: Glue Job — S3 + KMS + API Gateway
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "glue_job" {
  name = local.glue_execution_policy_name
  role = aws_iam_role.glue_job.id

  policy = templatefile("${path.module}/iam-policies/glue-job/resource-policy.json", {
    quarantine_bucket_arn   = var.quarantine_bucket_arn
    assets_bucket_arn       = "arn:aws:s3:::${var.assets_bucket_name}"
    kms_key_arn             = var.kms_key_arn
    vault_api_execution_arn = var.vault_api_execution_arn
  })
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: Glue Job — AWS Glue Service Role
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "glue_job_service" {
  role       = aws_iam_role.glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# -----------------------------------------------------------------------------
# Managed Policy Attachment: Glue Job — CloudWatch Write
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "glue_job_cloudwatch" {
  role       = aws_iam_role.glue_job.name
  policy_arn = var.cloudwatch_write_policy_arn
}
