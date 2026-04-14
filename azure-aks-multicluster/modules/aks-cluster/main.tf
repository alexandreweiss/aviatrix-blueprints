#####################
# AKS Cluster Module
#
# Creates an Azure Kubernetes Service cluster with:
#   - Private cluster (API server not publicly accessible)
#   - Azure CNI Overlay for pod networking (100.64.0.0/16)
#   - Workload Identity + OIDC issuer (replaces AWS IRSA)
#   - System node pool (minimal, for system pods only)
#   - Aviatrix Controller onboarding for SmartGroup visibility
#
# Design Notes:
#   - Node groups (user pools) are managed separately in the aks-node-group module.
#     This solves the chicken-and-egg problem: cluster must exist before node pools
#     can reference its outputs.
#   - Azure CNI Overlay means pods get IPs from the overlay CIDR (100.64.0.0/16),
#     NOT from the VNet address space. This is the Azure equivalent of AWS custom
#     networking with secondary CIDRs.
#   - Workload Identity replaces IRSA: instead of annotating service accounts with
#     IAM role ARNs, you create federated credentials on Azure managed identities.
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
      version = "~> 8.2.0"
    }
  }
}

#####################
# Data Sources
#####################

data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_resource_group" "dns" {
  count = var.private_dns_zone_resource_group_name != "" ? 1 : 0
  name  = var.private_dns_zone_resource_group_name
}

#####################
# User-Assigned Managed Identity for AKS
# Required for private cluster with custom VNet
#####################

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.cluster_name}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Grant the AKS identity Network Contributor on the VNet resource group
# Required for AKS to manage load balancers and route tables
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

#####################
# AKS Cluster
#####################

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # Private cluster - API server accessible only via private endpoint
  private_cluster_enabled = true
  # Authorized IP ranges for additional API server access (e.g., CI/CD)
  # NOTE: Only applies to the public FQDN if private_cluster_public_fqdn_enabled = true
  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  # Use user-assigned identity (not system-assigned) for predictable RBAC
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # Azure CNI Overlay - pods use overlay network, not VNet IPs
  # This is the key to overlapping pod CIDRs across clusters
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = "userDefinedRouting"
  }

  # OIDC issuer + Workload Identity (replaces AWS IRSA)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # System node pool - minimal, only for system pods (CoreDNS, konnectivity, etc.)
  # User workloads go on separate node pools managed by aks-node-group module
  default_node_pool {
    name                 = "system"
    vm_size              = var.system_node_vm_size
    node_count           = var.system_node_count
    vnet_subnet_id       = var.aks_subnet_id
    os_disk_size_gb      = 50
    type                 = "VirtualMachineScaleSets"
    auto_scaling_enabled = false

    # Taint system pool so user workloads don't land here
    node_labels = {
      "nodepool-type" = "system"
    }

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Auto-upgrade channel for security patches
  automatic_upgrade_channel = "patch"

  tags = var.tags

  depends_on = [azurerm_role_assignment.aks_network_contributor]
}

#####################
# Workload Identity - ExternalDNS
# Federated credential allows ExternalDNS pod to authenticate as this identity
#####################

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "${var.cluster_name}-external-dns"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Grant ExternalDNS identity DNS Zone Contributor on the Private DNS zone
resource "azurerm_role_assignment" "external_dns" {
  count                = var.private_dns_zone_id != "" ? 1 : 0
  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

# Grant ExternalDNS Reader on the DNS zone resource group (required for zone discovery)
resource "azurerm_role_assignment" "external_dns_rg_reader" {
  count                = var.private_dns_zone_resource_group_name != "" ? 1 : 0
  scope                = data.azurerm_resource_group.dns[0].id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

resource "azurerm_federated_identity_credential" "external_dns" {
  name                = "external-dns"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.external_dns.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:kube-system:external-dns"
}

#####################
# Workload Identity - NGINX Ingress Controller
# (optional, for workloads that need Azure identity)
#####################

resource "azurerm_user_assigned_identity" "ingress" {
  name                = "${var.cluster_name}-ingress"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_federated_identity_credential" "ingress" {
  name                = "ingress-controller"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.ingress.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:kube-system:ingress-nginx"
}

#####################
# Aviatrix Controller Onboarding
#
# Register the AKS cluster with Aviatrix Controller for SmartGroup visibility.
# This enables DCF policies to reference Kubernetes workloads.
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  name = var.cluster_name

  # AKS authentication via kubeconfig
  kube_config = azurerm_kubernetes_cluster.this.kube_config_raw

  tags = var.tags
}
