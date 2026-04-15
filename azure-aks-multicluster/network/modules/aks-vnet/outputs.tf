#####################
# Resource Group
#####################

output "resource_group_name" {
  description = "Resource group name containing the VNet"
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "Resource group ID"
  value       = azurerm_resource_group.this.id
}

#####################
# VNet
#####################

output "vnet_id" {
  description = "Virtual Network ARM resource ID"
  value       = azurerm_virtual_network.this.id
}

output "vnet_guid" {
  description = "Virtual Network GUID (used for Aviatrix vpc_id format)"
  value       = azurerm_virtual_network.this.guid
}

output "vnet_name" {
  description = "Virtual Network name"
  value       = azurerm_virtual_network.this.name
}

output "vnet_cidr" {
  description = "VNet primary CIDR block"
  value       = var.vnet_cidr
}

#####################
# Subnets
#####################

output "avx_gateway_subnet_id" {
  description = "Aviatrix gateway subnet ID"
  value       = azurerm_subnet.avx_gateway.id
}

output "avx_gateway_subnet_cidr" {
  description = "Aviatrix gateway subnet CIDR"
  value       = azurerm_subnet.avx_gateway.address_prefixes[0]
}

output "aks_system_subnet_id" {
  description = "AKS system node pool subnet ID"
  value       = azurerm_subnet.aks_system.id
}

output "aks_system_subnet_cidr" {
  description = "AKS system node pool subnet CIDR"
  value       = azurerm_subnet.aks_system.address_prefixes[0]
}

output "aks_system_subnet_name" {
  description = "AKS system node pool subnet name"
  value       = azurerm_subnet.aks_system.name
}

#####################
# Pod CIDR (pass-through)
#####################

output "pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay (configured at AKS cluster level)"
  value       = var.pod_cidr
}

#####################
# Route Table
#####################

output "aks_route_table_id" {
  description = "Route table ID for AKS subnets (managed by Aviatrix)"
  value       = azurerm_route_table.aks.id
}

#####################
# Location
#####################

output "location" {
  description = "Azure region"
  value       = azurerm_resource_group.this.location
}
