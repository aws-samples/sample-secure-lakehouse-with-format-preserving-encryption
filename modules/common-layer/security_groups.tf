# =============================================================================
# Common Layer — Security Groups (Lambda, Glue, VPC Endpoints)
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Security Group
# Egress: TCP 443 to VPC CIDR only (HTTPS to VPC endpoints)
# No ingress rules — Lambda initiates connections only
# -----------------------------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-sg-lambda-security-group"
  description = "Security group for Lambda functions - egress HTTPS to VPC endpoints only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg-lambda-security-group"
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_https_to_vpc" {
  security_group_id = aws_security_group.lambda.id
  description       = "Allow HTTPS egress to VPC CIDR for VPC endpoint access"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "lambda_https_to_s3" {
  security_group_id = aws_security_group.lambda.id
  description       = "Allow HTTPS egress to S3 via gateway endpoint prefix list"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# -----------------------------------------------------------------------------
# Glue Security Group
# Ingress: All traffic from self (required by Glue for inter-node communication)
# Egress: All traffic to self (required by Glue for inter-node communication)
# Egress: TCP 443 to VPC CIDR (HTTPS to VPC endpoints)
# -----------------------------------------------------------------------------
resource "aws_security_group" "glue" {
  name        = "${var.project_name}-sg-glue-security-group"
  description = "Security group for Glue jobs - self-referencing + egress HTTPS to VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg-glue-security-group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "glue_self_ingress" {
  security_group_id            = aws_security_group.glue.id
  description                  = "Allow all inbound traffic from self (Glue inter-node communication)"
  referenced_security_group_id = aws_security_group.glue.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "glue_self_egress" {
  security_group_id            = aws_security_group.glue.id
  description                  = "Allow all outbound traffic to self (Glue inter-node communication)"
  referenced_security_group_id = aws_security_group.glue.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "glue_https_to_vpc" {
  security_group_id = aws_security_group.glue.id
  description       = "Allow HTTPS egress to VPC CIDR for VPC endpoint access"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "glue_https_to_s3" {
  security_group_id = aws_security_group.glue.id
  description       = "Allow HTTPS egress to S3 via gateway endpoint prefix list"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# -----------------------------------------------------------------------------
# Endpoints Security Group
# Ingress: TCP 443 from Lambda SG (Lambda accessing VPC endpoints)
# Ingress: TCP 443 from Glue SG (Glue accessing VPC endpoints)
# No egress rules needed — endpoints only receive connections
# -----------------------------------------------------------------------------
resource "aws_security_group" "endpoints" {
  name        = "${var.project_name}-sg-endpoints-security-group"
  description = "Security group for VPC endpoints - ingress HTTPS from Lambda and Glue SGs"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg-endpoints-security-group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_lambda" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "Allow HTTPS from Lambda security group"
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_glue" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "Allow HTTPS from Glue security group"
  referenced_security_group_id = aws_security_group.glue.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
