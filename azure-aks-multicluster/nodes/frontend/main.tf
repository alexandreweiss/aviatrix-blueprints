#####################
# AKS Node Layer (Layer 3) - Frontend
#
# Provisions:
#   - User node pool via aks-node-group module
#   - Aviatrix k8s-firewall Helm chart (CRDs for in-cluster DCF policies)
#   - CoreDNS configuration for Azure Private DNS resolution
#   - NGINX Ingress Controller (Helm) - replaces AWS ALB Controller
#   - ExternalDNS (Helm) with Azure Private DNS provider
#
# This layer runs AFTER:
#   - Layer 1 (network/) - VNet, Aviatrix transit/spoke, Private DNS
#   - Layer 2 (clusters/) - AKS control plane, Workload Identity setup
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "az"
    args = [
      "aks", "get-credentials",
      "--resource-group", data.terraform_remote_state.network.outputs.frontend_resource_group_name,
      "--name", data.terraform_remote_state.cluster.outputs.cluster_name,
      "--format", "exec-credential"
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "az"
      args = [
        "aks", "get-credentials",
        "--resource-group", data.terraform_remote_state.network.outputs.frontend_resource_group_name,
        "--name", data.terraform_remote_state.cluster.outputs.cluster_name,
        "--format", "exec-credential"
      ]
    }
  }
}

#####################
# Aviatrix k8s-firewall (CRDs)
#
# Installs FirewallPolicy and WebGroupPolicy CRDs for in-cluster DCF controls.
# These enable namespace-level and pod-label-level policies applied via kubectl.
#####################

resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"

  wait = false

  recreate_pods = false
}

#####################
# User Node Pool
#
# NOTE: Unlike EKS, AKS does not need ENIConfig resources.
# Azure CNI Overlay handles pod networking transparently - pods get IPs from
# the overlay CIDR (100.64.0.0/16) without needing per-AZ subnet mappings.
#####################

module "default_node_pool" {
  source = "../../modules/aks-node-group"

  cluster_name        = data.terraform_remote_state.cluster.outputs.cluster_name
  resource_group_name = data.terraform_remote_state.network.outputs.frontend_resource_group_name

  subnet_id = data.terraform_remote_state.network.outputs.frontend_aks_system_subnet_id

  node_pool_name = "default"
  min_count      = var.node_pool_config.min_count
  max_count      = var.node_pool_config.max_count
  node_count     = var.node_pool_config.node_count
  vm_size        = var.node_pool_config.vm_size
  priority       = var.node_pool_config.priority

  node_labels = {
    "nodepool-type" = "user"
    "workload"      = "frontend"
  }

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }
}

#####################
# CoreDNS ConfigMap Patch
#
# Configure CoreDNS to forward queries for the private DNS zone to Azure DNS (168.63.129.16).
# This enables pods to resolve internal service names (e.g., db.azure.aviatrixdemo.local).
#
# NOTE: AKS manages CoreDNS as a system addon. We patch the configmap rather than
# replacing it, to preserve AKS's default configuration.
#####################

resource "kubernetes_config_map_v1_data" "coredns_custom" {
  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }

  data = {
    "private-dns.server" = <<-EOF
      ${data.terraform_remote_state.network.outputs.private_dns_zone_name}:53 {
          forward . 168.63.129.16
          cache 30
          log
          errors
      }
    EOF
  }

  force = true

  depends_on = [module.default_node_pool]
}
