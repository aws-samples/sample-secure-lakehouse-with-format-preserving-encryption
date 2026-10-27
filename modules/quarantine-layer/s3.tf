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
# Lifecycle: bound the plaintext-persistence window
# Raw files (which may contain PANs) land here in cleartext and remain until the
# pipeline encrypts + moves them. If processing stalls or fails, this rule
# guarantees objects — and their noncurrent versions — do not linger in the CDE
# indefinitely. Expiration is measured from object creation.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  # Versioning is enabled on this bucket, so the config must also handle
  # noncurrent versions and incomplete multipart uploads.
  depends_on = [aws_s3_bucket_versioning.quarantine]

  rule {
    id     = "expire-unprocessed-objects"
    status = "Enabled"

    filter {}

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# -----------------------------------------------------------------------------
# Enable EventBridge notifications on the quarantine bucket
# Without this, S3 does NOT send events to EventBridge.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "quarantine_eventbridge" {
  bucket      = aws_s3_bucket.quarantine.id
  eventbridge = true
}

# No placeholder "folder" object is created under the upload prefix. Terraform
# would have to manage an object in this bucket, but the bucket policy denies
# object access to the roles that run Terraform, and the lifecycle rule above
# expires every object after a day. The prefix appears in the console once the
# first file is uploaded.
