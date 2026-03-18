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
// Suffix "bic" differentiates Bicep-deployed resources from the Terraform
// deployment (afdblobtf) so both can coexist in the same subscription.
param workloadName = 'afdblobbic'

param environmentName = 'dev'

param locationShort = 'cus'

// ── Networking ────────────────────────────────────────────────────────────────

param vnetAddressPrefix = '10.0.0.0/16'

param privateEndpointSubnetPrefix = '10.0.1.0/24'

// ── Storage ───────────────────────────────────────────────────────────────────

param storageSkuName = 'Standard_LRS'

// ── Monitoring ────────────────────────────────────────────────────────────────

param logRetentionInDays = 30

// ── Security ──────────────────────────────────────────────────────────────────

param kvSoftDeleteRetentionInDays = 7

// ── Front Door & WAF ──────────────────────────────────────────────────────────

param afdWafMode = 'Prevention'

param afdCustomDomainHostName = 'blob.christopher-house.com'
