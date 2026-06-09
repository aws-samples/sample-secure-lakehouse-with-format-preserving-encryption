# =============================================================================
# Ingestion Layer — SQS FIFO Queue and Dead Letter Queue
# =============================================================================

resource "aws_sqs_queue" "pipeline_fifo" {
  name                        = "${var.sqs_queue_name}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = var.sqs_visibility_timeout
  message_retention_seconds   = var.sqs_message_retention
  kms_master_key_id           = var.kms_key_arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pipeline_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
}

resource "aws_sqs_queue" "pipeline_dlq" {
  name                      = "${var.sqs_queue_name}-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = var.kms_key_arn
}

resource "aws_sqs_queue_policy" "pipeline_fifo" {
  queue_url = aws_sqs_queue.pipeline_fifo.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.pipeline_fifo.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_put_object.arn
          }
        }
      }
    ]
  })
}
