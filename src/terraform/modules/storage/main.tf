###############################################################################
# Storage Module -- Main
#
# Deploys an Azure Storage Account configured for maximum security:
#   - Public network access disabled
#   - Shared-key (SAS) access disabled; Azure AD authentication only
#   - Blob-level anonymous access enabled for the 'health' container only
#   - TLS 1.2 minimum; HTTPS-only traffic
#   - Network rules default-deny with no bypass (fully private)
#
# AVM Used: Azure/avm-res-storage-storageaccount/azurerm @ 0.6.7
# Registry: https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/0.6.7
#
# NOTE: Because shared_access_key_enabled = false, the azurerm provider must
# be configured with storage_use_azuread = true, or the Terraform identity
# must hold the "Storage Blob Data Contributor" role on the account to manage
# blob containers via Terraform.
###############################################################################

module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.7"

  # --- Identity & Placement ---
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # --- Account Configuration ---
  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type

  # --- Security: Access Control ---
  # Disable public network access entirely (belt-and-suspenders with network_rules).
  public_network_access_enabled = false

  # Disable shared-key / SAS authentication; enforce Azure AD-only access.
  shared_access_key_enabled = false

  # Allow blob-level anonymous access so that the 'health' container can serve
  # health.txt to the Azure Front Door health probe without credentials.
  # Anonymous access is restricted to the 'health' container via its
  # container_access_type = "blob" setting; the 'upload' container remains private.
  # Public network access is still disabled, so this only applies to traffic
  # arriving via the Private Link endpoint.
  allow_nested_items_to_be_public = true

  # --- Security: Encryption in Transit ---
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  # --- Network Rules ---
  # default_action = "Deny" with empty bypass blocks all public traffic.
  # Traffic must arrive via private endpoint.
  network_rules = {
    default_action = "Deny"
    bypass         = []
  }

  # --- Blob Containers ---
  # 'upload'  : private — content is accessible via authenticated requests only.
  # 'health'  : blob-level anonymous read access so that the Azure Front Door
  #             health probe can GET health/health.txt through the Private Link
  #             endpoint without credentials.
  # The map key is used as the resource identifier; the name field sets the
  # actual container name in the storage account.
  containers = {
    upload = {
      name                  = "upload"
      container_access_type = "private"
    }
    health = {
      name                  = "health"
      container_access_type = "blob"
    }
  }

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}

###############################################################################
# Blob Diagnostic Setting (optional)
#
# Routes StorageRead / StorageWrite / StorageDelete logs and the Transaction
# metric from the blob service to a Log Analytics Workspace.
# Only created when var.log_analytics_workspace_id is non-empty, so callers
# that have not yet provisioned a workspace can skip diagnostics safely.
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace_id != "" ? 1 : 0

  name               = "diag-blob-${var.name}"
  target_resource_id = "${module.storage_account.resource_id}/blobServices/default"

  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}
