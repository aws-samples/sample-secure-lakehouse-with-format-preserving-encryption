# =============================================================================
# Packager Layer — Outputs
# =============================================================================

output "dependency_archive_uri" {
  description = "S3 URI of the built dependency archive (requirements.zip) for --extra-py-files"
  value       = local.dependency_archive_uri
}

output "dependency_archive_key" {
  description = "S3 key of the built dependency archive under the artifacts/ prefix"
  value       = local.dependency_archive_key
}

output "bin_file_key" {
  description = "S3 key of the uploaded BIN file under the bin_file/ prefix"
  value       = aws_s3_object.bin_file.key
}

output "bin_file_uri" {
  description = "S3 URI of the uploaded BIN file (s3://<assets-bucket>/bin_file/<name>)"
  value       = local.bin_file_uri
}
