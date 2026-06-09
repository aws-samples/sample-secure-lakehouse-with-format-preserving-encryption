# =============================================================================
# Packager Layer — BIN File Upload
# =============================================================================
#
# Uploads the BIN list file to the Glue assets bucket under the bin_file/ prefix.
# The `etag = filemd5(...)` makes Terraform detect content changes: editing the
# local BIN file changes its md5, so the next `terraform apply` re-uploads it to
# the same S3 key (overwrite). The Glue job reads it from local.bin_file_uri.

resource "aws_s3_object" "bin_file" {
  bucket      = var.assets_bucket_name
  key         = local.bin_file_key
  source      = var.bin_file_path
  source_hash = filemd5(var.bin_file_path)
}
