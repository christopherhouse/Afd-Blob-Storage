metadata name = 'Key Vault Module'
metadata description = 'Deploys a hardened Key Vault with RBAC authorisation, soft-delete, purge protection, and public network access disabled. Consumes AVM avm/res/key-vault/vault:0.9.0.'
metadata owner = 'platform-team'

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region for all resources in this module.')
param location string = resourceGroup().location

@description('Workload name used as part of CAF-compliant resource names.')
@minLength(2)
@maxLength(10)
param workloadName string

@description('Deployment environment. Drives naming and configuration differences.')
@allowed(['dev', 'staging', 'prod'])
param environmentName string

@description('Short location code appended to resource names (e.g. "eus2", "weu").')
@minLength(2)
@maxLength(6)
param locationShort string

@description('Number of days to retain soft-deleted vault objects. Must be between 7 and 90.')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming: kv- prefix. Key Vault names: 3–24 chars, alphanumeric + hyphens.
// take() safely caps the string at 24 characters regardless of input length,
// avoiding BCP335 static-analysis warnings when combined name exceeds the limit.
var rawKvName    = toLower('kv-${workloadName}-${environmentName}-${locationShort}')
var keyVaultName = take(rawKvName, 24)

// ── AVM: Key Vault ─────────────────────────────────────────────────────────────
// AVM module: br/public:avm/res/key-vault/vault:0.9.0
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/key-vault/vault

module keyVault 'br/public:avm/res/key-vault/vault:0.9.0' = {
  name: 'keyVaultDeployment'
  params: {
    name: keyVaultName
    location: location

    // Security: use Azure RBAC for data-plane authorisation instead of legacy access policies.
    enableRbacAuthorization: true

    // Resilience: soft-delete protects against accidental deletion.
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays

    // Security: purge protection prevents permanent deletion during the retention window.
    enablePurgeProtection: true

    // Security: disable all public inbound traffic; access via private endpoint only.
    publicNetworkAccess: 'Disabled'

    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Key Vault.')
output keyVaultId string = keyVault.outputs.resourceId

@description('Name of the deployed Key Vault.')
output keyVaultName string = keyVault.outputs.name

@description('URI of the deployed Key Vault (used by applications to reference secrets/keys).')
output keyVaultUri string = keyVault.outputs.uri
