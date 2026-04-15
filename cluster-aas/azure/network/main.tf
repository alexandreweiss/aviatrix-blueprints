#####################
# Pattern A: Cluster-as-a-Service - Azure Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in Azure
#   - 3x team VNets (team-a, team-b, team-c) via aks-vnet module
#   - 3x Aviatrix Spoke Gateways (active/active) with custom SNAT for pod traffic
#   - Database spoke VNet
#   - Azure Private DNS Zone for internal service discovery
#
# Architecture:
#   Transit GW (10.28.0.0/20)
#     ├── Team-A Spoke (10.30.0.0/20) - AKS cluster for team-a
#     ├── Team-B Spoke (10.31.0.0/20) - AKS cluster for team-b
#     ├── Team-C Spoke (10.32.0.0/20) - AKS cluster for team-c
#     └── Database Spoke (10.35.0.0/22) - Shared database
#
# Pod Networking:
#   Azure CNI Overlay with pod CIDR 100.64.0.0/16 (overlapping across VNets).
#   Pods use non-routable overlay addresses. Aviatrix SNAT translates pod traffic
#   to spoke gateway IPs for east-west and egress flows.
#
# CRITICAL LESSONS LEARNED:
#   - excluded_advertised_spoke_routes goes on the TRANSIT module, NOT on spokes
#   - This is software-defined routing via Aviatrix, not BGP from spokes
#   - Gateways are Active/Active, not standby
#   - DCF sees POST-SNAT traffic -- use VPC SmartGroups for source, hostname for dest
#   - Extract ARM VNet ID from Aviatrix format: element(split(":", vpc_id), 2)
#   - VNet names use suffix "-vnet" -- SmartGroups must match e.g. "team-a-vnet"
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "aviatrix" {
  skip_version_validation = true
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

locals {
  name_prefix = var.name_suffix != "" ? "${var.name_prefix}-${var.name_suffix}" : var.name_prefix
  pod_cidr    = var.pod_cidr

  teams = {
    team-a = {
      name      = "team-a"
      vnet_cidr = var.team_a_vnet_cidr
    }
    team-b = {
      name      = "team-b"
      vnet_cidr = var.team_b_vnet_cidr
    }
    team-c = {
      name      = "team-c"
      vnet_cidr = var.team_c_vnet_cidr
    }
  }
}

#####################
# Aviatrix Transit Gateway
#####################

module "azure_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.2.0"

  name    = "${local.name_prefix}-transit"
  cloud   = "Azure"
  account = var.aviatrix_azure_account_name
  region  = var.azure_region
  cidr    = var.transit_cidr
  ha_gw   = false

  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  # Pattern A uses larger transit instance for 3 team spokes
  instance_size     = "Standard_D8s_v3"
  connected_transit = true

  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This goes on the TRANSIT module, NOT on spokes.
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Team-A VNet and Spoke
#####################

# Module source: ../../azure-aks-multicluster/network/modules/aks-vnet
module "team_a_vnet" {
  source = "../../../azure-aks-multicluster/network/modules/aks-vnet"

  name      = "team-a"
  location  = var.azure_region
  vnet_cidr = local.teams["team-a"].vnet_cidr
  pod_cidr  = local.pod_cidr

  tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

module "team_a_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "Azure"
  name       = "${local.name_prefix}-team-a-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  # Active/Active gateways - NOT standby
  instance_size = "Standard_B2ms"
  ha_gw         = false

  enable_vpc_dns_server = true

  # Use existing VNet created by aks-vnet module
  # Format: "vnet_name:resource_group_name:arm_vnet_id"
  use_existing_vpc = true
  vpc_id           = "${module.team_a_vnet.vnet_name}:${module.team_a_vnet.resource_group_name}:${module.team_a_vnet.vnet_guid}"
  gw_subnet        = module.team_a_vnet.avx_gateway_subnet_cidr
  hagw_subnet      = module.team_a_vnet.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
resource "aviatrix_gateway_snat" "team_a_spoke_snat" {
  gw_name   = module.team_a_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = module.team_a_vnet.aks_system_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_a_spoke]
}

#####################
# Team-B VNet and Spoke
#####################

module "team_b_vnet" {
  source = "../../../azure-aks-multicluster/network/modules/aks-vnet"

  name      = "team-b"
  location  = var.azure_region
  vnet_cidr = local.teams["team-b"].vnet_cidr
  pod_cidr  = local.pod_cidr

  tags = {
    Environment = "demo"
    Team        = "team-b"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

module "team_b_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "Azure"
  name       = "${local.name_prefix}-team-b-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  instance_size = "Standard_B2ms"
  ha_gw         = false

  enable_vpc_dns_server = true

  use_existing_vpc = true
  vpc_id           = "${module.team_b_vnet.vnet_name}:${module.team_b_vnet.resource_group_name}:${module.team_b_vnet.vnet_guid}"
  gw_subnet        = module.team_b_vnet.avx_gateway_subnet_cidr
  hagw_subnet      = module.team_b_vnet.avx_gateway_subnet_cidr
}

resource "aviatrix_gateway_snat" "team_b_spoke_snat" {
  gw_name   = module.team_b_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = module.team_b_vnet.aks_system_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_b_spoke]
}

#####################
# Team-C VNet and Spoke
#####################

module "team_c_vnet" {
  source = "../../../azure-aks-multicluster/network/modules/aks-vnet"

  name      = "team-c"
  location  = var.azure_region
  vnet_cidr = local.teams["team-c"].vnet_cidr
  pod_cidr  = local.pod_cidr

  tags = {
    Environment = "demo"
    Team        = "team-c"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

module "team_c_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "Azure"
  name       = "${local.name_prefix}-team-c-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  instance_size = "Standard_B2ms"
  ha_gw         = false

  enable_vpc_dns_server = true

  use_existing_vpc = true
  vpc_id           = "${module.team_c_vnet.vnet_name}:${module.team_c_vnet.resource_group_name}:${module.team_c_vnet.vnet_guid}"
  gw_subnet        = module.team_c_vnet.avx_gateway_subnet_cidr
  hagw_subnet      = module.team_c_vnet.avx_gateway_subnet_cidr
}

resource "aviatrix_gateway_snat" "team_c_spoke_snat" {
  gw_name   = module.team_c_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = module.team_c_vnet.aks_system_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_c_spoke]
}

#####################
# Database Spoke
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud          = "Azure"
  name           = "${local.name_prefix}-db-spoke"
  cidr           = var.db_vnet_cidr
  account        = var.aviatrix_azure_account_name
  region         = var.azure_region
  transit_gw     = module.azure_transit.transit_gateway.gw_name
  instance_size  = "Standard_B2ms"
  ha_gw          = false
  single_ip_snat = true

  enable_vpc_dns_server = true
}

#####################
# Azure Private DNS Zone
#####################

resource "azurerm_private_dns_zone" "this" {
  name                = var.private_dns_zone_name
  resource_group_name = module.team_a_vnet.resource_group_name

  tags = {
    Environment = "demo"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

# Link DNS zone to all team VNets
resource "azurerm_private_dns_zone_virtual_network_link" "team_a" {
  name                  = "team-a-dns-link"
  resource_group_name   = module.team_a_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = module.team_a_vnet.vnet_id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "team_b" {
  name                  = "team-b-dns-link"
  resource_group_name   = module.team_a_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = module.team_b_vnet.vnet_id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "team_c" {
  name                  = "team-c-dns-link"
  resource_group_name   = module.team_a_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = module.team_c_vnet.vnet_id
  registration_enabled  = false
}

# Link DNS zone to transit VNet
# CRITICAL: Extract ARM VNet ID from Aviatrix format using element(split(":", vpc_id), 2)
resource "azurerm_private_dns_zone_virtual_network_link" "transit" {
  name                  = "transit-dns-link"
  resource_group_name   = module.team_a_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = element(split(":", module.azure_transit.vpc.vpc_id), 2)
  registration_enabled  = false
}

#####################
# Static DNS Records
#####################

resource "azurerm_private_dns_a_record" "db" {
  name                = "db"
  zone_name           = azurerm_private_dns_zone.this.name
  resource_group_name = module.team_a_vnet.resource_group_name
  ttl                 = 300
  records             = [var.db_private_ip]
}
