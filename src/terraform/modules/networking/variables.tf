###############################################################################
# Networking Module Variables
###############################################################################

variable "resource_group_id" {
  type        = string
  description = "Azure resource ID of the resource group in which the virtual network will be created (required by the VNet AVM's parent_id argument)."

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "resource_group_id must be a valid Azure resource group resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the virtual network will be deployed."
}

variable "name" {
  type        = string
  description = "Name of the virtual network (CAF prefix: vnet-)."
}

variable "subnet_name" {
  type        = string
  description = "Name of the private-endpoint subnet (CAF prefix: snet-pe-)."
}

variable "address_space" {
  type        = list(string)
  description = "One or more address spaces for the virtual network in CIDR notation."
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.address_space) >= 1
    error_message = "At least one address space must be provided."
  }
}

variable "private_endpoint_subnet_prefix" {
  type        = string
  description = "CIDR prefix for the private-endpoint subnet. Must be within the virtual network address space."
  default     = "10.0.1.0/24"
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
