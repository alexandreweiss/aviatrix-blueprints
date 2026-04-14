# -----------------------------------------------------------------------------
# Pattern C: GKE Production Cluster — Data Sources
# -----------------------------------------------------------------------------

data "google_project" "current" {
  project_id = var.gcp_project_id
}

data "google_client_config" "current" {}

data "google_container_engine_versions" "available" {
  project  = var.gcp_project_id
  location = var.gcp_region
}
