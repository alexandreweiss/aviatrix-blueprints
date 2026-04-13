#####################
# Distributed Cloud Firewall (DCF) Policies
#
# This file defines SmartGroups, WebGroups, and DCF Rulesets for the K8s multi-cloud demo.
#
# Architecture:
#   - Frontend VNet (10.30.0.0/20) - frontend-cluster AKS
#   - Backend VNet (10.31.0.0/20) - backend-cluster AKS
#   - Database VNet (10.35.0.0/22) - Database VM with direct A record
#   - Pod CIDR (100.64.0.0/16) - Shared across both clusters, SNAT'd to spoke gateway IPs
#
# Policy Structure:
#   1. Threat Prevention (GeoBlock, ThreatIQ) - Priority 0-9
#   2. Inter-VNet East-West traffic - Priority 10-29
#   3. Egress with WebGroups (DPI) - Priority 30-49
#
# IMPORTANT LESSONS LEARNED:
#   - DCF sees POST-SNAT traffic (spoke gateway IPs), not pod IPs
#   - Use VPC type SmartGroups for source matching (match by VNet/VPC name)
#   - Use Hostname SmartGroups for service destinations (FQDN pointing to internal LB)
#   - Default deny with dst=0.0.0.0/0 blocks inter-VNet traffic - DO NOT USE
#
# NOTE: K8s CRD-based policies (FirewallPolicy, WebGroupPolicy) can be applied
# directly in-cluster for namespace-level controls. See k8s-apps/dcf-crd/ for examples.
#####################

#####################
# Enable Distributed Cloud Firewall
#####################

resource "aviatrix_distributed_firewalling_config" "main" {
  enable_distributed_firewalling = true
}

# Enable DCF Enforcement on Kubernetes
resource "aviatrix_k8s_config" "main" {
  depends_on          = [aviatrix_distributed_firewalling_config.main]
  enable_k8s          = true
  enable_dcf_policies = true
}

# DCF enablement is async — controller needs time to activate
resource "time_sleep" "wait_for_dcf" {
  depends_on      = [aviatrix_distributed_firewalling_config.main]
  create_duration = "15s"
}

#####################
# SmartGroups - VPC Based (Infrastructure)
# Match by VPC/VNet name for source traffic identification
#####################

resource "aviatrix_smart_group" "frontend_vpc" {
  name = "sg-frontend-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "frontend-vnet"
    }
  }
}

resource "aviatrix_smart_group" "backend_vpc" {
  name = "sg-backend-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "backend-vnet"
    }
  }
}

resource "aviatrix_smart_group" "db_vpc" {
  name = "sg-db-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-db-spoke"
    }
  }
}

resource "aviatrix_smart_group" "all_aks_clusters" {
  name = "sg-all-aks-clusters"
  selector {
    match_expressions {
      type = "vpc"
      name = "frontend-vnet"
    }
    match_expressions {
      type = "vpc"
      name = "backend-vnet"
    }
  }
}

#####################
# SmartGroups - Hostname Based (Service Endpoints)
# Match by DNS hostname for service-level destination targeting
#####################

resource "aviatrix_smart_group" "backend_service" {
  name = "sg-backend-service"
  selector {
    match_expressions {
      fqdn = "backend.${var.private_dns_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "frontend_service" {
  name = "sg-frontend-service"
  selector {
    match_expressions {
      fqdn = "frontend.${var.private_dns_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "database" {
  name = "sg-database"
  selector {
    match_expressions {
      fqdn = "db.${var.private_dns_zone_name}"
    }
  }
}

#####################
# SmartGroups - External Feeds (Threats)
#####################

resource "aviatrix_smart_group" "geo_blocked" {
  name = "sg-geo-blocked"
  selector {
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "IR"
      }
    }
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "KP"
      }
    }
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "RU"
      }
    }
  }
}

resource "aviatrix_smart_group" "threat_intel" {
  name = "sg-threat-intel"
  selector {
    match_expressions {
      external = "threatiq"
      ext_args = {
        severity = "major"
      }
    }
    match_expressions {
      external = "threatiq"
      ext_args = {
        severity = "critical"
      }
    }
  }
}

#####################
# Built-in SmartGroups
# These are system-defined SmartGroups provided by Aviatrix
#####################

locals {
  # Built-in "Public Internet" SmartGroup UUID
  # This is a system-defined SmartGroup that matches all public (non-RFC1918) IPs
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups - Allowed Egress (SNI Filter)
#####################

resource "aviatrix_web_group" "kubernetes_io" {
  name = "wg-kubernetes-io"
  selector {
    match_expressions {
      snifilter = "kubernetes.io"
    }
  }
}

resource "aviatrix_web_group" "npm_registry" {
  name = "wg-npm-registry"
  selector {
    match_expressions {
      snifilter = "registry.npmjs.org"
    }
    match_expressions {
      snifilter = "npmjs.org"
    }
    match_expressions {
      snifilter = "www.npmjs.com"
    }
  }
}

#####################
# WebGroups - Allowed Egress (URL Path Filter)
# Demonstrates granular URL-based filtering within allowed domain
#####################

resource "aviatrix_web_group" "github_aviatrix" {
  name = "wg-github-aviatrix"
  selector {
    match_expressions {
      urlfilter = "github.com/AviatrixSystems/terraform-provider-aviatrix"
    }
    match_expressions {
      urlfilter = "github.com/AviatrixSystems/avxlabs-docs"
    }
  }
}

#####################
# WebGroups - AKS Required Services (Catch-all)
# These are required for AKS cluster operation
# Reference: https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress
#####################

resource "aviatrix_web_group" "aks_required" {
  name = "wg-aks-required"
  selector {
    ###################################
    # Microsoft Container Registry (MCR)
    # AKS pulls system images from MCR, not Docker Hub
    ###################################
    match_expressions {
      snifilter = "mcr.microsoft.com"
    }
    match_expressions {
      snifilter = "*.data.mcr.microsoft.com"
    }

    ###################################
    # Azure Resource Manager (ARM) APIs
    # Required for AKS control plane operations
    ###################################
    match_expressions {
      snifilter = "management.azure.com"
    }

    ###################################
    # Azure Active Directory / Entra ID
    # Required for authentication and token exchange
    ###################################
    match_expressions {
      snifilter = "login.microsoftonline.com"
    }
    match_expressions {
      snifilter = "login.microsoft.com"
    }
    match_expressions {
      snifilter = "sts.windows.net"
    }

    ###################################
    # Azure Monitor and Telemetry
    ###################################
    match_expressions {
      snifilter = "dc.services.visualstudio.com"
    }
    match_expressions {
      snifilter = "*.ods.opinsights.azure.com"
    }
    match_expressions {
      snifilter = "*.oms.opinsights.azure.com"
    }
    match_expressions {
      snifilter = "*.monitoring.azure.com"
    }

    ###################################
    # Azure Blob Storage
    # Required for VHDs, artifacts, and extensions
    ###################################
    match_expressions {
      snifilter = "*.blob.core.windows.net"
    }

    ###################################
    # AKS API Server
    # Private clusters use private endpoint, but FQDN still resolves
    ###################################
    match_expressions {
      snifilter = "*.hcp.*.azmk8s.io"
    }
    match_expressions {
      snifilter = "*.tun.*.azmk8s.io"
    }

    ###################################
    # Ubuntu/Azure Linux Package Repos
    # Required for node OS updates
    ###################################
    match_expressions {
      snifilter = "packages.microsoft.com"
    }
    match_expressions {
      snifilter = "security.ubuntu.com"
    }
    match_expressions {
      snifilter = "azure.archive.ubuntu.com"
    }
    match_expressions {
      snifilter = "changelogs.ubuntu.com"
    }

    ###################################
    # Microsoft Package Repository (PMC)
    ###################################
    match_expressions {
      snifilter = "pmc.edge.microsoft.com"
    }

    ###################################
    # Azure Policy and Governance
    ###################################
    match_expressions {
      snifilter = "data.policy.core.windows.net"
    }
    match_expressions {
      snifilter = "store.policy.core.windows.net"
    }

    ###################################
    # Kubernetes Registry
    ###################################
    match_expressions {
      snifilter = "registry.k8s.io"
    }
    match_expressions {
      snifilter = "*.pkg.dev"
    }

    ###################################
    # Azure DNS (for Private DNS resolution)
    ###################################
    match_expressions {
      snifilter = "*.privatelink.*.azmk8s.io"
    }
  }
}

#####################
# DCF Ruleset
#####################

data "aviatrix_dcf_attachment_point" "tf_before_ui" {
  name = "TERRAFORM_BEFORE_UI_MANAGED"
}

resource "aviatrix_dcf_ruleset" "k8s_demo" {
  depends_on = [time_sleep.wait_for_dcf]
  name       = "k8s-multicloud-demo"
  # TODO: revert to data source once Controller returns correct ID
  # attach_to = data.aviatrix_dcf_attachment_point.tf_before_ui.id
  attach_to = "defa11a1-3000-4001-0000-000000000000"

  #############################
  # THREAT PREVENTION (Priority 0-9)
  # Block malicious traffic before any permit rules
  #############################

  rules {
    name             = "Block GeoBlocked Countries"
    action           = "DENY"
    priority         = 0
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
  }

  rules {
    name             = "Block Threat Intel IPs"
    action           = "DENY"
    priority         = 1
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
  }

  #############################
  # INTER-VNET EAST-WEST (Priority 10-29)
  #
  # CRITICAL: DCF sees POST-SNAT traffic from pods
  # - Pod IP (100.64.x.x) is SNAT'd to spoke gateway IP (10.30.0.x or 10.31.0.x)
  # - Use VPC type SmartGroups for source matching
  # - Use Hostname SmartGroups for service destinations
  #############################

  rules {
    name             = "Frontend to Database"
    action           = "PERMIT"
    priority         = 10
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.frontend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.database.uuid]
    port_ranges {
      lo = 80
    }
  }

  rules {
    name             = "Backend to Database"
    action           = "PERMIT"
    priority         = 11
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.backend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.database.uuid]
    port_ranges {
      lo = 80
    }
  }

  # Inter-cluster monitoring (port 8080)
  # Frontend pods -> Backend services and vice versa
  rules {
    name             = "Frontend to Backend Services"
    action           = "PERMIT"
    priority         = 14
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.frontend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.backend_service.uuid]
    port_ranges {
      lo = 8080
    }
  }

  rules {
    name             = "Backend to Frontend Services"
    action           = "PERMIT"
    priority         = 15
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.backend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.frontend_service.uuid]
    port_ranges {
      lo = 8080
    }
  }

  #############################
  # EGRESS - AKS Required (Priority 20)
  # Allow AKS cluster operational traffic
  #############################

  rules {
    name                 = "AKS Required Azure Services"
    action               = "PERMIT"
    priority             = 20
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.aks_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # EGRESS - Allowed Destinations (Priority 30-49)
  # Explicit allow for specific external services
  #############################

  rules {
    name                 = "Allow kubernetes-io"
    action               = "PERMIT"
    priority             = 30
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.kubernetes_io.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Allow GitHub Aviatrix Repos"
    action               = "PERMIT"
    priority             = 31
    protocol             = "TCP"
    logging              = true
    watch                = true
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.github_aviatrix.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Allow npm Registry"
    action               = "PERMIT"
    priority             = 32
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.npm_registry.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # PLACEHOLDER FOR K8S CRD POLICIES (Priority 50-99)
  #
  # K8s CRD-based policies (FirewallPolicy, WebGroupPolicy) are applied
  # directly in the cluster and will be inserted at these priority levels.
  # See k8s-apps/dcf-crd/ for CRD examples.
  #
  # Example CRD use cases:
  #   - Namespace-specific egress rules (e.g., allow dev namespace to access test APIs)
  #   - Pod-label based policies (e.g., allow app=infosec pods to access virustotal.com)
  #   - Temporary rules for debugging/testing
  #############################

  #############################
  # DEFAULT DENY - INTENTIONALLY OMITTED
  #
  # DO NOT add a default deny rule with dst_smart_groups = public_internet (0.0.0.0/0)
  # because 0.0.0.0/0 matches ALL traffic including private RFC1918 addresses.
  # This would block inter-VNet traffic even with explicit permit rules above.
  #
  # If you need default deny for internet egress:
  #   1. Create a SmartGroup that excludes RFC1918 ranges
  #   2. Or use WebGroups with explicit deny for specific domains
  #   3. Or rely on Azure NSGs for internet egress control
  #############################
}

#####################
# Outputs
#####################

output "dcf_ruleset_uuid" {
  description = "UUID of the DCF ruleset"
  value       = aviatrix_dcf_ruleset.k8s_demo.id
}

output "smartgroup_frontend_vpc_uuid" {
  description = "UUID of frontend VNet SmartGroup"
  value       = aviatrix_smart_group.frontend_vpc.uuid
}

output "smartgroup_backend_vpc_uuid" {
  description = "UUID of backend VNet SmartGroup"
  value       = aviatrix_smart_group.backend_vpc.uuid
}

output "webgroup_github_aviatrix_uuid" {
  description = "UUID of GitHub Aviatrix WebGroup (for CRD reference)"
  value       = aviatrix_web_group.github_aviatrix.uuid
}
