###############################################################################
# Front Door Module Variables
###############################################################################

# ---------------------------------------------------------------------------
# Identity & Placement
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the AFD profile and WAF firewall policy will be deployed."
}

variable "location" {
  type        = string
  description = "Azure region used for the Private Link origin connection. Azure Front Door itself is a global service; this value is only used to locate the Private Link resource on the storage account side."
}

# ---------------------------------------------------------------------------
# Naming (CAF-compliant)
# ---------------------------------------------------------------------------

variable "afd_profile_name" {
  type        = string
  description = "Name of the Azure Front Door Premium profile. CAF convention: afd-<workload>-<env>."
}

variable "endpoint_name" {
  type        = string
  description = "Name of the Azure Front Door endpoint. Must be globally unique. CAF convention: afdep-<workload>-<env>."
}

variable "origin_group_name" {
  type        = string
  description = "Name of the Front Door origin group. CAF convention: og-<workload>-<env>."
}

variable "origin_name" {
  type        = string
  description = "Name of the Front Door origin. CAF convention: origin-<workload>-<env>."
}

variable "waf_policy_name" {
  type        = string
  description = "Name of the Front Door WAF firewall policy. Must be alphanumeric only — no hyphens or special characters (Azure restriction). Max 128 characters. CAF convention: waf<workload><env>."

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{1,128}$", var.waf_policy_name))
    error_message = "waf_policy_name must be 1-128 alphanumeric characters only (no hyphens or special characters — Azure restriction on WAF policy names)."
  }
}

# ---------------------------------------------------------------------------
# Storage Account (Origin)
# ---------------------------------------------------------------------------

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account used as the AFD origin. Used to construct the blob service FQDN: <name>.blob.core.windows.net."
}

variable "storage_account_id" {
  type        = string
  description = "Azure resource ID of the storage account. Used for the Private Link connection from AFD to the blob service."
}

# ---------------------------------------------------------------------------
# WAF Configuration
# ---------------------------------------------------------------------------

variable "waf_mode" {
  type        = string
  description = "WAF policy enforcement mode. 'Prevention' blocks requests matching managed rules (use in production). 'Detection' logs matches only without blocking (use for dev/testing or rule tuning)."
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be either 'Detection' or 'Prevention'."
  }
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources created by this module."
  default     = {}
}

variable "custom_domain_host_name" {
  type        = string
  description = "Custom domain hostname for the AFD endpoint (e.g. storage.example.com). Leave empty to use the default .azurefd.net domain only."
  default     = ""
}

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics Workspace for AFD diagnostic settings. Leave empty to skip diagnostics."
  default     = ""
}

variable "enable_front_door_health_probe" {
  type        = bool
  description = "When true, configures the AFD origin group health probe to GET /health/health.txt. When false, the health probe is disabled entirely for the origin group. AFD does not support MI auth over Private Link, so health probes rely on anonymous blob access when enabled."
  default     = true
}
