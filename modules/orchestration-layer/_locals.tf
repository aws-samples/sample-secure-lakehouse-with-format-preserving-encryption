# =============================================================================
# Orchestration Layer — Local Values
# =============================================================================

locals {
  # IAM naming: enc-blog-iam-<purpose>-role/policy
  sfn_role_name   = "enc-blog-iam-sfn-execution-role"
  sfn_policy_name = "enc-blog-iam-sfn-execution-policy"
}
