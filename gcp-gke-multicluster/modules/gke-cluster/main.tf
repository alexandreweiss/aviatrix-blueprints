terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

#####################
# GKE Cluster (Control Plane Only)
#####################

# GKE cluster with VPC-native networking, Workload Identity, and private endpoint
# Node pools are managed separately in the gke-node-pool module (Layer 3)
# This solves the chicken-and-egg problem where node pool count/for_each
# depends on cluster outputs that don't exist during initial plan
resource "google_container_cluster" "this" {
  provider = google-beta

  name     = var.cluster_name
  project  = var.project
  location = var.region

  # Use release channel for automatic upgrades
  release_channel {
    channel = var.release_channel
  }

  # Remove default node pool - we manage node pools separately in Layer 3
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native networking with alias IP ranges
  # This is the GKE equivalent of EKS custom networking with ENIConfig.
  # Instead of secondary CIDRs + ENIConfig CRDs, GKE uses secondary ranges natively.
  network    = var.network
  subnetwork = var.subnetwork

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Networking configuration
  networking_mode = "VPC_NATIVE"

  # Datapath provider - use advanced datapath (Dataplane V2 / Cilium) for
  # improved network policy enforcement and observability
  datapath_provider = "ADVANCED_DATAPATH"

  # Private cluster configuration
  # Nodes have no external IPs; master is accessible via private endpoint
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Allow public access to API server for management
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  # Master authorized networks - restrict API server access
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity Federation - GKE equivalent of AWS IRSA
  # Allows pods to authenticate as GCP service accounts without key files
  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }

  # Gateway API support (replaces AWS ALB Controller pattern)
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Cluster addons
  addons_config {
    # Enable HTTP load balancing (GCE Ingress Controller)
    http_load_balancing {
      disabled = false
    }

    # Enable horizontal pod autoscaling
    horizontal_pod_autoscaling {
      disabled = false
    }

    # DNS cache for improved DNS performance
    dns_cache_config {
      enabled = true
    }

    # GKE-managed GCS FUSE CSI driver (if needed for storage)
    gcs_fuse_csi_driver_config {
      enabled = false
    }
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "DEPLOYMENT", "POD", "DAEMONSET", "STATEFULSET"]

    managed_prometheus {
      enabled = true
    }
  }

  # Maintenance window - Sunday 2:00 AM UTC
  maintenance_policy {
    daily_maintenance_window {
      start_time = "02:00"
    }
  }

  # Security configuration
  # Binary Authorization can be enabled for production
  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  # Disable deletion protection for demo environments (Google provider v6+ defaults to true)
  deletion_protection = var.deletion_protection

  # Resource labels
  resource_labels = merge(var.labels, {
    environment = "demo"
    terraform   = "true"
  })

  # Ignore node pool changes since we manage them in Layer 3
  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_config,
    ]
  }
}

#####################
# Workload Identity - GCP Service Accounts
#####################

# Service account for ExternalDNS (Cloud DNS access)
resource "google_service_account" "external_dns" {
  account_id   = "${var.cluster_name}-ext-dns"
  project      = var.project
  display_name = "ExternalDNS for ${var.cluster_name}"
  description  = "Workload Identity SA for ExternalDNS to manage Cloud DNS records"
}

# Grant Cloud DNS admin to ExternalDNS service account
resource "google_project_iam_member" "external_dns" {
  project = var.project
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

# Workload Identity binding for ExternalDNS
# Allows the Kubernetes service account to impersonate the GCP service account
resource "google_service_account_iam_member" "external_dns_wi" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[kube-system/external-dns]"
}

# Service account for Gateway API / GCE Ingress Controller
# Note: GKE automatically configures the GCE ingress controller.
# This SA is for additional Gateway API resources that need LB management.
resource "google_service_account" "gateway_controller" {
  account_id   = "${var.cluster_name}-gw-ctrl"
  project      = var.project
  display_name = "Gateway Controller for ${var.cluster_name}"
  description  = "Workload Identity SA for Gateway API controller"
}

resource "google_project_iam_member" "gateway_controller_lb" {
  project = var.project
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.gateway_controller.email}"
}

resource "google_project_iam_member" "gateway_controller_network" {
  project = var.project
  role    = "roles/compute.networkUser"
  member  = "serviceAccount:${google_service_account.gateway_controller.email}"
}

resource "google_service_account_iam_member" "gateway_controller_wi" {
  service_account_id = google_service_account.gateway_controller.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[kube-system/gateway-controller]"
}

#####################
# Aviatrix Controller Onboarding
#####################
# Register the GKE cluster with Aviatrix Controller for Smart Groups
# This allows the controller to build workload-based security policies

# resource "aviatrix_kubernetes_cluster" "this" {
#   count = var.enable_aviatrix_onboarding ? 1 : 0
# 
#   cluster_id          = google_container_cluster.this.id
#   use_csp_credentials = true
# 
#   depends_on = [google_container_cluster.this]
# }

# ClusterRole for viewing nodes (required by Aviatrix for Smart Groups)
# GKE's default view ClusterRole doesn't include nodes
resource "kubernetes_cluster_role" "view_nodes" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  metadata {
    name = "view-nodes"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["nodes"]
  }

  depends_on = [google_container_cluster.this]
}

# ClusterRoleBinding to grant the Aviatrix service account the view-nodes ClusterRole
resource "kubernetes_cluster_role_binding" "view_nodes" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  metadata {
    name = "view-nodes"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.view_nodes[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "view-nodes"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [kubernetes_cluster_role.view_nodes]
}
