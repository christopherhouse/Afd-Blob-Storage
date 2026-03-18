###############################################################################
# Front Door Module Outputs
###############################################################################

output "afd_profile_id" {
  description = "Azure resource ID of the Azure Front Door Premium profile."
  value       = module.afd_profile.resource_id
}

output "afd_profile_name" {
  description = "Name of the Azure Front Door Premium profile."
  value       = module.afd_profile.resource_name
}

output "afd_endpoint_hostname" {
  description = "The .azurefd.net hostname of the Front Door endpoint (e.g. <name>-<hash>.z01.azurefd.net). Use this as the public entry point for the storage content."
  value       = module.afd_profile.frontdoor_endpoints["endpoint"].host_name
}

output "afd_custom_domain_host_name" {
  description = "The custom domain hostname configured on the AFD profile (empty string if none was configured)."
  value       = var.custom_domain_host_name
}
