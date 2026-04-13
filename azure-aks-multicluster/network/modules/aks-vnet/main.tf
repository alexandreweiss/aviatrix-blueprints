#####################
# AKS VNet Module
#
# Creates an Azure Virtual Network with subnets optimized for AKS with Aviatrix:
#   - Aviatrix gateway subnet (/28) - for Aviatrix spoke gateway ENIs
#   - AKS system node pool subnet (/22) - for system and user node pools
#   - AKS pod subnet (/16) - for Azure CNI Overlay pod networking
#
# Design Notes:
#   - The pod subnet uses Azure CNI Overlay, so the 100.64.0.0/16 CIDR is NOT routed
#     on the VNet. Instead, Azure handles encapsulation. This means the pod CIDR can
#     safely overlap across VNets (same pattern as AWS secondary CIDR).
#   - The Aviatrix gateway subnet is small (/28) since it only needs 2 IPs (GW + HA).
#   - NSGs are created per-subnet for defense-in-depth alongside Aviatrix DCF.
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

#####################
# Resource Group
#####################

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-vnet-rg"
  location = var.location

  tags = var.tags
}

#####################
# Virtual Network
#####################

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

#####################
# Subnets
#
# Subnet layout within the VNet CIDR:
#   - avx-gw:     /28 (16 IPs)  - Aviatrix spoke gateway
#   - aks-system:  /22 (1024 IPs) - AKS system + user node pools
#   - aks-pods:   Overlay /16    - Not a real subnet, Azure CNI Overlay uses this
#
# NOTE: The pod CIDR (100.64.0.0/16) is configured at the AKS cluster level
# as an overlay network, NOT as a VNet subnet. Azure CNI Overlay encapsulates
# pod traffic, making it invisible to the VNet routing plane.
#####################

resource "azurerm_subnet" "avx_gateway" {
  name                 = "${var.name}-avx-gw"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, var.avx_gw_newbits, 0)]
}

resource "azurerm_subnet" "aks_system" {
  name                 = "${var.name}-aks-system"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, var.aks_system_newbits, var.aks_system_netnum)]
}

#####################
# Network Security Groups
#####################

resource "azurerm_network_security_group" "avx_gateway" {
  name                = "${var.name}-avx-gw-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  tags = var.tags
}

resource "azurerm_network_security_group" "aks_system" {
  name                = "${var.name}-aks-system-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  tags = var.tags
}

#####################
# NSG Associations
#####################

resource "azurerm_subnet_network_security_group_association" "avx_gateway" {
  subnet_id                 = azurerm_subnet.avx_gateway.id
  network_security_group_id = azurerm_network_security_group.avx_gateway.id
}

resource "azurerm_subnet_network_security_group_association" "aks_system" {
  subnet_id                 = azurerm_subnet.aks_system.id
  network_security_group_id = azurerm_network_security_group.aks_system.id
}

#####################
# Route Table for AKS Subnets
# Aviatrix controller will manage routes dynamically
#####################

resource "azurerm_route_table" "aks" {
  name                = "${var.name}-aks-rt"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  # Disable BGP route propagation - Aviatrix manages routing
  bgp_route_propagation_enabled = false

  tags = var.tags

  # Aviatrix controller dynamically manages routes in this table
  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet_route_table_association" "aks_system" {
  subnet_id      = azurerm_subnet.aks_system.id
  route_table_id = azurerm_route_table.aks.id
}
