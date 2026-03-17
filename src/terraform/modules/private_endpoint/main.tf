###############################################################################
# Private Endpoint Module -- Main
#
# Deploys an Azure Private Endpoint that connects the storage account's blob
# service to the private-endpoint subnet, making the storage account
# accessible only via private IP within the VNet. Also configures a DNS zone
# group so that the Private DNS Zone A-record is managed automatically.
#
# AVM Used: Azure/avm-res-network-privateendpoint/azurerm @ 0.2.0
# Registry: https://registry.terraform.io/modules/Azure/avm-res-network-privateendpoint/azurerm/0.2.0
###############################################################################

###############################################################################
# Private Endpoint
###############################################################################

module "private_endpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"

  # --- Identity & Placement ---
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # --- Connectivity ---
  # The subnet into which the private endpoint NIC will be placed.
  subnet_resource_id = var.subnet_resource_id

  # Custom NIC name derived from the private endpoint name.
  network_interface_name = "nic-${var.name}"

  # The storage account to connect; "blob" targets the Blob service sub-resource.
  private_connection_resource_id  = var.storage_account_id
  subresource_names               = ["blob"]
  private_service_connection_name = var.name

  # --- DNS Zone Group ---
  # Automatically registers and removes an A-record in the linked Private DNS
  # Zone when the private endpoint is created or destroyed.
  private_dns_zone_group_name   = "blob-zone-group"
  private_dns_zone_resource_ids = [var.private_dns_zone_id]

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
