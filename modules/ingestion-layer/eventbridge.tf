# =============================================================================
# Ingestion Layer — EventBridge Rule and Target
# =============================================================================

resource "aws_cloudwatch_event_rule" "s3_put_object" {
  name        = "enc-blog-eb-s3-put-object-rule"
  description = "Captures PutObject events from the quarantine S3 bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.quarantine_bucket_name]
      }
      object = {
        key = [{ prefix = var.event_object_key_prefix }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "sqs_fifo" {
  rule      = aws_cloudwatch_event_rule.s3_put_object.name
  target_id = "sqs-fifo-target"
  arn       = aws_sqs_queue.pipeline_fifo.arn

  sqs_target {
    message_group_id = "enc-blog-pipeline"
  }
}
