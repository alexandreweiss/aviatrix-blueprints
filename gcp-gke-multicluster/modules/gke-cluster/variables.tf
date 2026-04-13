variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the cluster (regional cluster)"
  type        = string
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, or STABLE"
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "Release channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "network" {
  description = "VPC network name or self-link for the GKE cluster"
  type        = string
}

variable "subnetwork" {
  description = "Subnetwork name or self-link for GKE nodes"
  type        = string
}

variable "pod_range_name" {
  description = "Name of the secondary IP range for pods (defined on the subnetwork)"
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary IP range for services (defined on the subnetwork)"
  type        = string
  default     = "services"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the GKE master private endpoint. Must be /28."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "Must be a valid /28 CIDR block."
  }
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks authorized to access the GKE master endpoint"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All (restrict in production)"
    }
  ]
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container image validation"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Cloud DNS managed zone name for ExternalDNS"
  type        = string
  default     = ""
}

variable "dns_zone_dns_name" {
  description = "Cloud DNS zone DNS name (domain) for ExternalDNS"
  type        = string
  default     = ""
}

variable "enable_aviatrix_onboarding" {
  description = "Enable registration of the GKE cluster with Aviatrix Controller for Smart Groups"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the cluster. Set to false for demo/dev environments."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Resource labels for the GKE cluster"
  type        = map(string)
  default     = {}
}
