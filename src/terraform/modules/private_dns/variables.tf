###############################################################################
# Private DNS Module Variables
###############################################################################

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the Private DNS Zone and VNet link will be created."
}

variable "location" {
  type        = string
  description = "Azure region. Not directly used by Private DNS Zone resources (they are global), but accepted for consistency with other modules."
}

variable "vnet_id" {
  type        = string
  description = "Azure resource ID of the Virtual Network to link to the Private DNS Zone."
}

variable "workload_name" {
  type        = string
  description = "Short workload identifier used in the VNet link name (CAF naming)."
}

variable "environment_name" {
  type        = string
  description = "Deployment environment (e.g. dev, test, prod) used in the VNet link name (CAF naming)."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources created by this module."
  default     = {}
}
