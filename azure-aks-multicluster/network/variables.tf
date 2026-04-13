variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same subscription)"
  type        = string
  default     = "k8s-demo"
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

variable "node_group_config" {
  description = "Configuration for AKS node pools"
  type = object({
    min_count  = number
    max_count  = number
    node_count = number
    vm_size    = string
    priority   = string
  })
  default = {
    min_count  = 1
    max_count  = 3
    node_count = 2
    vm_size    = "Standard_D4s_v3"
    priority   = "Spot"
  }
}

variable "private_dns_zone_name" {
  description = "Azure Private DNS zone name for internal DNS"
  type        = string
  default     = "azure.aviatrixdemo.local"
}

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VNet"
  type        = string
  default     = "10.32.0.0/20"
}

variable "frontend_vnet_cidr" {
  description = "Primary CIDR for the frontend AKS VNet"
  type        = string
  default     = "10.30.0.0/20"
}

variable "backend_vnet_cidr" {
  description = "Primary CIDR for the backend AKS VNet"
  type        = string
  default     = "10.31.0.0/20"
}

variable "db_vnet_cidr" {
  description = "CIDR for the database spoke VNet"
  type        = string
  default     = "10.35.0.0/22"
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod networking (overlapping across VNets, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

variable "db_private_ip" {
  description = "Private IP address of the database VM (for DNS record)"
  type        = string
  default     = "10.35.0.10"
}
