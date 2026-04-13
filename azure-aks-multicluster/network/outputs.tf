#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.azure_transit.transit_gateway.gw_name
  sensitive   = true
}

output "transit_vnet_id" {
  description = "Transit VNet ID"
  value       = module.azure_transit.vpc.vpc_id
}

#####################
# Frontend VNet and Spoke
#####################

output "frontend_vnet_id" {
  description = "Frontend VNet ID"
  value       = module.frontend_vnet.vnet_id
}

output "frontend_vnet_name" {
  description = "Frontend VNet name"
  value       = module.frontend_vnet.vnet_name
}

output "frontend_vnet_cidr" {
  description = "Frontend VNet primary CIDR"
  value       = module.frontend_vnet.vnet_cidr
}

output "frontend_resource_group_name" {
  description = "Frontend resource group name"
  value       = module.frontend_vnet.resource_group_name
}

output "frontend_aks_system_subnet_id" {
  description = "Frontend AKS system node pool subnet ID"
  value       = module.frontend_vnet.aks_system_subnet_id
}

output "frontend_aks_system_subnet_cidr" {
  description = "Frontend AKS system node pool subnet CIDR"
  value       = module.frontend_vnet.aks_system_subnet_cidr
}

output "frontend_aks_system_subnet_name" {
  description = "Frontend AKS system node pool subnet name"
  value       = module.frontend_vnet.aks_system_subnet_name
}

output "frontend_spoke_gateway_name" {
  description = "Frontend spoke gateway name"
  value       = module.frontend_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "frontend_spoke_gateway_private_ip" {
  description = "Frontend spoke gateway private IP for SNAT"
  value       = module.frontend_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# Backend VNet and Spoke
#####################

output "backend_vnet_id" {
  description = "Backend VNet ID"
  value       = module.backend_vnet.vnet_id
}

output "backend_vnet_name" {
  description = "Backend VNet name"
  value       = module.backend_vnet.vnet_name
}

output "backend_vnet_cidr" {
  description = "Backend VNet primary CIDR"
  value       = module.backend_vnet.vnet_cidr
}

output "backend_resource_group_name" {
  description = "Backend resource group name"
  value       = module.backend_vnet.resource_group_name
}

output "backend_aks_system_subnet_id" {
  description = "Backend AKS system node pool subnet ID"
  value       = module.backend_vnet.aks_system_subnet_id
}

output "backend_aks_system_subnet_cidr" {
  description = "Backend AKS system node pool subnet CIDR"
  value       = module.backend_vnet.aks_system_subnet_cidr
}

output "backend_spoke_gateway_name" {
  description = "Backend spoke gateway name"
  value       = module.backend_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "backend_spoke_gateway_private_ip" {
  description = "Backend spoke gateway private IP for SNAT"
  value       = module.backend_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# Database Spoke
#####################

output "db_vnet_id" {
  description = "Database spoke VNet ID"
  value       = module.spoke_db.vpc.vpc_id
}

output "db_private_ip" {
  description = "Database VM private IP address"
  value       = var.db_private_ip
}

output "db_dns_name" {
  description = "Database DNS name"
  value       = "db.${var.private_dns_zone_name}"
}

#####################
# Azure Private DNS
#####################

output "private_dns_zone_id" {
  description = "Azure Private DNS zone ID (for AKS ExternalDNS)"
  value       = azurerm_private_dns_zone.this.id
}

output "private_dns_zone_name" {
  description = "Azure Private DNS zone name (for AKS ExternalDNS)"
  value       = azurerm_private_dns_zone.this.name
}

output "private_dns_zone_resource_group" {
  description = "Resource group containing the Private DNS zone"
  value       = module.frontend_vnet.resource_group_name
}

#####################
# Cluster Names
#####################

output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = var.name_prefix
}

output "frontend_cluster_name" {
  description = "Frontend AKS cluster name"
  value       = local.clusters.frontend.name
}

output "backend_cluster_name" {
  description = "Backend AKS cluster name"
  value       = local.clusters.backend.name
}

#####################
# Shared Configuration
#####################

output "azure_region" {
  description = "Azure region"
  value       = var.azure_region
}

output "azure_subscription_id" {
  description = "Azure subscription ID"
  value       = var.azure_subscription_id
  sensitive   = true
}

output "pod_cidr" {
  description = "Overlay CIDR for pod networking (overlapping across VNets)"
  value       = local.pod_cidr
}
