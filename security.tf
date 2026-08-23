# =============================================================================
# Root Module — Quarantine (CDE) Bucket Guardrails
# =============================================================================
# The quarantine bucket is the only place raw, unencrypted PAN data exists
# ("the plaintext window"). PCI DSS treats it as in-scope CDE storage, so it
# gets an explicit deny-by-default resource policy on top of identity-based
# permissions. Only the Glue job, the Copy Lambda, and a break-glass Ops Admin
# role may touch it; everything else is denied.
#
# This lives at the root (not in quarantine-layer) because the allow-list needs
# the Glue and Copy Lambda role ARNs, whose modules already depend on the
# quarantine bucket. Attaching the policy here breaks that dependency cycle.
# =============================================================================

locals {
  quarantine_bucket_arn = module.quarantine_layer.quarantine_bucket_arn

  # Principals permitted to operate inside the CDE bucket.
  quarantine_allowed_role_arns = [
    module.ingestion_layer.glue_role_arn,      # reads source, writes /encrypted
    module.landing_layer.copy_lambda_role_arn, # reads encrypted, deletes source
    aws_iam_role.quarantine_ops_admin.arn,     # break-glass cleanup
  ]
}

# -----------------------------------------------------------------------------
# Ops Admin Cleanup Role — break-glass, time-bound access
# -----------------------------------------------------------------------------
# Elevated role for emergency remediation (e.g. purging orphaned plaintext left
# by a stalled run). It is NOT assumable by default: the trust policy requires
# the caller to present an external ID and the session is capped to
# var.ops_admin_max_session_duration so any granted access is inherently
# time-bound.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ops_admin_trust" {
  statement {
    sid     = "AllowTimeBoundAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    # Require an external ID so the role cannot be assumed casually.
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.ops_admin_external_id]
    }
  }
}

resource "aws_iam_role" "quarantine_ops_admin" {
  name                 = "enc-blog-iam-quarantine-ops-admin-role"
  assume_role_policy   = data.aws_iam_policy_document.ops_admin_trust.json
  max_session_duration = var.ops_admin_max_session_duration
}

data "aws_iam_policy_document" "ops_admin_cleanup" {
  statement {
    sid    = "ListQuarantineBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
    ]
    resources = [local.quarantine_bucket_arn]
  }

  statement {
    sid    = "CleanupQuarantineObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = ["${local.quarantine_bucket_arn}/*"]
  }

  # Needed to read/delete SSE-KMS encrypted objects.
  statement {
    sid    = "KmsForQuarantineCleanup"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [module.common_layer.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "quarantine_ops_admin" {
  name   = "enc-blog-iam-quarantine-ops-admin-policy"
  role   = aws_iam_role.quarantine_ops_admin.id
  policy = data.aws_iam_policy_document.ops_admin_cleanup.json
}

# -----------------------------------------------------------------------------
# Deny-by-default Quarantine Bucket Policy
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "quarantine_bucket" {
  # ---------------------------------------------------------------------------
  # 1. Explicit allow for the pipeline principals (object + bucket operations).
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowPipelineRolesObjectAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = local.quarantine_allowed_role_arns
    }

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]
    resources = ["${local.quarantine_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowPipelineRolesBucketAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = local.quarantine_allowed_role_arns
    }

    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
    ]
    resources = [local.quarantine_bucket_arn]
  }

  # ---------------------------------------------------------------------------
  # 2. Deny every principal that is NOT on the allow-list (deny-by-default).
  #    The Deny is evaluated first and wins over any identity-based Allow, so
  #    only the listed roles can reach the CDE bucket.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyAllExceptPipelineRoles"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      local.quarantine_bucket_arn,
      "${local.quarantine_bucket_arn}/*",
    ]

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = local.quarantine_allowed_role_arns
    }
  }

  # ---------------------------------------------------------------------------
  # 3. Deny any request not using TLS (defense in depth for data in transit).
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      local.quarantine_bucket_arn,
      "${local.quarantine_bucket_arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "quarantine" {
  bucket = module.quarantine_layer.quarantine_bucket_name
  policy = data.aws_iam_policy_document.quarantine_bucket.json

  # Ensure the principal roles exist before we reference them in the policy.
  depends_on = [
    module.ingestion_layer,
    module.landing_layer,
  ]
}
