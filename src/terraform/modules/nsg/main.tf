###############################################################################
# NSG Module -- Main
#
# Deploys a Network Security Group with zero-trust rules for the
# private-endpoint subnet. Only Azure Front Door backend HTTPS traffic
# is permitted inbound; all other inbound and outbound traffic is denied.
#
# AVM Used: Azure/avm-res-network-networksecuritygroup/azurerm
# Registry: https://registry.terraform.io/modules/Azure/avm-res-network-networksecuritygroup/azurerm
###############################################################################

module "nsg" {
  source = "git::https://github.com/Azure/terraform-azurerm-avm-res-network-networksecuritygroup.git?ref=68318782b31395de77e556fd3260d4a4036b0b93" # v0.4.0

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rules = {
    # ── Inbound Rules ─────────────────────────────────────────────────────
    allow_afd_inbound = {
      name                       = "AllowAzureFrontDoorInbound"
      description                = "Allow Azure Front Door backend traffic to private endpoints over HTTPS."
      access                     = "Allow"
      direction                  = "Inbound"
      priority                   = 100
      protocol                   = "Tcp"
      source_address_prefix      = "AzureFrontDoor.Backend"
      source_port_range          = "*"
      destination_address_prefix = "VirtualNetwork"
      destination_port_range     = "443"
    }

    deny_all_inbound = {
      name                       = "DenyAllInbound"
      description                = "Zero-trust: deny all other inbound traffic."
      access                     = "Deny"
      direction                  = "Inbound"
      priority                   = 4096
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_range     = "*"
    }

    # ── Outbound Rules ────────────────────────────────────────────────────
    deny_all_outbound = {
      name                       = "DenyAllOutbound"
      description                = "Zero-trust: deny all outbound traffic from the private-endpoint subnet."
      access                     = "Deny"
      direction                  = "Outbound"
      priority                   = 4096
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_range     = "*"
    }
  }

  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
