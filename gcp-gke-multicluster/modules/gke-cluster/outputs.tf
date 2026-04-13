output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.this.id
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Endpoint for GKE control plane"
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_master_version" {
  description = "Master version of the GKE cluster"
  value       = google_container_cluster.this.master_version
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = "${var.project}.svc.id.goog"
}

output "external_dns_service_account_email" {
  description = "GCP service account email for ExternalDNS (Workload Identity)"
  value       = google_service_account.external_dns.email
}

output "gateway_controller_service_account_email" {
  description = "GCP service account email for Gateway Controller (Workload Identity)"
  value       = google_service_account.gateway_controller.email
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project}"
}

output "dns_zone_name" {
  description = "Cloud DNS zone name (if configured)"
  value       = var.dns_zone_name
}

output "dns_zone_dns_name" {
  description = "Cloud DNS zone DNS name (if configured)"
  value       = var.dns_zone_dns_name
}

output "external_dns_helm_values" {
  description = "Helm values for ExternalDNS deployment with Google Cloud DNS"
  value = var.dns_zone_name != "" ? {
    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.external_dns.email
      }
    }
    provider      = "google"
    sources       = ["service", "ingress", "gateway-httproute", "gateway-tlsroute"]
    domainFilters = [var.dns_zone_dns_name]
    policy        = "sync"
    txtOwnerId    = var.cluster_name
    extraArgs = [
      "--google-project=${var.project}",
      "--google-zone-visibility=private"
    ]
  } : null
}
