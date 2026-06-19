locals {
  vpc_name = "lmx-vpc"
  vpc_cidr = "10.16.0.0/16"

  # Spread subnets across as many Availability Zones as the region offers, up to 6.
  # The VPC module assigns subnets to AZs round-robin by list position, so each
  # environment below is sized to 6 subnets: in a 6-AZ region (e.g. us-east-1) an
  # environment spans a–f one-per-AZ; in a 3-AZ region (e.g. eu-central-1) the list
  # wraps to 2 subnets per AZ. Either way every environment gets full AZ coverage,
  # which minimizes Databricks "InsufficientInstanceCapacity" placement failures.
  # (The per-subnet AZ labels below show the assignment in a 6-AZ region.)
  azs = slice(
    data.aws_availability_zones.available.names,
    0,
    min(6, length(data.aws_availability_zones.available.names)),
  )

  public_subnets = [
    "10.16.0.0/24", # AZ a
    "10.16.1.0/24", # AZ b
    "10.16.2.0/24", # AZ c
  ]

  databricks_private_subnets_development = [
    "10.16.16.0/24", # AZ a
    "10.16.17.0/24", # AZ b
    "10.16.18.0/24", # AZ c
    "10.16.19.0/24", # AZ d
    "10.16.20.0/24", # AZ e
    "10.16.21.0/24", # AZ f
  ]

  databricks_private_subnets_production = [
    "10.16.32.0/24", # AZ a
    "10.16.33.0/24", # AZ b
    "10.16.34.0/24", # AZ c
    "10.16.35.0/24", # AZ d
    "10.16.36.0/24", # AZ e
    "10.16.37.0/24", # AZ f
  ]

  databricks_private_subnets_staging = [
    "10.16.48.0/24", # AZ a
    "10.16.49.0/24", # AZ b
    "10.16.50.0/24", # AZ c
    "10.16.51.0/24", # AZ d
    "10.16.52.0/24", # AZ e
    "10.16.53.0/24", # AZ f
  ]

  databricks_private_subnets_sandbox = [
    "10.16.64.0/24", # AZ a
    "10.16.65.0/24", # AZ b
    "10.16.66.0/24", # AZ c
    "10.16.67.0/24", # AZ d
    "10.16.68.0/24", # AZ e
    "10.16.69.0/24", # AZ f
  ]

  glue_private_subnets = [
    "10.16.80.0/24", # AZ a
    "10.16.81.0/24", # AZ b
    "10.16.82.0/24", # AZ c
  ]

  ec2_subnets = ["10.16.96.0/24"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = local.vpc_name
  cidr = local.vpc_cidr
  azs  = local.azs

  public_subnets = local.public_subnets
  # Order matters: each 6-subnet environment block starts on a multiple-of-6
  # index so it aligns to AZ a→f cleanly under the module's round-robin mapping.
  private_subnets = concat(
    local.databricks_private_subnets_development, # indices 0–5
    local.databricks_private_subnets_production,  # indices 6–11
    local.databricks_private_subnets_staging,     # indices 12–17
    local.databricks_private_subnets_sandbox,     # indices 18–23
    local.glue_private_subnets,                   # indices 24–26
    local.ec2_subnets,                            # index 27
  )

  enable_dns_hostnames = true
  enable_nat_gateway   = true
  # single NAT keeps cost down for dev/staging; set to false (one NAT per AZ)
  # for full production HA — no other change required.
  single_nat_gateway = true
  create_igw         = true

  tags = {
    Name = "lmx-vpc"
  }
}

# S3 VPC Gateway Endpoint
resource "aws_vpc_endpoint" "s3_gateway_shared" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway" # Gateway endpoint for S3

  # Associate the endpoint with the route table of the private subnets
  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name = "lmx-s3-shared-gateway-endpoint"
  }
}

# --- Security Group for Glue ---
resource "aws_security_group" "glue_sg" {
  name        = "lmx-glue-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for AWS Glue job - controls network access"

  # Egress Rules
  # Allow outbound HTTPS traffic to the internet (routed via NAT Gateway from private subnet)
  egress {
    description = "Allow outbound HTTPS traffic to the internet"
    from_port   = 443 # HTTPS
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTPS traffic specifically to the S3 VPC endpoint
  egress {
    description = "Allow outbound HTTPS to S3 via VPC Endpoint"
    from_port   = 443 # HTTPS
    to_port     = 443
    protocol    = "tcp"
    # Reference the prefix list ID of the S3 Gateway Endpoint
    prefix_list_ids = [aws_vpc_endpoint.s3_gateway_shared.prefix_list_id]
  }

  tags = {
    Name = "lmx-glue-sg"
  }
}