#####################
# NGINX Ingress Controller
#
# Replaces AWS ALB Controller in the Azure blueprint.
# Creates an Azure Internal Load Balancer for ingress traffic.
#
# Key differences from ALB Controller:
#   - Uses nginx instead of Application Gateway or ALB
#   - Creates an internal Azure Load Balancer (not public)
#   - No VPC ID or region needed (Azure handles this via the node's identity)
#   - Annotations control LB type (internal vs external)
#####################

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.nginx_ingress_chart_version
  namespace  = "kube-system"

  # Use internal load balancer - traffic enters via Aviatrix spoke
  values = [yamlencode({
    controller = {
      replicaCount = 2

      service = {
        annotations = {
          # Create an internal Azure Load Balancer (not public-facing)
          "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
          # Place LB in the AKS subnet
          "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = data.terraform_remote_state.network.outputs.frontend_aks_system_subnet_name
        }
        type = "LoadBalancer"
      }

      # Use Workload Identity for Azure API access (if needed)
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = data.terraform_remote_state.cluster.outputs.ingress_identity_client_id
        }
      }

      podLabels = {
        "azure.workload.identity/use" = "true"
      }

      # Node selector to run on user node pool
      nodeSelector = {
        "nodepool-type" = "user"
      }

      # Metrics for monitoring
      metrics = {
        enabled = true
      }
    }
  })]

  depends_on = [module.default_node_pool, kubernetes_config_map_v1_data.coredns_custom]
}

#####################
# ExternalDNS
#
# Automatically creates Azure Private DNS records for Kubernetes Services/Ingresses.
# Uses Workload Identity (federated credential) to authenticate with Azure DNS API.
#
# Key differences from AWS ExternalDNS:
#   - Provider: azure-private-dns (instead of aws/route53)
#   - Auth: Workload Identity (instead of IRSA)
#   - Zone: Azure Private DNS Zone (instead of Route53 private hosted zone)
#
# The Helm values are pre-computed in the aks-cluster module output to keep
# provider-specific configuration centralized.
#####################

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  # Use pre-computed Helm values from cluster module
  # This keeps Azure-specific configuration (subscription, tenant, resource group)
  # centralized in the aks-cluster module rather than duplicated here.
  values = [data.terraform_remote_state.cluster.outputs.external_dns_helm_values]

  # Additional overrides specific to this deployment
  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "txtOwnerId"
    value = data.terraform_remote_state.cluster.outputs.cluster_name
  }

  set {
    name  = "nodeSelector.nodepool-type"
    value = "user"
  }

  depends_on = [helm_release.nginx_ingress]
}
