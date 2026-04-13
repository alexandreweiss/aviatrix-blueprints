terraform {
  required_version = ">= 1.5"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "aviatrix" {
  skip_version_validation = true
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

locals {
  # Non-routable secondary range for pods - same across all VPCs (overlapping)
  pod_cidr      = var.pod_cidr
  services_cidr = var.services_cidr

  # Cluster configurations
  clusters = {
    frontend = {
      name         = "${var.name_prefix}-frontend"
      primary_cidr = var.frontend_vpc_cidr
    }
    backend = {
      name         = "${var.name_prefix}-backend"
      primary_cidr = var.backend_vpc_cidr
    }
  }
}

#####################
# Aviatrix Transit Gateway
#####################

module "gcp_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.0"

  name    = "${var.name_prefix}-transit"
  cloud   = "GCP"
  account = var.aviatrix_gcp_account_name
  region  = var.gcp_region
  cidr    = var.transit_cidr
  ha_gw   = false

  # Enable Transit FireNet for future NGFW integration
  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  instance_size     = "n1-standard-2"
  connected_transit = true

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Cloud DNS private zones)
  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This allows multiple spokes with the same secondary range (100.64.0.0/16)
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Frontend VPC and Spoke
#####################

module "frontend_vpc" {
  source = "./modules/gke-vpc"

  name    = "${var.name_prefix}-frontend"
  project = var.gcp_project
  region  = var.gcp_region

  primary_cidr           = local.clusters.frontend.primary_cidr
  pod_cidr               = local.pod_cidr
  services_cidr          = local.services_cidr
  master_ipv4_cidr_block = var.master_ipv4_cidr_block
}

module "frontend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "GCP"
  name       = "${var.name_prefix}-frontend-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = "n1-standard-2"
  ha_gw         = false

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Cloud DNS private zones)
  enable_vpc_dns_server = true

  # Use existing VPC created by gke-vpc module
  use_existing_vpc = true
  vpc_id           = "${module.frontend_vpc.network_name}~~${var.gcp_project}"
  gw_subnet        = module.frontend_vpc.avx_gateway_subnet_cidr
  hagw_subnet      = module.frontend_vpc.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
#
# IMPORTANT LESSONS LEARNED:
#   - GKE uses alias IP ranges (VPC-native) instead of AWS ENIConfig
#   - Pod traffic from alias IPs (100.64.x.x) is NOT routable across VPCs
#   - Aviatrix spoke gateway SNAT translates pod IPs to the gateway's routable IP
#   - DCF sees POST-SNAT traffic, so use VPC-type SmartGroups for source matching
resource "aviatrix_gateway_snat" "frontend_spoke_snat" {
  gw_name   = module.frontend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # SNAT for GKE node subnet to internet via eth0
  snat_policy {
    src_cidr   = module.frontend_vpc.gke_nodes_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.frontend_spoke]
}

#####################
# Backend VPC and Spoke
#####################

module "backend_vpc" {
  source = "./modules/gke-vpc"

  name    = "${var.name_prefix}-backend"
  project = var.gcp_project
  region  = var.gcp_region

  primary_cidr           = local.clusters.backend.primary_cidr
  pod_cidr               = local.pod_cidr
  services_cidr          = local.services_cidr
  master_ipv4_cidr_block = var.backend_master_ipv4_cidr_block
}

module "backend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "GCP"
  name       = "${var.name_prefix}-backend-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = "n1-standard-2"
  ha_gw         = false

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Cloud DNS private zones)
  enable_vpc_dns_server = true

  # Use existing VPC created by gke-vpc module
  use_existing_vpc = true
  vpc_id           = "${module.backend_vpc.network_name}~~${var.gcp_project}"
  gw_subnet        = module.backend_vpc.avx_gateway_subnet_cidr
  hagw_subnet      = module.backend_vpc.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
resource "aviatrix_gateway_snat" "backend_spoke_snat" {
  gw_name   = module.backend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  # SNAT for GKE node subnet to internet via eth0
  snat_policy {
    src_cidr   = module.backend_vpc.gke_nodes_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.backend_spoke]
}

#####################
# Database Spoke
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud          = "GCP"
  name           = "${var.name_prefix}-db-spoke"
  cidr           = var.db_vpc_cidr
  account        = var.aviatrix_gcp_account_name
  region         = var.gcp_region
  transit_gw     = module.gcp_transit.transit_gateway.gw_name
  instance_size  = "n1-standard-2"
  ha_gw          = false
  single_ip_snat = true

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Cloud DNS private zones)
  enable_vpc_dns_server = true
}

#####################
# Cloud DNS Private Zone
#####################

# Create private DNS zone - analogous to Route53 private hosted zone in EKS blueprint
resource "google_dns_managed_zone" "private" {
  name        = replace(var.dns_private_zone_name, ".", "-")
  project     = var.gcp_project
  dns_name    = "${var.dns_private_zone_name}."
  description = "Private DNS zone for GKE multi-cluster demo"
  visibility  = "private"

  private_visibility_config {
    # Associate with transit VPC
    networks {
      network_url = "projects/${var.gcp_project}/global/networks/${split("~~", module.gcp_transit.vpc.vpc_id)[0]}"
    }

    # Associate with frontend VPC
    networks {
      network_url = module.frontend_vpc.network_id
    }

    # Associate with backend VPC
    networks {
      network_url = module.backend_vpc.network_id
    }
  }

  labels = {
    environment = "demo"
    terraform   = "true"
  }
}

#####################
# Static DNS Records
#####################

# Database VM record (placeholder - update with actual DB IP)
resource "google_dns_record_set" "db" {
  name         = "db.${var.dns_private_zone_name}."
  project      = var.gcp_project
  managed_zone = google_dns_managed_zone.private.name
  type         = "A"
  ttl          = 300

  # Use the first private IP from the DB spoke's subnet
  # In production, replace with actual database VM IP
  rrdatas = [cidrhost(var.db_vpc_cidr, 10)]
}
