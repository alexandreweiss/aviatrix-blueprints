variable "name" {
  description = "Short name for the VNet (e.g., 'frontend', 'backend')"
  type        = string
}

variable "cluster_name" {
  description = "Full AKS cluster name, used for resource tagging"
  type        = string
}

variable "vnet_cidr" {
  description = "Primary CIDR for the VNet. Pod CIDR is Cilium overlay and NOT added here."
  type        = string
}

variable "region" {
  description = "Azure region in azurerm format (e.g., 'eastus2')"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
