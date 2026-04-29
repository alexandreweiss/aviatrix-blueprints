output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_self_link" {
  description = "GKE cluster self_link — used as cluster_id by aviatrix_kubernetes_cluster and K8s SmartGroups"
  value       = google_container_cluster.this.self_link
}

output "cluster_endpoint" {
  description = "Public master endpoint (for kubectl after master_authorized_networks allowlists your IP)"
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Cluster CA cert (base64) — consumed by the kubernetes/helm providers in nodes/"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  value = google_service_account.node.email
}

output "external_dns_service_account_email" {
  description = "GSA email bound to KSA kube-system/external-dns via Workload Identity Federation"
  value       = google_service_account.external_dns.email
}

output "workload_identity_pool" {
  value = "${data.terraform_remote_state.network.outputs.gcp_project_id}.svc.id.goog"
}
