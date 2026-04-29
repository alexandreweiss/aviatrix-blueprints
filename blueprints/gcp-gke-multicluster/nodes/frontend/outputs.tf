output "external_dns_namespace" {
  value = helm_release.external_dns.namespace
}

output "k8s_firewall_namespace" {
  value = helm_release.k8s_firewall.namespace
}
