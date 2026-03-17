// ── Dev Environment Parameters ────────────────────────────────────────────────
// Target: main.bicep
// Environment: dev
//
// Usage:
//   az deployment group create \
//     --resource-group rg-afdblob-dev-eus2 \
//     --template-file ../main.bicep \
//     --parameters ./main.dev.bicepparam
// ─────────────────────────────────────────────────────────────────────────────

using '../main.bicep'

// ── Identity ──────────────────────────────────────────────────────────────────

@description('Short workload identifier (no hyphens, 2–10 chars).')
// Suffix "bic" differentiates Bicep-deployed resources from the Terraform
// deployment (afdblobtf) so both can coexist in the same subscription.
param workloadName = 'afdblobbic'

@description('Deployment environment.')
param environmentName = 'dev'

@description('Short code for East US 2.')
param locationShort = 'eus2'

// ── Networking ────────────────────────────────────────────────────────────────

@description('VNet address space for dev.')
param vnetAddressPrefix = '10.0.0.0/16'

@description('Subnet CIDR dedicated to private endpoints in dev.')
param privateEndpointSubnetPrefix = '10.0.1.0/24'

// ── Storage ───────────────────────────────────────────────────────────────────

@description('Standard_LRS is sufficient for dev (no geo-redundancy required).')
param storageSkuName = 'Standard_LRS'

// ── Monitoring ────────────────────────────────────────────────────────────────

@description('30-day retention is appropriate for dev; reduce cost.')
param logRetentionInDays = 30

// ── Security ──────────────────────────────────────────────────────────────────

@description('Minimum soft-delete window; lower values ease dev teardown.')
param kvSoftDeleteRetentionInDays = 7
