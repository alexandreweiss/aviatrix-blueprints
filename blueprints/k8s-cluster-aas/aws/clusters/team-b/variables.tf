variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

# ──── Architecture Recommendation Toggles ────────────────────────────────────

variable "enable_private_endpoint" {
  description = <<-EOT
    Disable public access to the EKS API server endpoint (private-only).
    Requires VPN/bastion for kubectl access.
    Ref: https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html
  EOT
  type        = bool
  default     = false
}

variable "enable_control_plane_logging" {
  description = <<-EOT
    Enable EKS control plane logging (audit, api, authenticator, controllerManager, scheduler).
    Ref: https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
  EOT
  type        = bool
  default     = false
}
