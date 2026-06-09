# =============================================================================
# Root Module — Module Instantiations
# =============================================================================

# -----------------------------------------------------------------------------
# Common Layer — No upstream dependencies
# -----------------------------------------------------------------------------

module "common_layer" {
  source = "./modules/common-layer"

  project_name          = var.project_name
  vpc_cidr              = var.vpc_cidr
  az_count              = var.az_count
  kms_key_alias         = var.kms_key_alias
  log_group_name        = var.log_group_name
  log_retention_in_days = var.log_retention_in_days
}

# -----------------------------------------------------------------------------
# Quarantine Layer — Depends on Common Layer (KMS key ARN)
# -----------------------------------------------------------------------------

module "quarantine_layer" {
  source = "./modules/quarantine-layer"

  quarantine_bucket_name = var.quarantine_bucket_name
  kms_key_arn            = module.common_layer.kms_key_arn
  upload_prefix          = var.event_object_key_prefix
}

# -----------------------------------------------------------------------------
# Landing Layer — Depends on Common Layer + Quarantine Layer
# -----------------------------------------------------------------------------

module "landing_layer" {
  source = "./modules/landing-layer"

  landing_bucket_name         = var.landing_bucket_name
  kms_key_arn                 = module.common_layer.kms_key_arn
  quarantine_bucket_arn       = module.quarantine_layer.quarantine_bucket_arn
  quarantine_bucket_name      = module.quarantine_layer.quarantine_bucket_name
  vpc_id                      = module.common_layer.vpc_id
  private_subnet_ids          = module.common_layer.private_subnet_ids
  lambda_security_group_id    = module.common_layer.lambda_security_group_id
  log_group_arn               = module.common_layer.log_group_arn
  cloudwatch_write_policy_arn = module.common_layer.cloudwatch_write_policy_arn
  copy_lambda_name            = var.copy_lambda_name
  copy_lambda_runtime         = var.copy_lambda_runtime
  copy_lambda_timeout         = var.copy_lambda_timeout
  copy_lambda_memory_size     = var.copy_lambda_memory_size

  depends_on = [module.common_layer]
}

# -----------------------------------------------------------------------------
# Vault Transform Service — Depends on Common Layer
# -----------------------------------------------------------------------------

module "vault_transform_service" {
  source = "./modules/vault-transform-service"

  vpc_id                      = module.common_layer.vpc_id
  private_subnet_ids          = module.common_layer.private_subnet_ids
  lambda_security_group_id    = module.common_layer.lambda_security_group_id
  glue_security_group_id      = module.common_layer.glue_security_group_id
  endpoints_security_group_id = module.common_layer.endpoints_security_group_id
  execute_api_vpc_endpoint_id = module.common_layer.execute_api_vpc_endpoint_id
  kms_key_arn                 = module.common_layer.kms_key_arn
  log_group_arn               = module.common_layer.log_group_arn
  cloudwatch_write_policy_arn = module.common_layer.cloudwatch_write_policy_arn
  project_name                = var.project_name
  lambda_runtime              = var.lambda_runtime
  lambda_timeout              = var.lambda_timeout
  lambda_memory_size          = var.lambda_memory_size

  depends_on = [module.common_layer]
}

# -----------------------------------------------------------------------------
# Packager Layer — Depends on Vault Transform Service (assets/artifactory bucket)
# -----------------------------------------------------------------------------

module "packager_layer" {
  source = "./modules/packager-layer"

  assets_bucket_name = module.vault_transform_service.assets_bucket_name
  artifacts_prefix   = var.packager_artifacts_prefix
  requirements_path  = "${path.module}/${var.packager_requirements_path}"
  shared_modules_dir = "${path.module}/${var.packager_shared_modules_dir}"
  main_script_name   = var.packager_main_script_name
  bin_file_path      = "${path.module}/${var.packager_bin_file_path}"
  bin_file_prefix    = var.packager_bin_file_prefix

  depends_on = [module.vault_transform_service]
}

# -----------------------------------------------------------------------------
# Ingestion Layer — Depends on Common + Quarantine + Vault Transform + Orchestration
# -----------------------------------------------------------------------------

module "ingestion_layer" {
  source = "./modules/ingestion-layer"

  project_name                = var.project_name
  quarantine_bucket_arn       = module.quarantine_layer.quarantine_bucket_arn
  quarantine_bucket_name      = module.quarantine_layer.quarantine_bucket_name
  metadata_bucket_arn         = module.quarantine_layer.quarantine_bucket_arn
  metadata_bucket_name        = module.quarantine_layer.quarantine_bucket_name
  object_key                  = "cards/cards.csv"
  event_object_key_prefix     = var.event_object_key_prefix
  state_machine_arn           = module.orchestration_layer.state_machine_arn
  kms_key_arn                 = module.common_layer.kms_key_arn
  log_group_arn               = module.common_layer.log_group_arn
  cloudwatch_write_policy_arn = module.common_layer.cloudwatch_write_policy_arn
  vpc_id                      = module.common_layer.vpc_id
  private_subnet_ids          = module.common_layer.private_subnet_ids
  lambda_security_group_id    = module.common_layer.lambda_security_group_id
  glue_connection_name        = module.vault_transform_service.glue_connection_name
  vault_api_invoke_url        = module.vault_transform_service.api_invoke_url
  vault_api_execution_arn     = module.vault_transform_service.api_execution_arn
  assets_bucket_name          = module.vault_transform_service.assets_bucket_name
  dependency_archive_uri      = module.packager_layer.dependency_archive_uri
  bin_file_key                = module.packager_layer.bin_file_key
  sqs_queue_name              = var.sqs_queue_name
  sqs_visibility_timeout      = var.sqs_visibility_timeout
  sqs_message_retention       = var.sqs_message_retention
  sqs_max_receive_count       = var.sqs_max_receive_count
  lambda_trigger_name         = var.lambda_trigger_name
  lambda_trigger_runtime      = var.lambda_trigger_runtime
  lambda_trigger_timeout      = var.lambda_trigger_timeout
  lambda_trigger_memory_size  = var.lambda_trigger_memory_size
  glue_job_name               = var.glue_job_name
  glue_worker_type            = var.glue_worker_type
  glue_number_of_workers      = var.glue_number_of_workers
  glue_timeout                = var.glue_timeout
  glue_max_retries            = var.glue_max_retries

  depends_on = [module.packager_layer]
}

# -----------------------------------------------------------------------------
# Orchestration Layer — Depends on Ingestion Layer + Landing Layer + Common Layer
# -----------------------------------------------------------------------------

module "orchestration_layer" {
  source = "./modules/orchestration-layer"

  glue_job_arn                = module.ingestion_layer.glue_job_arn
  glue_job_name               = module.ingestion_layer.glue_job_name
  copy_lambda_arn             = module.landing_layer.copy_lambda_arn
  copy_lambda_function_name   = module.landing_layer.copy_lambda_function_name
  log_group_arn               = module.common_layer.log_group_arn
  state_machine_name          = var.state_machine_name
  cloudwatch_write_policy_arn = module.common_layer.cloudwatch_write_policy_arn
}
