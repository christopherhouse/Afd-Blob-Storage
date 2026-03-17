###############################################################################
# Root Module – Main Entry Point
#
# Wires together child modules:
#   - networking  : VNet + private-endpoint subnet
#   - monitoring  : Log Analytics Workspace
#   - storage     : Storage Account (fully private)
#   - security    : Key Vault (RBAC-enabled, purge-protected)
#
# Resource names follow CAF conventions and are computed in locals below.
###############################################################################

###############################################################################
# Data Sources
###############################################################################

# Retrieve the current Azure subscription and tenant IDs automatically so
# they never need to be stored in variable files or CI secrets.
data "azurerm_client_config" "current" {}

###############################################################################
# Locals – Naming, Tagging, and Derived Configuration
###############################################################################

locals {
  # Short location codes used in storage-account names (alphanumeric only).
  # Extended with additional Azure regions; falls back to a truncated location
  # string for any region not listed here.
  location_short_map = {
    "australiacentral"   = "auc"
    "australiacentral2"  = "auc2"
    "australiaeast"      = "aue"
    "australiasoutheast" = "ause"
    "brazilsouth"        = "brs"
    "canadacentral"      = "cac"
    "canadaeast"         = "cae"
    "centralindia"       = "cin"
    "centralus"          = "cus"
    "eastasia"           = "ea"
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "francecentral"      = "frc"
    "germanywestcentral" = "gwc"
    "japaneast"          = "jpe"
    "japanwest"          = "jpw"
    "koreacentral"       = "krc"
    "northcentralus"     = "ncus"
    "northeurope"        = "neu"
    "norwayeast"         = "noe"
    "southafricanorth"   = "san"
    "southcentralus"     = "scus"
    "southeastasia"      = "sea"
    "southindia"         = "sin"
    "swedencentral"      = "swc"
    "switzerlandnorth"   = "swn"
    "uaenorth"           = "uan"
    "uksouth"            = "uks"
    "ukwest"             = "ukw"
    "westcentralus"      = "wcus"
    "westeurope"         = "weu"
    "westindia"          = "win"
    "westus"             = "wus"
    "westus2"            = "wus2"
    "westus3"            = "wus3"
  }

  location_short  = lookup(local.location_short_map, var.location, substr(var.location, 0, 5))
  resource_prefix = "${var.workload_name}-${var.environment_name}"

  # Storage account names: alphanumeric only, max 24 characters.
  # Pattern: st + workload + env + locationshort (hyphens stripped, lowercased).
  storage_account_name = lower(
    substr(
      "st${replace(var.workload_name, "-", "")}${replace(var.environment_name, "-", "")}${replace(local.location_short, "-", "")}",
      0,
      24
    )
  )

  # Key Vault names: alphanumeric + hyphens, max 24 characters.
  key_vault_name = "kv-${substr("${var.workload_name}-${var.environment_name}", 0, 21)}"

  # Canonical resource names (CAF-compliant prefixes).
  names = {
    resource_group          = "rg-${local.resource_prefix}"
    vnet                    = "vnet-${local.resource_prefix}"
    private_endpoint_subnet = "snet-pe-${local.resource_prefix}"
    storage_account         = local.storage_account_name
    log_analytics_workspace = "law-${local.resource_prefix}"
    key_vault               = local.key_vault_name
  }

  # Tags applied to every resource.
  common_tags = {
    environment = var.environment_name
    workload    = var.workload_name
    location    = var.location
    managed_by  = "terraform"
    repository  = "Afd-Blob-Storage"
    owner       = var.owner_tag
  }
}

###############################################################################
# Resource Group
###############################################################################

resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.common_tags
}

###############################################################################
# Networking Module
# Deploys the VNet and a dedicated subnet for private endpoints.
###############################################################################

module "networking" {
  source = "./modules/networking"

  resource_group_id              = azurerm_resource_group.this.id
  location                       = azurerm_resource_group.this.location
  name                           = local.names.vnet
  subnet_name                    = local.names.private_endpoint_subnet
  address_space                  = var.address_space
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix
  tags                           = local.common_tags
  enable_telemetry               = var.enable_telemetry
}

###############################################################################
# Monitoring Module
# Deploys a Log Analytics Workspace for centralised log collection.
###############################################################################

module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  name                = local.names.log_analytics_workspace
  sku                 = var.law_sku
  retention_in_days   = var.law_retention_days
  tags                = local.common_tags
  enable_telemetry    = var.enable_telemetry
}

###############################################################################
# Storage Module
# Deploys a fully-private Storage Account (no public access, no shared keys).
###############################################################################

module "storage" {
  source = "./modules/storage"

  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  name                     = local.names.storage_account
  account_replication_type = var.storage_account_replication_type
  tags                     = local.common_tags
  enable_telemetry         = var.enable_telemetry
}

###############################################################################
# Security Module
# Deploys a Key Vault with RBAC, purge protection, and no public network access.
###############################################################################

module "security" {
  source = "./modules/security"

  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  name                       = local.names.key_vault
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.kv_sku_name
  soft_delete_retention_days = var.kv_soft_delete_retention_days
  tags                       = local.common_tags
  enable_telemetry           = var.enable_telemetry
}
