###############################################################################
# Monitoring Module -- Main
#
# Deploys an Azure Log Analytics Workspace for centralised log ingestion and
# querying. Other modules can reference the workspace resource ID when
# configuring diagnostic settings.
#
# AVM Used: Azure/avm-res-operationalinsights-workspace/azurerm @ 0.5.1
# Registry: https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm/0.5.1
###############################################################################

module "log_analytics_workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  # --- Identity & Placement ---
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # --- Workspace Configuration ---
  log_analytics_workspace_sku               = var.sku
  log_analytics_workspace_retention_in_days = var.retention_in_days

  # --- Network Access ---
  # Allow public internet ingestion and query by default so that agents,
  # diagnostic settings, and portal users can reach the workspace without
  # requiring a private link. The AVM module defaults these to "false".
  log_analytics_workspace_internet_ingestion_enabled = var.internet_ingestion_enabled
  log_analytics_workspace_internet_query_enabled     = var.internet_query_enabled

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
