###############################################################################
# Root Module Variables
# Parameterised for reuse across dev / staging / prod environments.
###############################################################################

# ---------------------------------------------------------------------------
# Core Naming & Location
# ---------------------------------------------------------------------------

variable "workload_name" {
  type        = string
  description = "Short workload identifier used in all resource names (e.g. 'afdblob'). Must be lowercase alphanumeric with optional hyphens."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,14}[a-z0-9]$", var.workload_name))
    error_message = "workload_name must be 2-16 lowercase alphanumeric characters (hyphens allowed but not at start/end)."
  }
}

variable "environment_name" {
  type        = string
  description = "Deployment environment: dev, staging, or prod."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment_name)
    error_message = "environment_name must be one of: dev, staging, prod."
  }
}

variable "location" {
  type        = string
  description = "Primary Azure region for resource deployment (e.g. 'eastus', 'westeurope')."
  default     = "eastus"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "address_space" {
  type        = list(string)
  description = "One or more address spaces for the virtual network (CIDR notation)."
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.address_space) >= 1
    error_message = "At least one address space must be provided."
  }
}

variable "private_endpoint_subnet_prefix" {
  type        = string
  description = "CIDR prefix allocated to the private-endpoint subnet. Must fall within address_space."
  default     = "10.0.1.0/24"
}

# ---------------------------------------------------------------------------
# Storage Account
# ---------------------------------------------------------------------------

variable "storage_account_replication_type" {
  type        = string
  description = "Azure Storage replication strategy. Use ZRS or GZRS for production, LRS for dev/cost savings."
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "storage_account_replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# ---------------------------------------------------------------------------
# Log Analytics Workspace
# ---------------------------------------------------------------------------

variable "law_sku" {
  type        = string
  description = "Pricing SKU for the Log Analytics Workspace."
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.law_sku)
    error_message = "law_sku must be a valid Log Analytics Workspace SKU."
  }
}

variable "law_retention_days" {
  type        = number
  description = "Data-retention period in days for the Log Analytics Workspace (30-730). Free tier is limited to 7 days."
  default     = 30

  validation {
    condition     = var.law_retention_days == 7 || (var.law_retention_days >= 30 && var.law_retention_days <= 730)
    error_message = "law_retention_days must be 7 (Free tier) or between 30 and 730."
  }
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

variable "kv_sku_name" {
  type        = string
  description = "Key Vault SKU: 'standard' (software-protected) or 'premium' (HSM-backed keys)."
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.kv_sku_name)
    error_message = "kv_sku_name must be either 'standard' or 'premium'."
  }
}

variable "kv_soft_delete_retention_days" {
  type        = number
  description = "Number of days Key Vault items are retained after soft-deletion (7-90). Once purge protection is enabled this cannot be reduced."
  default     = 90

  validation {
    condition     = var.kv_soft_delete_retention_days >= 7 && var.kv_soft_delete_retention_days <= 90
    error_message = "kv_soft_delete_retention_days must be between 7 and 90."
  }
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  type        = string
  description = "Name of the pre-existing resource group to deploy resources into. The resource group must already exist; Terraform will not create it."
}

variable "owner_tag" {
  type        = string
  description = "Team or individual responsible for these resources. Used in the 'owner' tag."
  default     = "platform-team"
}

# ---------------------------------------------------------------------------
# Module Behaviour
# ---------------------------------------------------------------------------

variable "enable_telemetry" {
  type        = bool
  description = "Enable Microsoft telemetry for Azure Verified Modules. Set to false in air-gapped or regulated environments."
  default     = false
}

# ---------------------------------------------------------------------------
# Azure Front Door + WAF
# ---------------------------------------------------------------------------

variable "afd_waf_mode" {
  type        = string
  description = "WAF policy mode for Azure Front Door. Use 'Prevention' to block matching requests (production) or 'Detection' to log only without blocking (dev/testing or rule tuning)."
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.afd_waf_mode)
    error_message = "afd_waf_mode must be either 'Detection' or 'Prevention'."
  }
}

variable "afd_custom_domain_host_name" {
  type        = string
  description = "Custom domain hostname for the Terraform AFD endpoint (e.g. storage.christopher-house.com). Leave empty to use only the default .azurefd.net domain."
  default     = ""
}
