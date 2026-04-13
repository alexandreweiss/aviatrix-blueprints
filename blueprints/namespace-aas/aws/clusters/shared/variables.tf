variable "kubernetes_version" {
  description = "Kubernetes version for the shared EKS cluster"
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_public_access" {
  description = "Whether to enable public access to the EKS API endpoint"
  type        = bool
  default     = true
}
