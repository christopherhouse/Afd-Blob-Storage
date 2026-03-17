###############################################################################
# Networking Module -- Main
#
# Deploys an Azure Virtual Network with a single dedicated subnet for private
# endpoints. The private-endpoint subnet has network policies disabled, which
# is required for private endpoint deployment.
#
# AVM Used: Azure/avm-res-network-virtualnetwork/azurerm @ 0.17.1
# Registry: https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/0.17.1
###############################################################################

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  # --- Identity & Placement ---
  # The VNet AVM uses parent_id (resource group resource ID) rather than
  # resource_group_name. Pass the resource group ID from the calling module.
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location

  # --- Addressing ---
  # address_space is set(string) in the AVM; convert from list(string) variable.
  address_space = toset(var.address_space)

  # --- Subnets ---
  # A single subnet dedicated to private endpoints.
  # private_endpoint_network_policies = "Disabled" is mandatory for private
  # endpoints to function correctly in this subnet.
  subnets = {
    private_endpoints = {
      name             = var.subnet_name
      address_prefixes = [var.private_endpoint_subnet_prefix]

      # Required: disable network policies so private endpoint NIC IPs can be
      # assigned and traffic can flow without being blocked by NSG/UDR policies.
      private_endpoint_network_policies = "Disabled"

      # Explicit opt-out of default outbound internet access (GA behaviour
      # as of 2024-09; disabling improves security posture).
      default_outbound_access_enabled = false
    }
  }

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
