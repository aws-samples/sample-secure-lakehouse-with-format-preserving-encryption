# =============================================================================
# Quarantine Layer — Input Variables
# =============================================================================

variable "quarantine_bucket_name" {
  type        = string
  description = "Name of the S3 quarantine bucket where raw files are deposited for processing"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the shared CMK from common layer for S3 SSE-KMS encryption"
}

variable "upload_prefix" {
  type        = string
  description = "S3 key prefix where files should be uploaded (visible as a folder in the console)"
}

variable "expiration_days" {
  type        = number
  description = "Number of days after which objects in the quarantine bucket expire. Bounds the plaintext-persistence window so raw PANs cannot linger indefinitely if processing stalls."
}

variable "noncurrent_expiration_days" {
  type        = number
  description = "Number of days after which noncurrent object versions in the quarantine bucket are permanently deleted."
}
