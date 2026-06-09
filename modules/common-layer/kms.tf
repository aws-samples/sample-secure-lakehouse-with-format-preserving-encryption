# =============================================================================
# Common Layer — KMS Customer Managed Key
# =============================================================================

resource "aws_kms_key" "shared" {
  description         = "Shared CMK for S3 bucket and SQS queue encryption"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-policy"
    Statement = [
      {
        Sid       = "EnableRootAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowEventBridgeToUseCMK"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = var.kms_key_alias
    Project = var.project_name
  }
}

resource "aws_kms_alias" "shared" {
  name          = "alias/${var.kms_key_alias}"
  target_key_id = aws_kms_key.shared.key_id
}
