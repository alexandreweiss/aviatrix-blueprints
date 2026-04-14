variable "name" {
  description = "Name prefix for VPC resources"
  type        = string
}

variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "primary_cidr" {
  description = "Primary CIDR for infrastructure (e.g., 10.40.0.0/20)"
  type        = string

  validation {
    condition     = can(cidrhost(var.primary_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "pod_cidr" {
  description = "Secondary CIDR for pods (e.g., 100.64.0.0/16). Can overlap across VPCs."
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "services_cidr" {
  description = "Secondary CIDR for Kubernetes services (e.g., 172.40.0.0/20)"
  type        = string
  default     = "172.40.0.0/20"

  validation {
    condition     = can(cidrhost(var.services_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "pod_range_name" {
  description = "Name of the secondary IP range for pods"
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary IP range for services"
  type        = string
  default     = "services"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the GKE master (private cluster). Must be /28."
  type        = string
  default     = "172.16.0.0/28"
}
