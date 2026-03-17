###############################################################################
# Storage Module Outputs
###############################################################################

output "storage_account_id" {
  description = "Azure resource ID of the storage account."
  value       = module.storage_account.resource_id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = module.storage_account.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint URL (e.g. https://<name>.blob.core.windows.net/)."
  # Constructed from the non-sensitive name output to avoid propagating the
  # AVM's sensitive resource output, which bundles storage access keys.
  value = "https://${module.storage_account.name}.blob.core.windows.net/"
}
