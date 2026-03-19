###############################################################################
# Dev Environment Variable Values
#
# Copy this file to override defaults for a local dev workspace.
# NEVER commit files containing real secrets, subscription IDs, or tenant IDs.
#
# Usage:
#   terraform plan  -var-file="terraform.tfvars"
#   terraform apply -var-file="terraform.tfvars"
#
# For CI/CD, pass values via environment variables (TF_VAR_*) or
# a secrets-manager integration rather than committed tfvars files.
###############################################################################

# ---------------------------------------------------------------------------
# Core Identity
# ---------------------------------------------------------------------------
# Suffix "tf" differentiates Terraform-deployed resources from the Bicep
# deployment (afdblobbic) so both can coexist in the same subscription.
workload_name       = "afdblobtf"
environment_name    = "dev"
location            = "centralus"
resource_group_name = "rg-afdblobtf-dev"

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
address_space                  = ["10.0.0.0/16"]
private_endpoint_subnet_prefix = "10.0.1.0/24"

# ---------------------------------------------------------------------------
# Storage Account
# Use LRS for dev to reduce cost; upgrade to ZRS or GZRS for staging/prod.
# ---------------------------------------------------------------------------
storage_account_replication_type = "LRS"

# ---------------------------------------------------------------------------
# Log Analytics Workspace
# Minimum retention (30 days) for dev; increase for staging/prod compliance.
# ---------------------------------------------------------------------------
law_sku            = "PerGB2018"
law_retention_days = 30

# ---------------------------------------------------------------------------
# Key Vault
# Use minimum soft-delete retention (7 days) for dev iteration speed.
# Increase to 90 days for staging/prod.
# ---------------------------------------------------------------------------
kv_sku_name                   = "standard"
kv_soft_delete_retention_days = 7

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------
owner_tag = "platform-team"

tags = {
  SecurityControl = "Ignore"
}

# ---------------------------------------------------------------------------
# Module Behaviour
# Disable AVM telemetry in dev; enable in prod for Microsoft support insights.
# ---------------------------------------------------------------------------
enable_telemetry = false

# ---------------------------------------------------------------------------
# Azure Front Door + WAF
# Use 'Detection' in dev for rule tuning without blocking traffic.
# Switch to 'Prevention' in staging/prod to actively block threats.
# ---------------------------------------------------------------------------
afd_waf_mode                = "Prevention"
afd_custom_domain_host_name = "storage.christopher-house.com"

# ---------------------------------------------------------------------------
# Health Probe
# Enable the AFD health probe via anonymous blob access on the health container.
# ---------------------------------------------------------------------------
enable_front_door_health_probe = true
