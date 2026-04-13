#####################
# Node Pool
#####################

output "node_pool_id" {
  description = "Default user node pool ID"
  value       = module.default_node_pool.node_pool_id
}

output "node_pool_name" {
  description = "Default user node pool name"
  value       = module.default_node_pool.node_pool_name
}

#####################
# Helm Releases
#####################

output "nginx_ingress_status" {
  description = "NGINX ingress controller Helm release status"
  value       = helm_release.nginx_ingress.status
}

output "external_dns_status" {
  description = "ExternalDNS Helm release status"
  value       = helm_release.external_dns.status
}

output "k8s_firewall_status" {
  description = "Aviatrix k8s-firewall Helm release status"
  value       = helm_release.k8s_firewall.status
}
