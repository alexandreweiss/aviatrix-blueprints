variable "cluster_name" {
  description = "Name of the GKE cluster to attach node pool to"
  type        = string
}

variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "location" {
  description = "GKE cluster location (region or zone)"
  type        = string
}

variable "node_pool_name" {
  description = "Name suffix for the node pool"
  type        = string
  default     = "default"
}

variable "min_node_count" {
  description = "Minimum number of nodes per zone"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes per zone"
  type        = number
  default     = 3
}

variable "initial_node_count" {
  description = "Initial number of nodes per zone"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "GCE machine type for nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "disk_size_gb" {
  description = "Disk size in GB for each node"
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "Disk type for nodes (pd-standard, pd-ssd, pd-balanced)"
  type        = string
  default     = "pd-balanced"
}

variable "preemptible" {
  description = "Use preemptible VMs (legacy, prefer spot)"
  type        = bool
  default     = false
}

variable "spot" {
  description = "Use Spot VMs for cost savings (use false for production)"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Kubernetes labels to apply to nodes"
  type        = map(string)
  default     = {}
}

variable "taints" {
  description = "Kubernetes taints to apply to nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "network_tags" {
  description = "GCP network tags for firewall rules"
  type        = list(string)
  default     = []
}

variable "max_surge" {
  description = "Maximum number of nodes that can be created beyond desired during upgrades"
  type        = number
  default     = 1
}

variable "max_unavailable" {
  description = "Maximum number of nodes that can be unavailable during upgrades"
  type        = number
  default     = 0
}
