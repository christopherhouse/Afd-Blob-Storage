###############################################################################
# Monitoring Module Variables
###############################################################################

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the Log Analytics Workspace will be created."
}

variable "location" {
  type        = string
  description = "Azure region where the Log Analytics Workspace will be deployed."
}

variable "name" {
  type        = string
  description = "Name of the Log Analytics Workspace (CAF prefix: law-). Must be 4-63 characters, starting and ending with alphanumeric characters."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{2,61}[A-Za-z0-9]$", var.name))
    error_message = "Log Analytics Workspace name must be 4-63 characters, start and end with alphanumeric, hyphens allowed in between."
  }
}

variable "sku" {
  type        = string
  description = "Pricing SKU for the Log Analytics Workspace."
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.sku)
    error_message = "sku must be a valid Log Analytics Workspace SKU."
  }
}

variable "retention_in_days" {
  type        = number
  description = "Data-retention period in days (7 for Free tier; 30-730 for all other tiers)."
  default     = 30

  validation {
    condition     = var.retention_in_days == 7 || (var.retention_in_days >= 30 && var.retention_in_days <= 730)
    error_message = "retention_in_days must be 7 (Free tier) or between 30 and 730."
  }
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
