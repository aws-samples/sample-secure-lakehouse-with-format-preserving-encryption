# =============================================================================
# Vault Transform Service — FPE Dependencies Lambda Layer
# =============================================================================

# -----------------------------------------------------------------------------
# Automatically build the layer by installing ff3 + passlib via pip.
# Uses a null_resource with an always-run trigger that checks if the layer
# directory has content. If empty/missing, it rebuilds.
# -----------------------------------------------------------------------------

resource "terraform_data" "build_fpe_layer" {
  triggers_replace = timestamp()

  provisioner "local-exec" {
    command = "bash ${abspath(path.module)}/scripts/build_layer.sh"
  }
}

data "archive_file" "fpe_layer" {
  type        = "zip"
  source_dir  = "${path.module}/assets/fpe_layer"
  output_path = "${path.module}/assets/fpe_layer.zip"

  depends_on = [terraform_data.build_fpe_layer]
}

resource "aws_lambda_layer_version" "fpe_dependencies" {
  layer_name          = "${var.project_name}-lambda-fpe-dependencies-layer"
  description         = "FPE dependencies: ff3 and passlib"
  compatible_runtimes = [var.lambda_runtime]
  filename            = data.archive_file.fpe_layer.output_path
  source_code_hash    = data.archive_file.fpe_layer.output_base64sha256
}
