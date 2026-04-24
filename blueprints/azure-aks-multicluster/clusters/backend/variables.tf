variable "azure_region" {
  description = "Azure region in azurerm format (e.g., 'eastus2')"
  type        = string
  default     = "eastus2"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.32"
}

variable "node_pool_config" {
  description = "Configuration for the default system node pool"
  type = object({
    node_count = number
    min_count  = number
    max_count  = number
    vm_size    = string
  })
  default = {
    node_count = 2
    min_count  = 1
    max_count  = 3
    vm_size    = "Standard_D2s_v3"
  }
}

variable "authorized_ip_ranges" {
  description = <<-EOT
    IP ranges authorized to access the AKS API server.
    Add your current public IP (e.g., ["1.2.3.4/32"]).
    Use ["0.0.0.0/0"] to allow all (not recommended for production).
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
