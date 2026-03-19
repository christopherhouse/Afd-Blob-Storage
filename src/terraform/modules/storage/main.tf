###############################################################################
# Storage Module -- Main
#
# Deploys an Azure Storage Account configured for maximum security:
#   - Public network access disabled
#   - Shared-key (SAS) access disabled; Azure AD authentication only
#   - Anonymous access allowed at account level only when health probe is enabled
#   - TLS 1.2 minimum; HTTPS-only traffic
#   - Network rules default-deny with no bypass (fully private)
#   - Conditionally creates a 'health' container with anonymous blob read access
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

  # Allow blob-level anonymous access at the account level only when the AFD
  # health probe is enabled.  This lets the 'health' container expose
  # /health/health.txt anonymously so AFD can probe origin health (AFD does not
  # support MI auth over Private Link).  When disabled, no anonymous access is
  # permitted.
  allow_nested_items_to_be_public = var.enable_front_door_health_probe

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
  # 'health'  : (conditional) when enable_front_door_health_probe is true, created
  #             with blob-level anonymous read access so AFD health probes can HEAD
  #             /health/health.txt without authentication (AFD does not support MI
  #             auth over Private Link).
  containers = merge(
    {
      upload = {
        name          = "upload"
        public_access = "None"
      }
    },
    var.enable_front_door_health_probe ? {
      health = {
        name          = "health"
        public_access = "Blob"
      }
    } : {}
  )

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
