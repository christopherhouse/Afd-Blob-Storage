###############################################################################
# Security Module Variables
###############################################################################

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the Key Vault will be created."
}

variable "location" {
  type        = string
  description = "Azure region where the Key Vault will be deployed."
}

variable "name" {
  type        = string
  description = "Name of the Key Vault (CAF prefix: kv-). Must be 3-24 characters: letters, numbers, and hyphens; must start with a letter and end with a letter or number."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault name must be 3-24 characters, start with a letter, end with a letter or number, and contain only letters, numbers, and hyphens."
  }
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID used for authenticating Key Vault requests. Typically sourced from data.azurerm_client_config.current.tenant_id."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a valid lowercase UUID (e.g. 00000000-0000-0000-0000-000000000000)."
  }
}

variable "sku_name" {
  type        = string
  description = "Key Vault SKU: 'standard' (software-protected keys) or 'premium' (HSM-backed keys)."
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be either 'standard' or 'premium'."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Number of days Key Vault objects are retained after soft-deletion before they can be permanently purged (7-90)."
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
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
  default     = true
}
