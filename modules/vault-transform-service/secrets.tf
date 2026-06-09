# =============================================================================
# Vault Transform Service — Secrets Manager
# =============================================================================

resource "aws_secretsmanager_secret" "fpe_key" {
  name                    = "${var.project_name}-sm-fpe-key-material-secret"
  description             = "FPE key material for Format-Preserving Encryption"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0
}
