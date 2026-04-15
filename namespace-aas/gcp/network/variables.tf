#####################
# Pattern B: Namespace-as-a-Service — GCP Network Variables
#
# Single shared GKE cluster. All teams share one VPC and one spoke gateway.
# Isolation is enforced by DCF SmartGroups keyed on k8s_namespace.
#####################

variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same project)"
  type        = string
  default     = "naas"
}

variable "aviatrix_gcp_account_name" {
  description = "GCP account name as registered in Aviatrix Controller"
  type        = string
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "env" {
  description = "Environment name (e.g. prod, staging)"
  type        = string
  default     = "prod"
}

#####################
# CIDRs
#####################

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VPC"
  type        = string
  default     = "10.38.0.0/20"
}

variable "shared_vpc_cidr" {
  description = "Primary CIDR for the shared cluster VPC (all teams share this single VPC)"
  type        = string
  default     = "10.40.0.0/16"
}

variable "pod_cidr" {
  description = "Secondary range for pod networking (VPC-native alias IP ranges, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for Kubernetes services"
  type        = string
  default     = "172.40.0.0/20"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE private cluster master endpoint. Must be /28."
  type        = string
  default     = "172.16.0.0/28"
}

#####################
# DNS
#####################

variable "dns_private_zone_name" {
  description = "Cloud DNS private zone domain name"
  type        = string
  default     = "gcp-naas.aviatrixdemo.local"
}

#####################
# DCF
#####################

variable "k8s_cluster_name" {
  description = "Name of the shared GKE cluster (used in SmartGroup k8s_cluster_id)"
  type        = string
  default     = "naas-shared-gke"
}

variable "team_namespaces" {
  description = "List of team namespace names for SmartGroup creation"
  type        = list(string)
  default     = ["team-a", "team-b", "team-c"]
}

variable "geo_block_countries" {
  description = "ISO country codes to geo-block"
  type        = list(string)
  default     = ["CN", "RU", "KP", "IR"]
}

variable "approved_web_domains" {
  description = "Domains permitted for namespace egress via WebGroups"
  type        = list(string)
  default = [
    "*.googleapis.com",
    "registry.npmjs.org",
    "pypi.org",
    "ghcr.io",
  ]
}

variable "name_suffix" {
  description = "Optional suffix appended to all resource names for uniqueness (e.g., 'ab12')"
  type        = string
  default     = ""
}

variable "disable_dcf_on_destroy" {
  description = "Whether to disable DCF globally when this pattern is destroyed. Default false — DCF stays enabled."
  type        = bool
  default     = false
}
