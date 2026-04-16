# -----------------------------------------------------------------------------
# Pattern C: EKS Production Cluster — Data Sources
# Read network layer outputs via remote state
# -----------------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../network/terraform.tfstate"
  }
}
