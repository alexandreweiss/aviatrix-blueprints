#####################
# Kubernetes Add-ons (Helm Charts)
#####################
# These add-ons are automatically installed after the cluster and nodes are ready
# Deployed in Layer 3 to ensure cluster and nodes exist before installation

#####################
# Gateway API Setup
#####################

# GKE has built-in Gateway API support (enabled in the cluster module via gateway_api_config).
# Unlike EKS which requires the AWS Load Balancer Controller Helm chart, GKE's GCE ingress
# controller and Gateway API implementation are managed by GKE itself.
#
# Deploy a default GatewayClass for internal load balancing via Gateway API.
# External GatewayClass (gke-l7-global-external-managed) is available by default.
resource "kubernetes_manifest" "internal_gateway_class" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "GatewayClass"
    metadata = {
      name = "gke-l7-rilb"
    }
    spec = {
      controllerName = "networking.gke.io/gateway"
      description    = "GKE internal regional L7 load balancer via Gateway API"
    }
  }

  depends_on = [module.default_node_pool]
}

#####################
# ExternalDNS
#####################

# Automatically creates Cloud DNS records for Kubernetes Service, Ingress,
# and Gateway API resources.
# Uses Workload Identity Federation instead of AWS IRSA for authentication.
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = var.external_dns_chart_version

  # Using values instead of multiple set blocks for complex configurations
  # This is more maintainable and avoids shell escaping issues
  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          # Workload Identity Federation binding (GKE equivalent of IRSA)
          "iam.gke.io/gcp-service-account" = data.terraform_remote_state.cluster.outputs.external_dns_service_account_email
        }
      }

      provider = {
        name = "google"
      }

      # Only manage records in this domain
      domainFilters = [data.terraform_remote_state.network.outputs.dns_zone_dns_name]

      # Sync mode: ExternalDNS will create AND delete records
      policy = "sync"

      # Unique identifier for this cluster's records
      txtOwnerId = data.terraform_remote_state.cluster.outputs.cluster_name

      # Google Cloud DNS-specific settings
      extraArgs = [
        "--google-project=${local.gcp_project}",
        "--google-zone-visibility=private"
      ]

      # Sources - include Gateway API routes (GKE-specific)
      sources = ["service", "ingress", "gateway-httproute", "gateway-tlsroute"]
    })
  ]

  # Install after nodes are ready
  depends_on = [
    module.default_node_pool,
  ]
}
