###############################################################################
# Storage Module Variables
###############################################################################

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the storage account will be created."
}

variable "location" {
  type        = string
  description = "Azure region where the storage account will be deployed."
}

variable "name" {
  type        = string
  description = "Name of the storage account. Must be globally unique, 3-24 lowercase alphanumeric characters only (CAF prefix: st)."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters (no hyphens or special characters)."
  }
}

variable "account_kind" {
  type        = string
  description = "Kind of storage account. StorageV2 supports all features including hierarchical namespaces."
  default     = "StorageV2"

  validation {
    condition     = contains(["BlobStorage", "BlockBlobStorage", "FileStorage", "Storage", "StorageV2"], var.account_kind)
    error_message = "account_kind must be one of: BlobStorage, BlockBlobStorage, FileStorage, Storage, StorageV2."
  }
}

variable "account_tier" {
  type        = string
  description = "Performance tier: Standard (HDD-backed) or Premium (SSD-backed)."
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be either 'Standard' or 'Premium'."
  }
}

variable "account_replication_type" {
  type        = string
  description = "Replication strategy for the storage account. Use ZRS or GZRS for production resiliency."
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
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

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics Workspace for blob diagnostic settings. Leave empty to skip diagnostics."
  default     = ""
}

variable "enable_front_door_health_probe" {
  type        = bool
  description = "When true, creates a 'health' blob container with anonymous blob read access so that the AFD health probe can GET /health/health.txt without authentication. AFD does not support MI auth over Private Link."
  default     = true
}
