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
# GCP VPC Network
#####################

resource "google_compute_network" "this" {
  name                    = var.name
  project                 = var.project
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

#####################
# Aviatrix Gateway Subnet
#####################

# Small /28 subnet for Aviatrix Spoke Gateway (16 IPs)
resource "google_compute_subnetwork" "avx_gateway" {
  name          = "${var.name}-avx-gw"
  project       = var.project
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = cidrsubnet(var.primary_cidr, 8, 0) # /28 from primary CIDR
}

#####################
# GKE Node Subnet
#####################

# /22 subnet for GKE nodes with secondary ranges for pods and services
# GKE uses VPC-native (alias IP ranges) instead of AWS's ENIConfig approach.
# The secondary ranges are non-routable and can overlap across VPCs,
# just like the secondary CIDR pattern in the EKS blueprint.
resource "google_compute_subnetwork" "gke_nodes" {
  name          = "${var.name}-gke-nodes"
  project       = var.project
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = cidrsubnet(var.primary_cidr, 2, 1) # /22 from primary CIDR

  # Pod secondary range - non-routable, overlapping across VPCs (same as EKS secondary CIDR)
  secondary_ip_range {
    range_name    = var.pod_range_name
    ip_cidr_range = var.pod_cidr
  }

  # Services secondary range
  secondary_ip_range {
    range_name    = var.services_range_name
    ip_cidr_range = var.services_cidr
  }

  # Enable private Google access so nodes without external IPs can reach Google APIs
  private_ip_google_access = true
}

#####################
# Cloud Router + NAT
#####################

# Cloud Router for NAT gateway (required for private GKE nodes to reach internet)
resource "google_compute_router" "this" {
  name    = "${var.name}-router"
  project = var.project
  network = google_compute_network.this.id
  region  = var.region
}

# Cloud NAT provides outbound internet for private GKE nodes
# In production, Aviatrix spoke gateway handles egress via SNAT policies.
# Cloud NAT serves as a fallback for bootstrap traffic before Aviatrix routes propagate.
resource "google_compute_router_nat" "this" {
  name    = "${var.name}-nat"
  project = var.project
  router  = google_compute_router.this.name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke_nodes.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

#####################
# Firewall Rules
#####################

# Allow internal communication within the VPC
resource "google_compute_firewall" "internal" {
  name    = "${var.name}-allow-internal"
  project = var.project
  network = google_compute_network.this.id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.primary_cidr,
    var.pod_cidr,
    var.services_cidr,
  ]
}

# Allow GKE master to reach nodes (webhooks, kubelet, etc.)
resource "google_compute_firewall" "gke_master" {
  name    = "${var.name}-allow-gke-master"
  project = var.project
  network = google_compute_network.this.id

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "10250", "9443"]
  }

  # GKE master CIDR (private cluster)
  source_ranges = [var.master_ipv4_cidr_block]
}
