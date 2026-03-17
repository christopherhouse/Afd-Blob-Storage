###############################################################################
# Root Module Outputs
###############################################################################

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group containing all workload resources."
  value       = data.azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "Azure resource ID of the resource group."
  value       = data.azurerm_resource_group.this.id
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

output "vnet_id" {
  description = "Azure resource ID of the virtual network."
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = module.networking.vnet_name
}

output "private_endpoint_subnet_id" {
  description = "Azure resource ID of the private-endpoint subnet."
  value       = module.networking.private_endpoint_subnet_id
}

# ---------------------------------------------------------------------------
# Storage Account
# ---------------------------------------------------------------------------

output "storage_account_id" {
  description = "Azure resource ID of the storage account."
  value       = module.storage.storage_account_id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = module.storage.storage_account_name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint URL for the storage account."
  value       = module.storage.primary_blob_endpoint
}

# ---------------------------------------------------------------------------
# Log Analytics Workspace
# ---------------------------------------------------------------------------

output "log_analytics_workspace_resource_id" {
  description = "Azure resource ID of the Log Analytics Workspace."
  value       = module.monitoring.workspace_resource_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace customer ID (used for data ingestion / agent configuration)."
  # Marked sensitive because the underlying AVM resource output is sensitive.
  sensitive = true
  value     = module.monitoring.workspace_id
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

output "key_vault_id" {
  description = "Azure resource ID of the Key Vault."
  value       = module.security.key_vault_id
}

output "key_vault_uri" {
  description = "URI of the Key Vault (e.g. https://<name>.vault.azure.net/)."
  value       = module.security.key_vault_uri
}
