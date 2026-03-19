###############################################################################
# Root Module -- Main Entry Point
#
# Wires together child modules:
#   - networking  : VNet + private-endpoint subnet
#   - monitoring  : Log Analytics Workspace
#   - storage     : Storage Account (fully private)
#   - front_door  : Azure Front Door Premium profile + WAF policy
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

  # Canonical resource names (CAF-compliant prefixes).
  names = {
    vnet                    = "vnet-${local.resource_prefix}"
    private_endpoint_subnet = "snet-pe-${local.resource_prefix}"
    nsg                     = "nsg-pe-${local.resource_prefix}"
    storage_account         = local.storage_account_name
    log_analytics_workspace = "law-${local.resource_prefix}"
    private_dns_zone        = "privatelink.blob.core.windows.net"
    private_endpoint        = "pe-${local.resource_prefix}-blob"

    # Azure Front Door + WAF names (CAF-compliant).
    afd_profile      = "afd-${local.resource_prefix}"
    afd_endpoint     = "afdep-${local.resource_prefix}"
    afd_origin_group = "og-${local.resource_prefix}"
    afd_origin       = "origin-${local.resource_prefix}"
    # WAF policy names cannot contain hyphens (Azure restriction); strip them.
    waf_policy = lower(replace("waf${var.workload_name}${var.environment_name}", "-", ""))
  }

  # Tags applied to every resource.
  # Infrastructure-managed keys are in the second argument to merge(), ensuring
  # they take precedence over any matching keys supplied via var.tags.
  common_tags = merge(var.tags, {
    environment = var.environment_name
    workload    = var.workload_name
    location    = var.location
    managed_by  = "terraform"
    repository  = "Afd-Blob-Storage"
    owner       = var.owner_tag
  })
}

###############################################################################
# Resource Group — existing resource (not managed by Terraform)
# The resource group must be created prior to running this module.
###############################################################################

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

###############################################################################
# NSG Module
# Deploys a Network Security Group with zero-trust rules for the
# private-endpoint subnet. Must be deployed before the VNet so its
# resource ID can be associated with the subnet.
###############################################################################

module "nsg" {
  source = "./modules/nsg"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  name                = local.names.nsg
  tags                = local.common_tags
  enable_telemetry    = var.enable_telemetry
}

###############################################################################
# Networking Module
# Deploys the VNet and a dedicated subnet for private endpoints.
###############################################################################

module "networking" {
  source = "./modules/networking"

  resource_group_id              = data.azurerm_resource_group.this.id
  location                       = data.azurerm_resource_group.this.location
  name                           = local.names.vnet
  subnet_name                    = local.names.private_endpoint_subnet
  address_space                  = var.address_space
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix
  network_security_group_id      = module.nsg.nsg_id
  tags                           = local.common_tags
  enable_telemetry               = var.enable_telemetry
}

###############################################################################
# Monitoring Module
# Deploys a Log Analytics Workspace for centralised log collection.
###############################################################################

module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
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

  resource_group_name            = data.azurerm_resource_group.this.name
  location                       = data.azurerm_resource_group.this.location
  name                           = local.names.storage_account
  account_replication_type       = var.storage_account_replication_type
  tags                           = local.common_tags
  enable_telemetry               = var.enable_telemetry
  log_analytics_workspace_id     = module.monitoring.workspace_resource_id
  enable_front_door_health_probe = var.enable_front_door_health_probe
}

###############################################################################
# Private DNS Module
# Deploys a Private DNS Zone for blob storage and links it to the workload VNet
# so that private endpoint DNS queries resolve correctly inside the network.
###############################################################################

module "private_dns" {
  source = "./modules/private_dns"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  vnet_id             = module.networking.vnet_id
  workload_name       = var.workload_name
  environment_name    = var.environment_name
  tags                = local.common_tags
}

###############################################################################
# Private Endpoint Module
# Deploys a Private Endpoint that connects the storage account's blob service
# to the private-endpoint subnet and registers its IP in the Private DNS Zone.
###############################################################################

module "private_endpoint" {
  source = "./modules/private_endpoint"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  name                = local.names.private_endpoint
  subnet_resource_id  = module.networking.private_endpoint_subnet_id
  storage_account_id  = module.storage.storage_account_id
  private_dns_zone_id = module.private_dns.private_dns_zone_id
  tags                = local.common_tags
  enable_telemetry    = var.enable_telemetry
}

###############################################################################
# Front Door Module
# Deploys Azure Front Door Premium with WAF integration:
#   - AFD Premium profile + globally unique endpoint
#   - Origin Group with HTTPS health probes and load-balancing configuration
#   - Origin pointing to the storage blob service via Private Link
#     (requires manual approval in the Azure Portal after deployment)
#   - Route forwarding HTTPS traffic from the endpoint to the origin group
#   - WAF Firewall Policy (var.afd_waf_mode) with DRS 2.1 + Bot Manager 1.0
#   - Security Policy associating the WAF policy with the AFD endpoint
###############################################################################

module "front_door" {
  source = "./modules/front_door"

  resource_group_name            = data.azurerm_resource_group.this.name
  location                       = data.azurerm_resource_group.this.location
  afd_profile_name               = local.names.afd_profile
  endpoint_name                  = local.names.afd_endpoint
  origin_group_name              = local.names.afd_origin_group
  origin_name                    = local.names.afd_origin
  waf_policy_name                = local.names.waf_policy
  storage_account_name           = module.storage.storage_account_name
  storage_account_id             = module.storage.storage_account_id
  waf_mode                       = var.afd_waf_mode
  custom_domain_host_name        = var.afd_custom_domain_host_name
  log_analytics_workspace_id     = module.monitoring.workspace_resource_id
  enable_front_door_health_probe = var.enable_front_door_health_probe
  tags                           = local.common_tags

  # Ensure the storage account is fully configured before AFD attempts to
  # establish the Private Link connection.
  depends_on = [module.storage]
}
