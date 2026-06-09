# =============================================================================
# Ingestion Layer — Treatment Contract Upload
# =============================================================================
#
# Uploads the dataset treatment contract (YAML) from the local
# assets/treatment-contract/ folder to the quarantine bucket under the
# treatment-contract/ prefix. The Glue job's Contract class reads it from
# s3://<quarantine-bucket>/treatment-contract/<dataset>-treatment-contract.yaml
# (see contract_utils.py). The `etag = filemd5(...)` re-uploads the object
# whenever the local contract content changes on the next apply.

resource "aws_s3_object" "treatment_contract" {
  bucket      = var.quarantine_bucket_name
  key         = "${local.treatment_contract_prefix}/${local.treatment_contract_file}"
  source      = "${path.module}/assets/treatment-contract/${local.treatment_contract_file}"
  source_hash = filemd5("${path.module}/assets/treatment-contract/${local.treatment_contract_file}")
}
