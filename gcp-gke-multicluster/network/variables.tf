variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same project)"
  type        = string
  default     = "k8s-demo"
}

variable "aviatrix_gcp_account_name" {
  description = "GCP account name as registered in Aviatrix Controller"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "dns_private_zone_name" {
  description = "Cloud DNS private zone name for internal DNS"
  type        = string
  default     = "gcp.aviatrixdemo.local"
}

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VPC"
  type        = string
  default     = "10.42.0.0/20"
}

variable "frontend_vpc_cidr" {
  description = "Primary CIDR for the frontend GKE VPC"
  type        = string
  default     = "10.40.0.0/20"
}

variable "backend_vpc_cidr" {
  description = "Primary CIDR for the backend GKE VPC"
  type        = string
  default     = "10.41.0.0/20"
}

variable "db_vpc_cidr" {
  description = "CIDR for the database spoke VPC"
  type        = string
  default     = "10.45.0.0/22"
}

variable "pod_cidr" {
  description = "Secondary range for pod networking (overlapping across VPCs, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for Kubernetes services"
  type        = string
  default     = "172.40.0.0/20"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE private cluster master endpoint (frontend). Must be /28."
  type        = string
  default     = "172.16.0.0/28"
}

variable "backend_master_ipv4_cidr_block" {
  description = "CIDR block for GKE private cluster master endpoint (backend). Must be /28 and unique from frontend."
  type        = string
  default     = "172.16.0.16/28"
}
