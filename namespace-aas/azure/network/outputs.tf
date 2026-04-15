#####################
# Pattern B: Namespace-as-a-Service — Azure Network Outputs
#####################

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
# Shared Cluster VNet
#####################

output "shared_vnet_id" {
  description = "Shared cluster VNet ID"
  value       = module.shared_vnet.vnet_id
}

output "shared_vnet_name" {
  description = "Shared cluster VNet name"
  value       = module.shared_vnet.vnet_name
}

output "shared_vnet_cidr" {
  description = "Shared cluster VNet primary CIDR"
  value       = var.shared_vnet_cidr
}

output "shared_resource_group_name" {
  description = "Shared cluster resource group name"
  value       = module.shared_vnet.resource_group_name
}

output "shared_aks_system_subnet_id" {
  description = "AKS system node pool subnet ID"
  value       = module.shared_vnet.aks_system_subnet_id
}

output "shared_aks_system_subnet_cidr" {
  description = "AKS system node pool subnet CIDR"
  value       = module.shared_vnet.aks_system_subnet_cidr
}

output "shared_aks_system_subnet_name" {
  description = "AKS system node pool subnet name"
  value       = module.shared_vnet.aks_system_subnet_name
}

#####################
# Spoke Gateway
#####################

output "shared_spoke_gateway_name" {
  description = "Shared spoke gateway name"
  value       = module.shared_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "shared_spoke_gateway_private_ip" {
  description = "Shared spoke gateway private IP (used for SNAT)"
  value       = module.shared_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# DNS
#####################

output "private_dns_zone_id" {
  description = "Azure Private DNS zone ID (for AKS ExternalDNS)"
  value       = azurerm_private_dns_zone.this.id
}

output "private_dns_zone_name" {
  description = "Azure Private DNS zone name"
  value       = azurerm_private_dns_zone.this.name
}

output "private_dns_zone_resource_group" {
  description = "Resource group containing the Private DNS zone"
  value       = module.shared_vnet.resource_group_name
}

#####################
# Cluster Configuration
#####################

output "shared_cluster_name" {
  description = "Shared AKS cluster name"
  value       = var.k8s_cluster_name
}

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
  description = "Overlay CIDR for pod networking"
  value       = local.pod_cidr
}

output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}
