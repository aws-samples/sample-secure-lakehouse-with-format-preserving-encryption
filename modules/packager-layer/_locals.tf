# =============================================================================
# Packager Layer — Local Values
# =============================================================================

locals {
  # Fixed destination under the artifacts/ prefix (configured, never hard-coded
  # bucket). The Glue job binds dependency_archive_uri to --extra-py-files.
  dependency_archive_name = "requirements.zip"
  dependency_archive_key  = "${var.artifacts_prefix}/${local.dependency_archive_name}"
  dependency_archive_uri  = "s3://${var.assets_bucket_name}/${local.dependency_archive_key}"

  # Local build location for the fat zip produced by the provisioner.
  build_dir    = "${path.module}/.build"
  archive_path = "${local.build_dir}/${local.dependency_archive_name}"

  # All shared Python modules to bundle: every *.py in shared_modules_dir
  # EXCEPT the main job script (delivered separately as the job script_location).
  # Listing them dynamically means adding/removing a .py file is picked up
  # automatically — no need to edit this module.
  shared_module_paths = sort([
    for f in fileset(var.shared_modules_dir, "*.py") : "${var.shared_modules_dir}/${f}"
    if f != var.main_script_name
  ])

  # Content-hash of every bundled module keyed by filename. Folding this into the
  # terraform_data triggers_replace means ANY edit to ANY bundled .py (or an
  # add/remove) changes the trigger and re-runs packaging.
  shared_module_hashes = {
    for p in local.shared_module_paths : basename(p) => filemd5(p)
  }

  # BIN file destination in the assets bucket under the bin_file/ prefix.
  bin_file_name = basename(var.bin_file_path)
  bin_file_key  = "${var.bin_file_prefix}/${local.bin_file_name}"
  bin_file_uri  = "s3://${var.assets_bucket_name}/${local.bin_file_key}"
}
