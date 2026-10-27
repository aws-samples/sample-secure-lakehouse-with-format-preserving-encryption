# =============================================================================
# Ingestion Layer — Local Values
# =============================================================================

locals {
  # IAM naming: enc-blog-iam-<purpose>-role/policy
  lambda_trigger_role_name   = "enc-blog-iam-lambda-trigger-role"
  lambda_trigger_policy_name = "enc-blog-iam-lambda-trigger-policy"
  glue_execution_role_name   = "enc-blog-iam-glue-execution-role"
  glue_execution_policy_name = "enc-blog-iam-glue-execution-policy"
  bin_file_path              = "${var.metadata_bucket_name}/cards/bin-file.csv"

  # Treatment contract: uploaded to the assets bucket under the
  # treatment-contract/ prefix and read back by the Glue job's Contract class
  # at s3://<assets-bucket>/treatment-contract/<dataset>-treatment-contract.yaml.
  treatment_contract_prefix = "treatment-contract"
  treatment_contract_file   = "${var.dataset}-treatment-contract.yaml"

  # Prefix in the assets bucket where the Glue job writes Spark UI event logs.
  # Shared by the job argument (glue.tf) and the job role's write permission
  # (iam.tf) so the two cannot drift apart.
  spark_ui_logs_prefix = "log"
}
