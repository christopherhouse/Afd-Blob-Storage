###############################################################################
# Storage Module – Main
#
# Deploys an Azure Storage Account configured for maximum security:
#   - Public network access disabled
#   - Shared-key (SAS) access disabled; Azure AD authentication only
#   - No public blob access
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

  # Prevent anonymous public access to blobs and containers.
  allow_nested_items_to_be_public = false

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

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
