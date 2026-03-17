###############################################################################
# Private DNS Module -- Main
#
# Deploys an Azure Private DNS Zone for the blob storage private endpoint and
# links it to the workload VNet so that DNS queries for the private endpoint
# resolve correctly inside the virtual network.
#
# AVM Lookup: Azure/avm-res-network-privatednzone/azurerm
# Result: No AVM found in the Azure Verified Modules registry as of 2025-07.
# Falling back to native azurerm resources per project policy.
#
# Resources deployed:
#   - azurerm_private_dns_zone            : privatelink.blob.core.windows.net
#   - azurerm_private_dns_zone_virtual_network_link : VNet link (auto-reg off)
###############################################################################

###############################################################################
# Private DNS Zone
###############################################################################

# Fixed zone name required by Azure for blob storage private endpoints.
# DNS queries for <storage>.blob.core.windows.net resolve to the private IP
# inside the VNet via this zone.
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

###############################################################################
# VNet Link
###############################################################################

# Links the Private DNS Zone to the workload VNet so that resources inside
# the VNet use this zone for DNS resolution.
# registration_enabled = false because the Private Endpoint DNS zone group
# manages the A-records automatically; auto-registration is not needed.
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "pdnslink-${var.workload_name}-${var.environment_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = var.vnet_id

  # Auto-registration is disabled: private endpoint DNS zone groups inject
  # and remove A-records for the storage account private IPs automatically.
  registration_enabled = false

  tags = var.tags
}
