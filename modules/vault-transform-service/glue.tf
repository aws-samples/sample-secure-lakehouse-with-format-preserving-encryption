# =============================================================================
# Vault Transform Service — Glue Connection (NETWORK type)
# =============================================================================

resource "aws_glue_connection" "network" {
  name            = "${var.project_name}-glue-network-connection"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = data.aws_availability_zones.available.names[0]
    security_group_id_list = [var.glue_security_group_id]
    subnet_id              = var.private_subnet_ids[0]
  }
}
