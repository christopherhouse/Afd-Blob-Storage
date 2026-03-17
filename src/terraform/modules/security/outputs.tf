###############################################################################
# Security Module Outputs
###############################################################################

output "key_vault_id" {
  description = "Azure resource ID of the Key Vault. Use this to assign RBAC roles or configure diagnostic settings."
  value       = module.key_vault.resource_id
}

output "key_vault_uri" {
  description = "URI of the Key Vault (e.g. https://<name>.vault.azure.net/). Use this in application configuration to reference secrets."
  # module.key_vault.uri is a dedicated output from the Key Vault AVM.
  value = module.key_vault.uri
}
