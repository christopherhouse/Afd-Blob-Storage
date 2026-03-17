###############################################################################
# Private Endpoint Module Variables
###############################################################################

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the private endpoint will be created."
}

variable "location" {
  type        = string
  description = "Azure region where the private endpoint will be deployed."
}

variable "name" {
  type        = string
  description = "Name of the private endpoint (CAF prefix: pe-). Example: pe-<workload>-<env>-blob."
}

variable "subnet_resource_id" {
  type        = string
  description = "Azure resource ID of the subnet in which to place the private endpoint NIC."
}

variable "storage_account_id" {
  type        = string
  description = "Azure resource ID of the storage account to connect via the private endpoint."
}

variable "private_dns_zone_id" {
  type        = string
  description = "Azure resource ID of the Private DNS Zone (privatelink.blob.core.windows.net) used by the DNS zone group."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources created by this module."
  default     = {}
}

variable "enable_telemetry" {
  type        = bool
  description = "Enable Microsoft telemetry for the Azure Verified Module."
  default     = false
}
