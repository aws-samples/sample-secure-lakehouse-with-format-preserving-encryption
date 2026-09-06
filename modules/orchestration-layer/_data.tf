# =============================================================================
# Orchestration Layer — Data Sources
# =============================================================================

# Package the notification formatter Lambda source into a deployment zip.
data "archive_file" "notify_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/assets/notify"
  output_path = "${path.module}/assets/notify.zip"
}
