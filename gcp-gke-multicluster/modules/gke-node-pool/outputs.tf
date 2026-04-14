output "node_pool_id" {
  description = "GKE node pool ID"
  value       = google_container_node_pool.this.id
}

output "node_pool_name" {
  description = "GKE node pool name"
  value       = google_container_node_pool.this.name
}

output "instance_group_urls" {
  description = "List of instance group URLs for the node pool"
  value       = google_container_node_pool.this.instance_group_urls
}

output "managed_instance_group_urls" {
  description = "List of managed instance group URLs for the node pool"
  value       = google_container_node_pool.this.managed_instance_group_urls
}
