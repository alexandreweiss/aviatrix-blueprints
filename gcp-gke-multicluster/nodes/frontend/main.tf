terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
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

provider "google" {
  project = local.gcp_project
  region  = local.gcp_region
}

locals {
  gcp_project = data.terraform_remote_state.network.outputs.gcp_project
  gcp_region  = data.terraform_remote_state.network.outputs.gcp_region
}

# Kubernetes provider for Kubernetes resources
# By Layer 3, the cluster exists and can authenticate
provider "kubernetes" {
  host                   = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

# Helm provider for Kubernetes add-ons
# Uses the same authentication as the Kubernetes provider
provider "helm" {
  kubernetes {
    host                   = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

#####################
# Aviatrix Distributed Cloud Firewall (DCF) for Kubernetes
#####################

# Install the k8s-firewall Helm chart which provides CRDs for:
# - firewallpolicies.networking.aviatrix.com
# - webgrouppolicies.networking.aviatrix.com
# These enable Kubernetes-native firewall policy management via Aviatrix DCF
resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"

  # Skip waiting for resources - CRDs don't have traditional ready status
  wait = false

  # Recreate pods on upgrade to pick up new CRD versions
  recreate_pods = false
}

#####################
# Frontend GKE Node Pool
#####################

# This deployment runs AFTER frontend-cluster exists
# All values from the cluster state are known at plan time
# NOTE: GKE does not require ENIConfig (unlike EKS). VPC-native networking
# with alias IP ranges handles pod IP assignment automatically via secondary ranges.

module "default_node_pool" {
  source = "../../modules/gke-node-pool"

  # Cluster identity - from cluster state (exists at plan time)
  cluster_name = data.terraform_remote_state.cluster.outputs.cluster_name
  project      = local.gcp_project
  location     = data.terraform_remote_state.cluster.outputs.cluster_location

  # Scaling configuration - from variables (known at plan time)
  node_pool_name     = "default"
  min_node_count     = var.node_pool_config.min_node_count
  max_node_count     = var.node_pool_config.max_node_count
  initial_node_count = var.node_pool_config.initial_node_count

  # Instance configuration - from variables (known at plan time)
  machine_type = var.node_pool_config.machine_type
  spot         = var.node_pool_config.spot

  labels = {
    environment = "demo"
    cluster     = "frontend"
  }
}
