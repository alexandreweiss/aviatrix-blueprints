terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.host
  client_certificate     = data.terraform_remote_state.cluster.outputs.client_certificate
  client_key             = data.terraform_remote_state.cluster.outputs.client_key
  cluster_ca_certificate = data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.host
    client_certificate     = data.terraform_remote_state.cluster.outputs.client_certificate
    client_key             = data.terraform_remote_state.cluster.outputs.client_key
    cluster_ca_certificate = data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
  }
}

locals {
  cluster_name  = data.terraform_remote_state.cluster.outputs.cluster_name
  dns_zone_name = data.terraform_remote_state.network.outputs.private_dns_zone_name
  name_prefix   = data.terraform_remote_state.network.outputs.name_prefix
}

# NOTE: AKS Azure CNI Powered by Cilium does not expose a cilium-config ConfigMap.
# Pod masquerade is controlled by azure-ip-masq-agent, which already lists
# 100.64.0.0/16 (pod CIDR) in NonMasqueradeCIDRs. DCF rules operate at VNet level
# (post-SNAT to spoke GW IP). Pod-level DCF requires the Aviatrix K8s controller.
