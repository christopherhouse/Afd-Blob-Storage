###############################################################################
# NSG Module Outputs
###############################################################################

output "nsg_id" {
  description = "Azure resource ID of the Network Security Group."
  value       = module.nsg.resource_id
}

output "nsg_name" {
  description = "Name of the Network Security Group."
  value       = module.nsg.name
}
