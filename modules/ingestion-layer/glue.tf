# =============================================================================
# Ingestion Layer — Glue Encryption Job
# =============================================================================

resource "aws_s3_object" "glue_encryption_script" {
  bucket      = var.assets_bucket_name
  key         = "scripts/encryption.py"
  source      = "${path.module}/assets/glue_encryption/encryption.py"
  source_hash = filemd5("${path.module}/assets/glue_encryption/encryption.py")
}

resource "aws_glue_job" "encryption" {
  depends_on   = [aws_s3_object.glue_encryption_script]
  name         = var.glue_job_name
  role_arn     = aws_iam_role.glue_job.arn
  glue_version = "6.0"

  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  timeout           = var.glue_timeout
  max_retries       = var.glue_max_retries

  connections = [var.glue_connection_name]

  command {
    script_location = "s3://${var.assets_bucket_name}/scripts/encryption.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--TempDir"                          = "s3://${var.assets_bucket_name}/temp/"
    "--dataset"                          = var.dataset
    "--domain_id"                        = "pci"
    "--datasource"                       = "oracle"
    "--vault_api_url"                    = var.vault_api_invoke_url
    "--source_bucket"                    = var.quarantine_bucket_name
    "--metadata_bucket"                  = var.assets_bucket_name
    "--transformation"                   = "fpe.card-number"
    "--chunk_size"                       = tostring(var.encryption_chunk_size)
    "--bin_file_path"                    = "s3://${var.assets_bucket_name}/bin_file/bin-file.csv"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--enable-job-insights"              = "true"

    # Automatically scale the number of workers. number_of_workers becomes the
    # maximum; Glue starts smaller and adds or removes workers with demand.
    "--enable-auto-scaling" = "true"

    # Spark UI: write event logs to S3 (Standard format, viewable from the Glue
    # console). The job role is granted write access to this prefix in iam.tf.
    "--enable-spark-ui"       = "true"
    "--spark-event-logs-path" = "s3://${var.assets_bucket_name}/${local.spark_ui_logs_prefix}/"

    "--extra-py-files" = var.dependency_archive_uri
  }

}
