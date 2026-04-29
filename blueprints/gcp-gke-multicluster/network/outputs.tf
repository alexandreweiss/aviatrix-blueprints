#####################
# Identifiers consumed by clusters/* and nodes/*
#####################

output "name_prefix" {
  value = var.name_prefix
}

output "gcp_project_id" {
  value = var.gcp_project_id
}

output "gcp_region" {
  value = var.gcp_region
}

output "gcp_zone" {
  value = var.gcp_zone
}

output "private_dns_zone_name" {
  description = "Cloud DNS private zone name (with trailing dot — Cloud DNS native form)"
  value       = var.private_dns_zone_name
}

output "private_dns_zone_resource_name" {
  description = "Cloud DNS managed-zone resource name (used by ExternalDNS Workload Identity policy bindings)"
  value       = google_dns_managed_zone.main.name
}

#####################
# Frontend
#####################

output "frontend_cluster_name" {
  value = local.clusters.frontend.name
}

output "frontend_cluster_id" {
  description = "Constructed GKE cluster self_link for K8s SmartGroups (matches what clusters/frontend onboards)"
  value       = local.frontend_cluster_id
}

output "frontend_vpc_name" {
  value = module.frontend_vpc.vpc_name
}

output "frontend_vpc_self_link" {
  value = module.frontend_vpc.vpc_self_link
}

output "frontend_nodes_subnet_name" {
  value = module.frontend_vpc.nodes_subnet_name
}

output "frontend_pods_range_name" {
  value = module.frontend_vpc.pods_range_name
}

output "frontend_services_range_name" {
  value = module.frontend_vpc.services_range_name
}

output "frontend_master_cidr" {
  value = var.frontend_master_cidr
}

output "frontend_spoke_gateway_public_ip" {
  description = "Public egress IP of the frontend spoke GW (must be allowlisted on the GKE master_authorized_networks)"
  value       = nonsensitive(module.frontend_spoke.spoke_gateway.public_ip)
}

output "frontend_gateway_global_ip_name" {
  description = "Reserved global address name for the GKE Gateway (referenced by HTTPRoute / Gateway annotations in nodes/frontend)"
  value       = google_compute_global_address.frontend_gateway.name
}

output "frontend_gateway_global_ip_address" {
  description = "Reserved IPv4 address for the frontend Gateway"
  value       = google_compute_global_address.frontend_gateway.address
}

#####################
# Backend
#####################

output "backend_cluster_name" {
  value = local.clusters.backend.name
}

output "backend_cluster_id" {
  description = "Constructed GKE cluster self_link for K8s SmartGroups (matches what clusters/backend onboards)"
  value       = local.backend_cluster_id
}

output "backend_vpc_name" {
  value = module.backend_vpc.vpc_name
}

output "backend_vpc_self_link" {
  value = module.backend_vpc.vpc_self_link
}

output "backend_nodes_subnet_name" {
  value = module.backend_vpc.nodes_subnet_name
}

output "backend_pods_range_name" {
  value = module.backend_vpc.pods_range_name
}

output "backend_services_range_name" {
  value = module.backend_vpc.services_range_name
}

output "backend_master_cidr" {
  value = var.backend_master_cidr
}

output "backend_spoke_gateway_public_ip" {
  value = nonsensitive(module.backend_spoke.spoke_gateway.public_ip)
}

output "backend_gateway_global_ip_name" {
  value = google_compute_global_address.backend_gateway.name
}

output "backend_gateway_global_ip_address" {
  value = google_compute_global_address.backend_gateway.address
}

#####################
# Pod / service ranges (shared)
#####################

output "frontend_pods_cidr" {
  value = var.frontend_pods_cidr
}

output "backend_pods_cidr" {
  value = var.backend_pods_cidr
}

output "services_cidr" {
  value = var.services_cidr
}

#####################
# DCF outputs (validation / cross-references)
#####################

output "dcf_ruleset_uuid" {
  value = aviatrix_dcf_ruleset.gke_demo.id
}

output "smartgroup_frontend_vpc_uuid" {
  value = aviatrix_smart_group.frontend_vpc.uuid
}

output "smartgroup_backend_vpc_uuid" {
  value = aviatrix_smart_group.backend_vpc.uuid
}

output "webgroup_gcp_required_uuid" {
  value = aviatrix_web_group.gcp_required.uuid
}

output "webgroup_github_aviatrix_uuid" {
  value = aviatrix_web_group.github_aviatrix.uuid
}

output "smartgroup_frontend_gatus_ns_uuid" {
  value = try(aviatrix_smart_group.frontend_gatus_ns[0].uuid, null)
}

output "smartgroup_backend_gatus_ns_uuid" {
  value = try(aviatrix_smart_group.backend_gatus_ns[0].uuid, null)
}
