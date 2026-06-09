# =============================================================================
# Landing Layer — Local Values
# =============================================================================

locals {
  # IAM naming: enc-blog-iam-<purpose>-role/policy
  copy_lambda_role_name = "enc-blog-iam-copy-lambda-execution-role"
}
