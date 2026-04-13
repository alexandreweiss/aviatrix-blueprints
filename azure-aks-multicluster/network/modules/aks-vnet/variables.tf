variable "name" {
  description = "Name prefix for all VNet resources"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "vnet_cidr" {
  description = "Primary CIDR block for the VNet (e.g., 10.30.0.0/20)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay (not a VNet subnet, configured at AKS level). Can overlap across VNets."
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "avx_gw_newbits" {
  description = "Number of additional bits for the Aviatrix gateway subnet (e.g., 8 on a /20 gives /28)"
  type        = number
  default     = 8
}

variable "aks_system_newbits" {
  description = "Number of additional bits for the AKS system subnet (e.g., 2 on a /20 gives /22)"
  type        = number
  default     = 2
}

variable "aks_system_netnum" {
  description = "Network number for the AKS system subnet within the VNet CIDR"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
