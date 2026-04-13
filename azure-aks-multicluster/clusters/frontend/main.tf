#####################
# AKS Cluster Layer (Layer 2) - Frontend
#
# Provisions the AKS control plane using outputs from the network layer.
# Node pools are managed separately in Layer 3 (nodes/).
#
# Authentication:
#   - Aviatrix: AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD env vars
#   - Azure: az login or service principal env vars (ARM_*)
#   - Kubernetes: kubeconfig from AKS cluster output
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aviatrix" {
  skip_version_validation = true
}

provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.network.outputs.azure_subscription_id
}

provider "azuread" {}

provider "kubernetes" {
  host                   = module.frontend_aks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.frontend_aks.cluster_certificate_authority_data)

  # Use az CLI for authentication (works with both interactive and service principal)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "az"
    args = [
      "aks", "get-credentials",
      "--resource-group", data.terraform_remote_state.network.outputs.frontend_resource_group_name,
      "--name", data.terraform_remote_state.network.outputs.frontend_cluster_name,
      "--format", "exec-credential"
    ]
  }
}

#####################
# Frontend AKS Cluster
#####################

module "frontend_aks" {
  source = "../../modules/aks-cluster"

  cluster_name        = data.terraform_remote_state.network.outputs.frontend_cluster_name
  resource_group_name = data.terraform_remote_state.network.outputs.frontend_resource_group_name
  location            = data.terraform_remote_state.network.outputs.azure_region
  kubernetes_version  = var.kubernetes_version

  # Network configuration from Layer 1
  aks_subnet_id = data.terraform_remote_state.network.outputs.frontend_aks_system_subnet_id
  pod_cidr      = data.terraform_remote_state.network.outputs.pod_cidr

  # Private DNS for ExternalDNS
  private_dns_zone_id                 = data.terraform_remote_state.network.outputs.private_dns_zone_id
  private_dns_zone_name               = data.terraform_remote_state.network.outputs.private_dns_zone_name
  private_dns_zone_resource_group_name = data.terraform_remote_state.network.outputs.private_dns_zone_resource_group

  # Aviatrix onboarding for SmartGroup visibility
  enable_aviatrix_onboarding = true

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }
}
