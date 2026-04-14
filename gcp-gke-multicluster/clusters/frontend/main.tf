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

provider "google" {
  project = local.gcp_project
  region  = local.gcp_region
}

provider "google-beta" {
  project = local.gcp_project
  region  = local.gcp_region
}

# Aviatrix provider - uses environment variables for authentication:
# AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD
provider "aviatrix" {
  skip_version_validation = true
}

locals {
  cluster_name = data.terraform_remote_state.network.outputs.frontend_cluster_name
  gcp_project  = data.terraform_remote_state.network.outputs.gcp_project
  gcp_region   = data.terraform_remote_state.network.outputs.gcp_region
}

# Kubernetes provider - connects to GKE cluster using gcloud exec auth
# This allows Terraform to manage Kubernetes resources without requiring kubectl to be pre-configured
provider "kubernetes" {
  host                   = "https://${module.frontend_gke.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.frontend_gke.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

#####################
# Frontend GKE Cluster (Control Plane Only)
#####################

module "frontend_gke" {
  source = "../../modules/gke-cluster"

  cluster_name = local.cluster_name
  project      = local.gcp_project
  region       = local.gcp_region

  # Network configuration from Layer 1
  network              = data.terraform_remote_state.network.outputs.frontend_network_name
  subnetwork           = data.terraform_remote_state.network.outputs.frontend_gke_nodes_subnet_name
  pod_range_name       = data.terraform_remote_state.network.outputs.frontend_pod_range_name
  services_range_name  = data.terraform_remote_state.network.outputs.frontend_services_range_name
  master_ipv4_cidr_block = data.terraform_remote_state.network.outputs.master_ipv4_cidr_block

  # Cloud DNS configuration for ExternalDNS
  dns_zone_name     = data.terraform_remote_state.network.outputs.dns_zone_name
  dns_zone_dns_name = data.terraform_remote_state.network.outputs.dns_zone_dns_name

  # Aviatrix Controller onboarding
  enable_aviatrix_onboarding = true

  # Release channel
  release_channel = var.release_channel

  # Master authorized networks
  master_authorized_networks = var.master_authorized_networks

  labels = {
    environment = "demo"
    cluster     = "frontend"
  }
}
