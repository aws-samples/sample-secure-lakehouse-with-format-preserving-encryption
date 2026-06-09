# =============================================================================
# Landing Layer — Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

data "archive_file" "copy_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/assets/ingest"
  output_path = "${path.module}/assets/ingest.zip"
}
