###############################################################################
# Networking Module -- Main
#
# Deploys an Azure Virtual Network with a single dedicated subnet for private
# endpoints. The private-endpoint subnet has an NSG associated and network
# policies set to NetworkSecurityGroupEnabled for zero-trust enforcement.
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
  # NSG is associated and network policies are set to NetworkSecurityGroupEnabled
  # so NSG rules are enforced on private endpoint traffic (zero-trust posture).
  subnets = {
    private_endpoints = {
      name             = var.subnet_name
      address_prefixes = [var.private_endpoint_subnet_prefix]

      # Enable NSG-only network policies so zero-trust NSG rules apply to
      # private endpoint traffic while route table policies remain disabled.
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled"

      network_security_group = {
        id = var.network_security_group_id
      }
    }
  }

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
