#####################
# Pattern B: Namespace-as-a-Service — Azure Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in Azure
#   - 1 shared cluster VNet (all teams share a single AKS cluster)
#   - 1 Aviatrix Spoke Gateway with custom SNAT for pod traffic
#   - Azure Private DNS Zone for internal DNS
#
# Architecture:
#   Transit GW (10.28.0.0/20)
#     └── Shared Cluster Spoke (10.30.0.0/16) - single AKS cluster for all teams
#
# Team isolation is enforced by DCF SmartGroups keyed on k8s_namespace,
# NOT by separate VNets or Kubernetes RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Pod Networking:
#   Azure CNI Overlay with pod CIDR 100.64.0.0/16.
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
  name_prefix = var.name_suffix != "" ? "${var.name_prefix}-${var.name_suffix}" : var.name_prefix
  pod_cidr    = var.pod_cidr
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

  # Enable FireNet for future NGFW integration
  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  instance_size     = "Standard_B2ms"
  connected_transit = true

  # Use VPC DNS server for gateway management — required for hostname SmartGroups
  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This allows spokes with the same overlay CIDR (100.64.0.0/16)
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Shared Cluster VNet
#
# Unlike Pattern A (Cluster-as-a-Service) which creates 1 VNet per team,
# Pattern B uses a single VNet for the shared cluster. All teams' namespaces
# run in the same AKS cluster within this VNet.
#####################

module "shared_vnet" {
  source = "../../../azure-aks-multicluster/network/modules/aks-vnet"

  name      = "${local.name_prefix}-shared-vnet"
  location  = var.azure_region
  vnet_cidr = var.shared_vnet_cidr
  pod_cidr  = local.pod_cidr

  tags = {
    Environment = var.env
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}

#####################
# Spoke Gateway (Shared Cluster VNet)
#####################

module "shared_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "Azure"
  name       = "${local.name_prefix}-shared-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  instance_size = "Standard_B2ms"
  ha_gw         = false

  # Use VPC DNS server for gateway management — required for hostname SmartGroups
  enable_vpc_dns_server = true

  # Use existing VNet created by aks-vnet module
  use_existing_vpc = true
  vpc_id           = "${module.shared_vnet.vnet_name}:${module.shared_vnet.resource_group_name}:${module.shared_vnet.vnet_guid}"
  gw_subnet        = module.shared_vnet.avx_gateway_subnet_cidr
  hagw_subnet      = module.shared_vnet.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
#
# Why SNAT is needed:
#   Azure CNI Overlay pods use non-routable addresses (100.64.x.x).
#   Aviatrix transit cannot route these overlapping CIDRs.
#   SNAT translates pod source IPs to the spoke gateway IP, making traffic
#   routable across the Aviatrix transit fabric.
#
# DCF sees POST-SNAT traffic, so use VPC SmartGroups for source matching.
resource "aviatrix_gateway_snat" "shared_spoke_snat" {
  gw_name   = module.shared_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  # SNAT for AKS node subnet to internet
  snat_policy {
    src_cidr   = module.shared_vnet.aks_system_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.shared_spoke]
}

#####################
# Azure Private DNS Zone
#
# Private DNS zones in Azure are global resources linked to VNets.
# Each linked VNet can resolve records in the zone.
#####################

resource "azurerm_private_dns_zone" "this" {
  name                = var.private_dns_zone_name
  resource_group_name = module.shared_vnet.resource_group_name

  tags = {
    Environment = var.env
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}

# Link DNS zone to shared cluster VNet
resource "azurerm_private_dns_zone_virtual_network_link" "shared" {
  name                  = "shared-cluster-dns-link"
  resource_group_name   = module.shared_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = module.shared_vnet.vnet_id
  registration_enabled  = false
}

# Link DNS zone to transit VNet
# Extract ARM VNet ID: element(split(":", vpc_id), 2) for DNS links
resource "azurerm_private_dns_zone_virtual_network_link" "transit" {
  name                  = "transit-dns-link"
  resource_group_name   = module.shared_vnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = element(split(":", module.azure_transit.vpc.vpc_id), 2)
  registration_enabled  = false
}
