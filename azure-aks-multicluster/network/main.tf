#####################
# Azure AKS Multi-Cluster Blueprint - Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in Azure
#   - VNets for frontend, backend, and database spokes
#   - Aviatrix Spoke Gateways with custom SNAT for pod traffic
#   - Azure Private DNS Zone for internal service discovery
#
# Architecture:
#   Transit GW (10.32.0.0/20)
#     ├── Frontend Spoke (10.30.0.0/20) - AKS frontend cluster
#     ├── Backend Spoke (10.31.0.0/20)  - AKS backend cluster
#     └── Database Spoke (10.35.0.0/22) - Database VM
#
# Pod Networking:
#   Azure CNI Overlay with pod CIDR 100.64.0.0/16 (overlapping across VNets).
#   Pods use non-routable overlay addresses. Aviatrix SNAT translates pod traffic
#   to spoke gateway IPs for east-west and egress flows.
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
  # Non-routable overlay CIDR for pods - same across all VNets (overlapping)
  pod_cidr = var.pod_cidr

  # Cluster configurations
  clusters = {
    frontend = {
      name      = "${var.name_prefix}-frontend"
      vnet_cidr = var.frontend_vnet_cidr
    }
    backend = {
      name      = "${var.name_prefix}-backend"
      vnet_cidr = var.backend_vnet_cidr
    }
  }
}

#####################
# Aviatrix Transit Gateway
#####################

module "azure_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.2.0"

  name    = "${var.name_prefix}-transit"
  cloud   = "Azure"
  account = var.aviatrix_azure_account_name
  region  = var.azure_region
  cidr    = var.transit_cidr
  ha_gw   = false

  # Enable FireNet for future NGFW integration
  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  instance_size     = "Standard_B2ms"
  connected_transit = true

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Azure Private DNS zones)
  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This allows multiple spokes with the same overlay CIDR (100.64.0.0/16)
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Frontend VNet and Spoke
#####################

module "frontend_vnet" {
  source = "./modules/aks-vnet"

  name     = "frontend"
  location = var.azure_region
  vnet_cidr = local.clusters.frontend.vnet_cidr
  pod_cidr  = local.pod_cidr

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }
}

module "frontend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "Azure"
  name       = "${var.name_prefix}-frontend-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  instance_size = "Standard_B2ms"
  ha_gw         = false

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Azure Private DNS zones)
  enable_vpc_dns_server = true

  # Use existing VNet created by aks-vnet module
  use_existing_vpc    = true
  vpc_id              = "${module.frontend_vnet.vnet_name}:${module.frontend_vnet.resource_group_name}:${module.frontend_vnet.vnet_guid}"
  gw_subnet           = module.frontend_vnet.avx_gateway_subnet_cidr
  hagw_subnet         = module.frontend_vnet.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
#
# Why SNAT is needed:
#   Azure CNI Overlay pods use non-routable addresses (100.64.x.x).
#   Aviatrix transit cannot route these overlapping CIDRs between spokes.
#   SNAT translates pod source IPs to the spoke gateway IP, making traffic
#   routable across the Aviatrix transit fabric.
#
# SNAT Policy Order:
#   1. Pod traffic -> transit (east-west between spokes)
#   2. Pod traffic -> internet via eth0
#   3. Node subnet traffic -> internet via eth0
resource "aviatrix_gateway_snat" "frontend_spoke_snat" {
  gw_name   = module.frontend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # SNAT for AKS node subnet to internet
  snat_policy {
    src_cidr   = module.frontend_vnet.aks_system_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.frontend_spoke]
}

#####################
# Backend VNet and Spoke
#####################

module "backend_vnet" {
  source = "./modules/aks-vnet"

  name      = "backend"
  location  = var.azure_region
  vnet_cidr = local.clusters.backend.vnet_cidr
  pod_cidr  = local.pod_cidr

  tags = {
    Environment = "demo"
    Cluster     = "backend"
    Terraform   = "true"
  }
}

module "backend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "Azure"
  name       = "${var.name_prefix}-backend-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  instance_size = "Standard_B2ms"
  ha_gw         = false

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Azure Private DNS zones)
  enable_vpc_dns_server = true

  # Use existing VNet created by aks-vnet module
  use_existing_vpc    = true
  vpc_id              = "${module.backend_vnet.vnet_name}:${module.backend_vnet.resource_group_name}:${module.backend_vnet.vnet_guid}"
  gw_subnet           = module.backend_vnet.avx_gateway_subnet_cidr
  hagw_subnet         = module.backend_vnet.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
resource "aviatrix_gateway_snat" "backend_spoke_snat" {
  gw_name   = module.backend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  # SNAT for AKS node subnet to internet
  snat_policy {
    src_cidr   = module.backend_vnet.aks_system_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.backend_spoke]
}

#####################
# Database Spoke
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud          = "Azure"
  name           = "${var.name_prefix}-db-spoke"
  cidr           = var.db_vnet_cidr
  account        = var.aviatrix_azure_account_name
  region         = var.azure_region
  transit_gw     = module.azure_transit.transit_gateway.gw_name
  instance_size  = "Standard_B2ms"
  ha_gw          = false
  single_ip_snat = true

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Azure Private DNS zones)
  enable_vpc_dns_server = true
}

#####################
# Azure Private DNS Zone
#
# Private DNS zones in Azure are global resources linked to VNets.
# Each linked VNet can resolve records in the zone.
# This replaces Route53 private hosted zones from the AWS blueprint.
#####################

resource "azurerm_private_dns_zone" "this" {
  name                = var.private_dns_zone_name
  resource_group_name = module.frontend_vnet.resource_group_name

  tags = {
    Environment = "demo"
    Terraform   = "true"
  }
}

# Link DNS zone to frontend VNet
resource "azurerm_private_dns_zone_virtual_network_link" "frontend" {
  name                  = "frontend-dns-link"
  resource_group_name   = module.frontend_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = module.frontend_vnet.vnet_id
  registration_enabled  = false
}

# Link DNS zone to backend VNet
resource "azurerm_private_dns_zone_virtual_network_link" "backend" {
  name                  = "backend-dns-link"
  resource_group_name   = module.frontend_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = module.backend_vnet.vnet_id
  registration_enabled  = false
}

# Link DNS zone to transit VNet
resource "azurerm_private_dns_zone_virtual_network_link" "transit" {
  name                  = "transit-dns-link"
  resource_group_name   = module.frontend_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = element(split(":", module.azure_transit.vpc.vpc_id), 2)
  registration_enabled  = false
}

#####################
# Static DNS Records
#####################

# Database record (placeholder - update with actual DB IP after provisioning)
resource "azurerm_private_dns_a_record" "db" {
  name                = "db"
  zone_name           = azurerm_private_dns_zone.this.name
  resource_group_name = module.frontend_vnet.resource_group_name
  ttl                 = 300
  records             = [var.db_private_ip]
}
