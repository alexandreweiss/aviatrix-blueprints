#####################
# Pattern B: Namespace-as-a-Service — Azure Network Variables
#
# Single shared AKS cluster. All teams share one VNet and one spoke gateway.
# Isolation is enforced by DCF SmartGroups keyed on k8s_namespace.
#####################

variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same subscription)"
  type        = string
  default     = "naas"
}

variable "aviatrix_azure_account_name" {
  description = "Azure account name as registered in Aviatrix Controller"
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription ID for the azurerm provider"
  type        = string
}

variable "azure_region" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US 2"
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
  description = "CIDR for the Aviatrix transit VNet"
  type        = string
  default     = "10.28.0.0/20"
}

variable "shared_vnet_cidr" {
  description = "CIDR for the shared cluster VNet (all teams share this single VNet)"
  type        = string
  default     = "10.30.0.0/16"
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod networking (Azure CNI Overlay, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

#####################
# DNS
#####################

variable "private_dns_zone_name" {
  description = "Azure Private DNS zone name for internal DNS"
  type        = string
  default     = "azure-naas.aviatrixdemo.local"
}

#####################
# DCF
#####################

variable "k8s_cluster_name" {
  description = "Name of the shared AKS cluster (used in SmartGroup k8s_cluster_id)"
  type        = string
  default     = "naas-shared-aks"
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
    "*.blob.core.windows.net",
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
