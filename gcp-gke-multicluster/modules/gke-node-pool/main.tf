terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

#####################
# GKE Node Pool
#####################

# This module is deployed AFTER the cluster exists (Layer 3), solving the
# chicken-and-egg problem where node pool count/for_each depends on
# cluster outputs that don't exist during initial plan.

resource "google_container_node_pool" "this" {
  name     = "${var.cluster_name}-${var.node_pool_name}"
  project  = var.project
  location = var.location
  cluster  = var.cluster_name

  # Autoscaling configuration
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  initial_node_count = var.initial_node_count

  # Node configuration
  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type

    # Preemptible / Spot VMs for cost savings (use ON_DEMAND for production)
    preemptible = var.preemptible
    spot        = var.spot

    # OAuth scopes - minimal scopes, rely on Workload Identity for app-level access
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity metadata configuration
    # GKE_METADATA enables the metadata server proxy for Workload Identity
    # This is the GKE equivalent of AWS IRSA - pods authenticate as GCP service accounts
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Kubernetes labels applied to all nodes in this pool
    labels = merge(var.labels, {
      node-pool = var.node_pool_name
    })

    # Kubernetes taints
    dynamic "taint" {
      for_each = var.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # Shielded instance configuration (security hardening)
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = var.network_tags
  }

  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = var.max_surge
    max_unavailable = var.max_unavailable
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}
