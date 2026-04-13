output "cluster_endpoint" {
  value = module.frontend_gke.cluster_endpoint
}

output "cluster_ca_certificate" {
  value     = module.frontend_gke.cluster_ca_certificate
  sensitive = true
}

output "cluster_name" {
  value = module.frontend_gke.cluster_name
}

output "cluster_location" {
  value = module.frontend_gke.cluster_location
}

output "external_dns_service_account_email" {
  value = module.frontend_gke.external_dns_service_account_email
}
