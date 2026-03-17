###############################################################################
# Private DNS Module Outputs
###############################################################################

output "private_dns_zone_id" {
  description = "Azure resource ID of the Private DNS Zone (privatelink.blob.core.windows.net). Pass this to the private endpoint DNS zone group."
  value       = azurerm_private_dns_zone.this.id
}

output "private_dns_zone_name" {
  description = "Name of the Private DNS Zone (privatelink.blob.core.windows.net)."
  value       = azurerm_private_dns_zone.this.name
}
