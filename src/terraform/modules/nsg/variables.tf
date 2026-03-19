###############################################################################
# NSG Module Variables
###############################################################################

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the NSG will be created."
}

variable "location" {
  type        = string
  description = "Azure region where the NSG will be deployed."
}

variable "name" {
  type        = string
  description = "Name of the Network Security Group (CAF prefix: nsg-)."
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
