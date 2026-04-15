# -----------------------------------------------------------------------------
# Pattern C: AKS Production Cluster
# Dedicated production cluster in isolated VNet
# Azure CNI Overlay + Workload Identity
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "aviatrix" {
  skip_version_validation = true
}

module "aks_prod" {
  source = "../../../../azure-aks-multicluster/modules/aks-cluster"

  cluster_name        = "${var.environment_prefix}-prod"
  resource_group_name = var.resource_group_name
  location            = var.azure_region
  kubernetes_version  = var.kubernetes_version

  # Azure CNI Overlay networking
  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  pod_cidr            = var.pod_cidr

  vnet_id   = var.vnet_id
  subnet_id = var.subnet_id

  # Workload Identity
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Default node pool
  default_node_pool = {
    name                = "system"
    vm_size             = var.node_vm_size
    enable_auto_scaling = true
    min_count           = var.node_min_count
    max_count           = var.node_max_count
    os_disk_size_gb     = 128
    node_labels = {
      "environment" = "production"
      "cluster"     = "prod"
    }
  }

  tags = {
    Environment = "production"
    Pattern     = "C"
    ManagedBy   = "terraform"
  }
}

#####################
# Aviatrix Kubernetes Cluster Onboarding
#####################

# resource "aviatrix_kubernetes_cluster" "this" {
#   cluster_id          = module.aks_prod.cluster_id
#   use_csp_credentials = true
# }
