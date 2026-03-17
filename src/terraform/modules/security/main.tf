###############################################################################
# Security Module -- Main
#
# Deploys an Azure Key Vault configured for enterprise security:
#   - Azure RBAC authorization (legacy access policies disabled)
#   - Soft-delete enabled (configurable retention, 7-90 days)
#   - Purge protection enabled (immutable once set)
#   - Public network access disabled
#   - Network ACLs default-deny; AzureServices bypass for trusted services
#
# AVM Used: Azure/avm-res-keyvault-vault/azurerm @ 0.10.2
# Registry: https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm/0.10.2
#
# NOTE: In this AVM, RBAC authorization is the default
# (legacy_access_policies_enabled defaults to false). No explicit
# enable_rbac_authorization variable is needed — simply leave
# legacy_access_policies_enabled at its default.
###############################################################################

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  # --- Identity & Placement ---
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # --- Azure AD Tenant ---
  tenant_id = var.tenant_id

  # --- SKU ---
  sku_name = var.sku_name

  # --- Security: Soft-Delete & Purge Protection ---
  # soft_delete_retention_days: number of days deleted items are recoverable.
  soft_delete_retention_days = var.soft_delete_retention_days

  # purge_protection_enabled: once enabled this cannot be reversed.
  # Prevents permanent deletion during the retention window.
  purge_protection_enabled = true

  # --- Security: Network Access ---
  # Disable all public network access; access must be via private endpoint.
  public_network_access_enabled = false

  # Network ACLs: default-deny with AzureServices bypass so that trusted
  # Azure platform services (e.g. Azure Backup, ARM) can reach the vault.
  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # --- RBAC Authorization ---
  # RBAC is enabled by default in this AVM (legacy_access_policies_enabled
  # defaults to false). Data-plane access is granted via Azure role assignments,
  # not vault access policies.

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
