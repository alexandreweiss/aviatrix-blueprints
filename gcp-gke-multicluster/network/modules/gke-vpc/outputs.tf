output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.this.name
}

output "network_id" {
  description = "VPC network ID"
  value       = google_compute_network.this.id
}

output "network_self_link" {
  description = "VPC network self link"
  value       = google_compute_network.this.self_link
}

output "avx_gateway_subnet_name" {
  description = "Aviatrix gateway subnet name"
  value       = google_compute_subnetwork.avx_gateway.name
}

output "avx_gateway_subnet_cidr" {
  description = "CIDR block of the Aviatrix gateway subnet"
  value       = google_compute_subnetwork.avx_gateway.ip_cidr_range
}

output "gke_nodes_subnet_name" {
  description = "GKE node subnet name"
  value       = google_compute_subnetwork.gke_nodes.name
}

output "gke_nodes_subnet_cidr" {
  description = "CIDR block of the GKE node subnet"
  value       = google_compute_subnetwork.gke_nodes.ip_cidr_range
}

output "gke_nodes_subnet_self_link" {
  description = "GKE node subnet self link"
  value       = google_compute_subnetwork.gke_nodes.self_link
}

output "pod_range_name" {
  description = "Name of the secondary IP range for pods"
  value       = var.pod_range_name
}

output "pod_cidr" {
  description = "Secondary CIDR block for pods"
  value       = var.pod_cidr
}

output "services_range_name" {
  description = "Name of the secondary IP range for services"
  value       = var.services_range_name
}

output "services_cidr" {
  description = "Secondary CIDR block for services"
  value       = var.services_cidr
}

output "region" {
  description = "GCP region"
  value       = var.region
}
