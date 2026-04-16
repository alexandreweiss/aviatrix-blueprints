# -----------------------------------------------------------------------------
# Pattern C: AKS Non-Production Cluster — Data Sources
# -----------------------------------------------------------------------------

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}
