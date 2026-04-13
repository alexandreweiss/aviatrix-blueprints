variable "cluster_name" {
  description = "Name of the AKS cluster to attach the node pool to"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the AKS cluster"
  type        = string
}

variable "node_pool_name" {
  description = "Name of the node pool (max 12 chars, lowercase alphanumeric)"
  type        = string
  default     = "default"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.node_pool_name))
    error_message = "Node pool name must be 1-12 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "subnet_id" {
  description = "Subnet ID where nodes will be launched"
  type        = string
}

variable "vm_size" {
  description = "Azure VM size for the node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "auto_scaling_enabled" {
  description = "Enable cluster autoscaler for this node pool"
  type        = bool
  default     = true
}

variable "min_count" {
  description = "Minimum number of nodes (when autoscaling is enabled)"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum number of nodes (when autoscaling is enabled)"
  type        = number
  default     = 3
}

variable "node_count" {
  description = "Fixed number of nodes (when autoscaling is disabled)"
  type        = number
  default     = 2
}

variable "priority" {
  description = "Node pool priority: Regular or Spot"
  type        = string
  default     = "Spot"

  validation {
    condition     = contains(["Regular", "Spot"], var.priority)
    error_message = "Priority must be 'Regular' or 'Spot'."
  }
}

variable "spot_max_price" {
  description = "Maximum price for Spot VMs (-1 = on-demand price cap)"
  type        = number
  default     = -1
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 50
}

variable "os_disk_type" {
  description = "OS disk type: Managed or Ephemeral"
  type        = string
  default     = "Managed"
}

variable "max_surge" {
  description = "Max surge for node pool upgrades (count or percentage)"
  type        = string
  default     = "10%"
}

variable "node_labels" {
  description = "Kubernetes labels to apply to nodes"
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints to apply to nodes (e.g., ['dedicated=gpu:NoSchedule'])"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
