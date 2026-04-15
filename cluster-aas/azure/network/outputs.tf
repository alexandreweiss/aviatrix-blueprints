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
# Team-A VNet and Spoke
#####################

output "team_a_vnet_id" {
  value = module.team_a_vnet.vnet_id
}

output "team_a_vnet_name" {
  value = module.team_a_vnet.vnet_name
}

output "team_a_resource_group_name" {
  value = module.team_a_vnet.resource_group_name
}

output "team_a_aks_system_subnet_id" {
  value = module.team_a_vnet.aks_system_subnet_id
}

output "team_a_aks_system_subnet_cidr" {
  value = module.team_a_vnet.aks_system_subnet_cidr
}

output "team_a_aks_system_subnet_name" {
  value = module.team_a_vnet.aks_system_subnet_name
}

output "team_a_spoke_gateway_name" {
  value     = module.team_a_spoke.spoke_gateway.gw_name
  sensitive = true
}

#####################
# Team-B VNet and Spoke
#####################

output "team_b_vnet_id" {
  value = module.team_b_vnet.vnet_id
}

output "team_b_vnet_name" {
  value = module.team_b_vnet.vnet_name
}

output "team_b_resource_group_name" {
  value = module.team_b_vnet.resource_group_name
}

output "team_b_aks_system_subnet_id" {
  value = module.team_b_vnet.aks_system_subnet_id
}

output "team_b_aks_system_subnet_cidr" {
  value = module.team_b_vnet.aks_system_subnet_cidr
}

output "team_b_aks_system_subnet_name" {
  value = module.team_b_vnet.aks_system_subnet_name
}

output "team_b_spoke_gateway_name" {
  value     = module.team_b_spoke.spoke_gateway.gw_name
  sensitive = true
}

#####################
# Team-C VNet and Spoke
#####################

output "team_c_vnet_id" {
  value = module.team_c_vnet.vnet_id
}

output "team_c_vnet_name" {
  value = module.team_c_vnet.vnet_name
}

output "team_c_resource_group_name" {
  value = module.team_c_vnet.resource_group_name
}

output "team_c_aks_system_subnet_id" {
  value = module.team_c_vnet.aks_system_subnet_id
}

output "team_c_aks_system_subnet_cidr" {
  value = module.team_c_vnet.aks_system_subnet_cidr
}

output "team_c_aks_system_subnet_name" {
  value = module.team_c_vnet.aks_system_subnet_name
}

output "team_c_spoke_gateway_name" {
  value     = module.team_c_spoke.spoke_gateway.gw_name
  sensitive = true
}

#####################
# Database Spoke
#####################

output "db_vnet_id" {
  value = module.spoke_db.vpc.vpc_id
}

output "db_private_ip" {
  value = var.db_private_ip
}

output "db_dns_name" {
  value = "db.${var.private_dns_zone_name}"
}

#####################
# Azure Private DNS
#####################

output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.this.id
}

output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.this.name
}

output "private_dns_zone_resource_group" {
  value = module.team_a_vnet.resource_group_name
}

#####################
# Cluster Names
#####################

output "name_prefix" {
  value = local.name_prefix
}

output "team_a_cluster_name" {
  value = "${local.name_prefix}-team-a"
}

output "team_b_cluster_name" {
  value = "${local.name_prefix}-team-b"
}

output "team_c_cluster_name" {
  value = "${local.name_prefix}-team-c"
}

#####################
# Shared Configuration
#####################

output "azure_region" {
  value = var.azure_region
}

output "azure_subscription_id" {
  value     = var.azure_subscription_id
  sensitive = true
}

output "pod_cidr" {
  value = local.pod_cidr
}
