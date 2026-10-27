# =============================================================================
# Root Module — Quarantine (CDE) Bucket Guardrails
# =============================================================================
# The quarantine bucket is the only place raw, unencrypted PAN data exists
# ("the plaintext window"). PCI DSS treats it as in-scope CDE storage, so it
# gets an explicit deny-by-default resource policy on top of identity-based
# permissions. Only the Glue job, the Copy Lambda, and a break-glass Ops Admin
# role may touch its objects. The roles that deploy this stack may manage the
# bucket's configuration, and uploader roles may write source files, but
# neither can read, list, or delete objects; everything else is denied.
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

  # Roles that run terraform apply. They manage the bucket's configuration but
  # are denied its objects. aws:PrincipalArn resolves an assumed-role session to
  # its role ARN, so these are role ARNs, built from the caller's account so no
  # account ID is committed.
  quarantine_deployer_role_arns = [
    for name in var.quarantine_deployer_role_names :
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"
  ]

  # Roles that drop source files into the bucket. Write-only: they can upload
  # but cannot read back, list, or delete what is there.
  quarantine_uploader_role_arns = [
    for name in var.quarantine_uploader_role_names :
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"
  ]

  # What an upload needs. aws s3 cp switches to multipart above 8 MB;
  # CreateMultipartUpload, UploadPart and CompleteMultipartUpload are all
  # authorised by s3:PutObject, and AbortMultipartUpload lets a failed upload
  # clean up its own parts.
  quarantine_upload_actions = [
    "s3:PutObject",
    "s3:AbortMultipartUpload",
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
  # 2. Deny-by-default, split by resource so deployers can manage the bucket
  #    without being able to read what is in it. A Deny wins over any
  #    identity-based Allow, so both hold even for administrators.
  #
  #    a. Objects (the plaintext PANs): everyone except the pipeline roles is
  #       denied every object action other than upload, deployers and
  #       uploaders included. With force_destroy, emptying a non-empty bucket
  #       on destroy therefore needs the break-glass role.
  #    b. Uploads: uploader roles are exempt for upload only. Writing a source
  #       file is how the pipeline is fed; reading one back is not needed.
  #    c. The bucket itself (policy, encryption, versioning, lifecycle,
  #       notifications, listing): deployers are exempt as well. A single
  #       bucket-and-objects deny once covered them too, so the first apply
  #       denied the deploying role s3:GetBucketPolicy on the policy it had
  #       just written, and every later plan failed to refresh the bucket.
  #       Deployers can list object keys (HeadBucket needs s3:ListBucket) but
  #       cannot read object contents.
  #
  #    No Allow is needed for deployers: their same-account identity policies
  #    already grant bucket management; these statements only lift the Deny.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "DenyObjectAccessExceptPipelineRoles"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    # Every object action except upload; upload is governed by the next
    # statement.
    not_actions = local.quarantine_upload_actions
    resources   = ["${local.quarantine_bucket_arn}/*"]

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = local.quarantine_allowed_role_arns
    }
  }

  statement {
    sid    = "DenyObjectUploadExceptPipelineAndUploaderRoles"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = local.quarantine_upload_actions
    resources = ["${local.quarantine_bucket_arn}/*"]

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values = concat(
        local.quarantine_allowed_role_arns,
        local.quarantine_uploader_role_arns,
      )
    }
  }

  statement {
    sid    = "DenyBucketAccessExceptPipelineAndDeployerRoles"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [local.quarantine_bucket_arn]

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values = concat(
        local.quarantine_allowed_role_arns,
        local.quarantine_deployer_role_arns,
      )
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
