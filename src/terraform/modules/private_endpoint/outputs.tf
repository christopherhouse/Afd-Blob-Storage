###############################################################################
# Private Endpoint Module Outputs
###############################################################################

output "private_endpoint_id" {
  description = "Azure resource ID of the private endpoint."
  value       = module.private_endpoint.resource_id
}

output "private_endpoint_name" {
  description = "Name of the private endpoint."
  value       = module.private_endpoint.name
}
