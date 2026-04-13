output "node_pool_id" {
  description = "AKS node pool ID"
  value       = azurerm_kubernetes_cluster_node_pool.this.id
}

output "node_pool_name" {
  description = "AKS node pool name"
  value       = azurerm_kubernetes_cluster_node_pool.this.name
}

output "node_pool_vm_size" {
  description = "VM size of the node pool"
  value       = azurerm_kubernetes_cluster_node_pool.this.vm_size
}

output "node_pool_node_count" {
  description = "Current node count"
  value       = azurerm_kubernetes_cluster_node_pool.this.node_count
}

output "node_pool_priority" {
  description = "Node pool priority (Regular or Spot)"
  value       = azurerm_kubernetes_cluster_node_pool.this.priority
}
