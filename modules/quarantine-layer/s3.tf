# =============================================================================
# Quarantine Layer — S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "quarantine" {
  bucket        = "${var.quarantine_bucket_name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Enable EventBridge notifications on the quarantine bucket
# Without this, S3 does NOT send events to EventBridge.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "quarantine_eventbridge" {
  bucket      = aws_s3_bucket.quarantine.id
  eventbridge = true
}

# -----------------------------------------------------------------------------
# Create the upload prefix as a visible "folder" in S3 console
# This ensures console users can navigate to the correct path for uploads.
# -----------------------------------------------------------------------------

resource "aws_s3_object" "upload_prefix" {
  bucket  = aws_s3_bucket.quarantine.id
  key     = var.upload_prefix
  content = ""
}
