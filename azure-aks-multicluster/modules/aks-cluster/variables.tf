variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group where the AKS cluster will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the AKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.30"
}

variable "aks_subnet_id" {
  description = "Subnet ID for AKS node pools"
  type        = string
}

variable "pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay (can overlap across clusters)"
  type        = string
  default     = "100.64.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must not overlap with VNet or pod CIDR)"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service (must be within service_cidr)"
  type        = string
  default     = "172.16.0.10"
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_count" {
  description = "Number of nodes in the system node pool"
  type        = number
  default     = 2
}

variable "authorized_ip_ranges" {
  description = "Authorized IP ranges for API server access (private cluster public FQDN)"
  type        = list(string)
  default     = []
}

variable "private_dns_zone_id" {
  description = "Azure Private DNS zone ID for ExternalDNS (empty string to skip)"
  type        = string
  default     = ""
}

variable "private_dns_zone_name" {
  description = "Azure Private DNS zone name for ExternalDNS"
  type        = string
  default     = ""
}

variable "private_dns_zone_resource_group_name" {
  description = "Resource group containing the Private DNS zone"
  type        = string
  default     = ""
}

variable "enable_aviatrix_onboarding" {
  description = "Whether to onboard the AKS cluster to Aviatrix Controller"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
