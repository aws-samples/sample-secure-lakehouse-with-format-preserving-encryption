# =============================================================================
# Packager Layer — Input Variables
# =============================================================================

variable "assets_bucket_name" {
  type        = string
  description = "S3 assets bucket name where the dependency archive is uploaded (from vault-transform-service)"
}

variable "requirements_path" {
  type        = string
  description = "Absolute/relative path to the requirements.txt listing the third-party libraries to bundle"
}

variable "shared_modules_dir" {
  type        = string
  description = "Directory containing the shared Python modules (.py) bundled into the dependency archive. All *.py files here (except the main job script) are bundled, and any change re-triggers packaging."
}

variable "main_script_name" {
  type        = string
  description = "Name of the main Glue job script in shared_modules_dir to EXCLUDE from the bundled archive (it is delivered separately as the job script_location)."
  default     = "encryption.py"
}

variable "artifacts_prefix" {
  type        = string
  description = "S3 key prefix under which the dependency archive is uploaded"
  default     = "artifacts"
}

variable "bin_file_path" {
  type        = string
  description = "Path to the local BIN list file uploaded to the assets bucket for the Glue job."
}

variable "bin_file_prefix" {
  type        = string
  description = "S3 key prefix under which the BIN file is uploaded in the assets bucket."
  default     = "bin_file"
}

variable "glue_platform" {
  type        = string
  description = "Target wheel platform for the Glue 5.0 runtime"
  default     = "manylinux2014_x86_64"
}

variable "glue_python_version" {
  type        = string
  description = "Target CPython version for the Glue 5.0 runtime"
  default     = "3.11"
}
