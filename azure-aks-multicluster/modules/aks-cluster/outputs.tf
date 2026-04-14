#####################
# Cluster Identity
#####################

output "cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

#####################
# Cluster Endpoints
#####################

output "cluster_endpoint" {
  description = "AKS cluster API server endpoint (private)"
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

#####################
# Network
#####################

output "cluster_service_cidr" {
  description = "Kubernetes service CIDR"
  value       = var.service_cidr
}

output "node_resource_group" {
  description = "Auto-generated resource group for AKS node infrastructure"
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

#####################
# Identity
#####################

output "kubelet_identity" {
  description = "Kubelet managed identity (used by nodes to pull images, etc.)"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0]
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

#####################
# Workload Identity - ExternalDNS
#####################

output "external_dns_identity_client_id" {
  description = "Client ID of the ExternalDNS managed identity (for Workload Identity)"
  value       = azurerm_user_assigned_identity.external_dns.client_id
}

output "external_dns_identity_id" {
  description = "Resource ID of the ExternalDNS managed identity"
  value       = azurerm_user_assigned_identity.external_dns.id
}

#####################
# Workload Identity - Ingress
#####################

output "ingress_identity_client_id" {
  description = "Client ID of the ingress controller managed identity"
  value       = azurerm_user_assigned_identity.ingress.client_id
}

output "ingress_identity_id" {
  description = "Resource ID of the ingress controller managed identity"
  value       = azurerm_user_assigned_identity.ingress.id
}

#####################
# kubectl Configuration
#####################

output "kubectl_config_command" {
  description = "az CLI command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}

#####################
# ExternalDNS Helm Values
#####################

output "external_dns_helm_values" {
  description = "Helm values for ExternalDNS with Azure DNS provider"
  value = yamlencode({
    provider = "azure-private-dns"
    azure = {
      resourceGroup  = var.private_dns_zone_resource_group_name
      subscriptionId = data.azurerm_subscription.current.subscription_id
      tenantId       = data.azurerm_subscription.current.tenant_id
      useManagedIdentityExtension = true
    }
    serviceAccount = {
      annotations = {
        "azure.workload.identity/client-id" = azurerm_user_assigned_identity.external_dns.client_id
      }
    }
    podLabels = {
      "azure.workload.identity/use" = "true"
    }
    domainFilters = [var.private_dns_zone_name]
    policy        = "sync"
    txtOwnerId    = var.cluster_name
  })
}
