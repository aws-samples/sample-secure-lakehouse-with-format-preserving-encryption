# =============================================================================
# Ingestion Layer — Treatment Contract Upload
# =============================================================================
#
# Uploads the dataset treatment contract (YAML) from the local
# assets/treatment-contract/ folder to the assets bucket under the
# treatment-contract/ prefix. The Glue job's Contract class reads it from
# s3://<--metadata_bucket>/treatment-contract/<dataset>-treatment-contract.yaml
# (see contract_utils.py), and glue.tf points --metadata_bucket at the assets
# bucket. The `source_hash = filemd5(...)` re-uploads the object whenever the
# local contract content changes on the next apply.
#
# It is not stored in the quarantine bucket: that bucket expires every object
# after a day, which would delete the contract, and its policy denies object
# access to the roles that run Terraform, which could then not refresh it.

resource "aws_s3_object" "treatment_contract" {
  bucket      = var.assets_bucket_name
  key         = "${local.treatment_contract_prefix}/${local.treatment_contract_file}"
  source      = "${path.module}/assets/treatment-contract/${local.treatment_contract_file}"
  source_hash = filemd5("${path.module}/assets/treatment-contract/${local.treatment_contract_file}")
}
