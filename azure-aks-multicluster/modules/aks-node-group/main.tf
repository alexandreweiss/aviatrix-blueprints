#####################
# AKS User Node Pool Module
#
# Creates AKS user node pools SEPARATELY from the cluster, solving the
# chicken-and-egg problem: cluster must exist before node pools can reference
# its outputs (OIDC issuer, identity, etc.).
#
# This module is deployed AFTER the cluster exists (Layer 3).
#
# Key differences from EKS node groups:
#   - AKS uses "node pools" (not "managed node groups")
#   - Spot VMs replace AWS Spot Instances (similar concept, different API)
#   - No launch templates needed - AKS handles VM configuration natively
#   - Labels and taints are first-class AKS node pool properties
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

#####################
# Data Sources
#####################

data "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

#####################
# User Node Pool
#####################

resource "azurerm_kubernetes_cluster_node_pool" "this" {
  name                  = var.node_pool_name
  kubernetes_cluster_id = data.azurerm_kubernetes_cluster.this.id
  vm_size               = var.vm_size
  vnet_subnet_id        = var.subnet_id

  # Scaling configuration
  auto_scaling_enabled = var.auto_scaling_enabled
  min_count            = var.auto_scaling_enabled ? var.min_count : null
  max_count            = var.auto_scaling_enabled ? var.max_count : null
  node_count           = var.auto_scaling_enabled ? null : var.node_count

  # Spot VM configuration (Azure equivalent of AWS Spot Instances)
  priority        = var.priority
  eviction_policy = var.priority == "Spot" ? "Delete" : null
  spot_max_price  = var.priority == "Spot" ? var.spot_max_price : null

  # OS configuration
  os_disk_size_gb = var.os_disk_size_gb
  os_disk_type    = var.os_disk_type
  os_type         = "Linux"
  os_sku          = "Ubuntu"

  # Kubernetes labels and taints
  node_labels = var.node_labels
  node_taints = var.node_taints

  dynamic "node_network_profile" {
    for_each = [] # Reserved for future network policy configuration
    content {}
  }

  upgrade_settings {
    max_surge = var.max_surge
  }

  tags = merge(var.tags, {
    Name     = "${var.cluster_name}-${var.node_pool_name}"
    NodePool = var.node_pool_name
  })
}

