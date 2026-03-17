###############################################################################
# Networking Module Outputs
###############################################################################

output "vnet_id" {
  description = "Azure resource ID of the virtual network."
  value       = module.vnet.resource_id
}

output "vnet_name" {
  description = "Name of the virtual network."
  # module.vnet.name is a dedicated non-sensitive output from the VNet AVM.
  value = module.vnet.name
}

output "private_endpoint_subnet_id" {
  description = "Azure resource ID of the private-endpoint subnet."
  value       = module.vnet.subnets["private_endpoints"].resource_id
}
