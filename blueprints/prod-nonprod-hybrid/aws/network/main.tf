# -----------------------------------------------------------------------------
# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — AWS Network
# RECOMMENDED pattern for most organizations
#
# Architecture:
#   1 Transit Gateway
#   2 Spoke Gateways: prod VPC + nonprod VPC (each in own VPC)
#   1 DB Spoke Gateway (prod data only)
#   SNAT + DNS configured per spoke
# -----------------------------------------------------------------------------

provider "aviatrix" {
  skip_version_validation = true
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Transit Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_transit_gateway" "main" {
  cloud_type   = 1 # AWS
  account_name = var.aws_account_name
  gw_name      = "${var.environment_prefix}-transit"
  vpc_id       = aviatrix_vpc.transit.vpc_id
  vpc_reg      = var.aws_region
  gw_size      = var.transit_gw_size
  subnet       = aviatrix_vpc.transit.public_subnets[0].cidr

  enable_transit_firenet              = true
  enable_transit_summarize_cidr_to_tgw = false
  connected_transit                   = true
  ha_gw_size                          = var.enable_ha ? var.transit_gw_size : null
  ha_subnet                           = var.enable_ha ? aviatrix_vpc.transit.public_subnets[1].cidr : null

  # CRITICAL: Exclude overlapping pod CIDR so multiple spokes can use 100.64.0.0/16
  excluded_advertised_spoke_routes = var.pod_cidr
}

# ---------------------------------------------------------------------------
# Transit VPC
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "transit" {
  cloud_type           = 1
  account_name         = var.aws_account_name
  name                 = "${var.environment_prefix}-transit"
  region               = var.aws_region
  cidr                 = var.transit_cidr
  aviatrix_transit_vpc = true
}

# ---------------------------------------------------------------------------
# Production VPC + Spoke Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "prod" {
  cloud_type           = 1
  account_name         = var.aws_account_name
  name                 = "${var.environment_prefix}-prod"
  region               = var.aws_region
  cidr                 = var.prod_vpc_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "prod" {
  cloud_type   = 1
  account_name = var.aws_account_name
  gw_name      = "${var.environment_prefix}-prod-spoke"
  vpc_id       = aviatrix_vpc.prod.vpc_id
  vpc_reg      = var.aws_region
  gw_size      = var.spoke_gw_size
  subnet       = aviatrix_vpc.prod.public_subnets[0].cidr


  single_ip_snat                   = true

  ha_gw_size = var.enable_ha ? var.spoke_gw_size : null
  ha_subnet  = var.enable_ha ? aviatrix_vpc.prod.public_subnets[1].cidr : null
}

resource "aviatrix_spoke_transit_attachment" "prod" {
  spoke_gw_name   = aviatrix_spoke_gateway.prod.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# Secondary CIDR for pod networking (VPC CNI custom networking)
resource "aws_vpc_ipv4_cidr_block_association" "prod_pods" {
  vpc_id     = aviatrix_vpc.prod.vpc_id
  cidr_block = var.pod_cidr
}

# ---------------------------------------------------------------------------
# Non-Production VPC + Spoke Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "nonprod" {
  cloud_type           = 1
  account_name         = var.aws_account_name
  name                 = "${var.environment_prefix}-nonprod"
  region               = var.aws_region
  cidr                 = var.nonprod_vpc_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "nonprod" {
  cloud_type   = 1
  account_name = var.aws_account_name
  gw_name      = "${var.environment_prefix}-nonprod-spoke"
  vpc_id       = aviatrix_vpc.nonprod.vpc_id
  vpc_reg      = var.aws_region
  gw_size      = var.spoke_gw_size
  subnet       = aviatrix_vpc.nonprod.public_subnets[0].cidr


  single_ip_snat                   = true

  ha_gw_size = var.enable_ha ? var.spoke_gw_size : null
  ha_subnet  = var.enable_ha ? aviatrix_vpc.nonprod.public_subnets[1].cidr : null
}

resource "aviatrix_spoke_transit_attachment" "nonprod" {
  spoke_gw_name   = aviatrix_spoke_gateway.nonprod.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# Secondary CIDR for pod networking (VPC CNI custom networking)
resource "aws_vpc_ipv4_cidr_block_association" "nonprod_pods" {
  vpc_id     = aviatrix_vpc.nonprod.vpc_id
  cidr_block = var.pod_cidr
}

# ---------------------------------------------------------------------------
# Database Spoke (prod data only)
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "db" {
  cloud_type           = 1
  account_name         = var.aws_account_name
  name                 = "${var.environment_prefix}-prod-db"
  region               = var.aws_region
  cidr                 = var.db_spoke_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "db" {
  cloud_type   = 1
  account_name = var.aws_account_name
  gw_name      = "${var.environment_prefix}-db-spoke"
  vpc_id       = aviatrix_vpc.db.vpc_id
  vpc_reg      = var.aws_region
  gw_size      = var.db_spoke_gw_size
  subnet       = aviatrix_vpc.db.public_subnets[0].cidr



  ha_gw_size = var.enable_ha ? var.db_spoke_gw_size : null
  ha_subnet  = var.enable_ha ? aviatrix_vpc.db.public_subnets[1].cidr : null
}

resource "aviatrix_spoke_transit_attachment" "db" {
  spoke_gw_name   = aviatrix_spoke_gateway.db.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# ---------------------------------------------------------------------------
# DNS — Private Hosted Zone for service discovery
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "private" {
  count = var.route53_zone_id == "" ? 1 : 0

  name = var.dns_domain

  vpc {
    vpc_id = aviatrix_vpc.prod.vpc_id
  }

  vpc {
    vpc_id = aviatrix_vpc.nonprod.vpc_id
  }

  lifecycle {
    ignore_changes = [vpc]
  }
}

locals {
  dns_zone_id = var.route53_zone_id != "" ? var.route53_zone_id : aws_route53_zone.private[0].zone_id
}
