# =============================================================================
# Ingestion Layer — Data Sources
# =============================================================================

data "archive_file" "lambda_trigger" {
  type        = "zip"
  source_dir  = "${path.module}/assets/handle_event"
  output_path = "${path.module}/assets/handle_event.zip"
}
