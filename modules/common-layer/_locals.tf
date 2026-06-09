# =============================================================================
# Common Layer — VPC Endpoints
# =============================================================================

locals {
  interface_endpoints = [
    "execute-api",
    "secretsmanager",
    "logs",
    "glue",
    "sts",
    "sqs",
    "states"
  ]
}
