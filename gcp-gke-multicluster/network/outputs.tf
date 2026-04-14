#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.gcp_transit.transit_gateway.gw_name
  sensitive   = true
}

#####################
# Frontend VPC and Spoke
#####################

output "frontend_network_name" {
  description = "Frontend VPC network name"
  value       = module.frontend_vpc.network_name
}

output "frontend_network_id" {
  description = "Frontend VPC network ID"
  value       = module.frontend_vpc.network_id
}

output "frontend_network_self_link" {
  description = "Frontend VPC network self link"
  value       = module.frontend_vpc.network_self_link
}

output "frontend_gke_nodes_subnet_name" {
  description = "Frontend GKE node subnet name"
  value       = module.frontend_vpc.gke_nodes_subnet_name
}

output "frontend_gke_nodes_subnet_cidr" {
  description = "Frontend GKE node subnet CIDR"
  value       = module.frontend_vpc.gke_nodes_subnet_cidr
}

output "frontend_gke_nodes_subnet_self_link" {
  description = "Frontend GKE node subnet self link"
  value       = module.frontend_vpc.gke_nodes_subnet_self_link
}

output "frontend_pod_range_name" {
  description = "Frontend pod secondary range name"
  value       = module.frontend_vpc.pod_range_name
}

output "frontend_services_range_name" {
  description = "Frontend services secondary range name"
  value       = module.frontend_vpc.services_range_name
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
# Backend VPC and Spoke
#####################

output "backend_network_name" {
  description = "Backend VPC network name"
  value       = module.backend_vpc.network_name
}

output "backend_network_id" {
  description = "Backend VPC network ID"
  value       = module.backend_vpc.network_id
}

output "backend_network_self_link" {
  description = "Backend VPC network self link"
  value       = module.backend_vpc.network_self_link
}

output "backend_gke_nodes_subnet_name" {
  description = "Backend GKE node subnet name"
  value       = module.backend_vpc.gke_nodes_subnet_name
}

output "backend_gke_nodes_subnet_cidr" {
  description = "Backend GKE node subnet CIDR"
  value       = module.backend_vpc.gke_nodes_subnet_cidr
}

output "backend_gke_nodes_subnet_self_link" {
  description = "Backend GKE node subnet self link"
  value       = module.backend_vpc.gke_nodes_subnet_self_link
}

output "backend_pod_range_name" {
  description = "Backend pod secondary range name"
  value       = module.backend_vpc.pod_range_name
}

output "backend_services_range_name" {
  description = "Backend services secondary range name"
  value       = module.backend_vpc.services_range_name
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

output "db_vpc_name" {
  description = "Database spoke VPC name"
  value       = module.spoke_db.vpc.name
}

output "db_dns_name" {
  description = "Database DNS name"
  value       = "db.${var.dns_private_zone_name}"
}

#####################
# Cloud DNS
#####################

output "dns_zone_name" {
  description = "Cloud DNS private zone name (resource name, for ExternalDNS)"
  value       = google_dns_managed_zone.private.name
}

output "dns_zone_dns_name" {
  description = "Cloud DNS private zone DNS name (domain name, for ExternalDNS)"
  value       = var.dns_private_zone_name
}

#####################
# Cluster Names
#####################

output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = var.name_prefix
}

output "frontend_cluster_name" {
  description = "Frontend GKE cluster name"
  value       = local.clusters.frontend.name
}

output "backend_cluster_name" {
  description = "Backend GKE cluster name"
  value       = local.clusters.backend.name
}

#####################
# Shared Configuration
#####################

output "gcp_region" {
  description = "GCP region"
  value       = var.gcp_region
}

output "gcp_project" {
  description = "GCP project ID"
  value       = var.gcp_project
}

output "pod_cidr" {
  description = "Secondary range for pod networking (overlapping across VPCs)"
  value       = local.pod_cidr
}

output "services_cidr" {
  description = "Secondary range for Kubernetes services"
  value       = local.services_cidr
}

output "master_ipv4_cidr_block" {
  description = "CIDR block for GKE private cluster master endpoint (frontend)"
  value       = var.master_ipv4_cidr_block
}

output "backend_master_ipv4_cidr_block" {
  description = "CIDR block for GKE private cluster master endpoint (backend)"
  value       = var.backend_master_ipv4_cidr_block
}
