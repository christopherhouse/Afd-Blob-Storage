metadata name = 'Storage Account Module'
metadata description = 'Deploys a hardened Storage Account with public access disabled and shared-key access disabled. Consumes AVM avm/res/storage/storage-account:0.9.1.'
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

@description('Storage account SKU. Defaults to Standard_LRS for lower environments; consider Standard_ZRS or Standard_GRS for prod.')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_LRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
  'Standard_ZRS'
])
param skuName string = 'Standard_LRS'

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming for storage accounts: no hyphens, lowercase, max 24 chars.
// Pattern: st<workload><env><locationShort>
// take() safely caps the string at 24 characters regardless of input length,
// avoiding the BCP335 static-analysis warning produced by a conditional check.
var rawStorageName     = toLower('st${workloadName}${environmentName}${locationShort}')
var storageAccountName = take(rawStorageName, 24)

// ── AVM: Storage Account ───────────────────────────────────────────────────────
// AVM module: br/public:avm/res/storage/storage-account:0.9.1
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/storage/storage-account

module storageAccount 'br/public:avm/res/storage/storage-account:0.9.1' = {
  name: 'storageAccountDeployment'
  params: {
    name: storageAccountName
    location: location
    skuName: skuName
    kind: 'StorageV2'

    // Security: disable shared-key (SAS) access — enforce AAD/RBAC-only auth.
    allowSharedKeyAccess: false

    // Security: disable all public inbound traffic; access via private endpoint only.
    publicNetworkAccess: 'Disabled'

    // Security: blobs must never be anonymously accessible.
    allowBlobPublicAccess: false

    // Security: block all network access by default; allow only from trusted Azure services.
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }

    // Security: enforce TLS 1.2+ for all client connections.
    minimumTlsVersion: 'TLS1_2'

    // Security: HTTPS-only transport.
    supportsHttpsTrafficOnly: true

    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Storage Account.')
output storageAccountId string = storageAccount.outputs.resourceId

@description('Name of the deployed Storage Account.')
output storageAccountName string = storageAccount.outputs.name

@description('Primary blob service endpoint URL.')
output primaryBlobEndpoint string = 'https://${storageAccount.outputs.name}.blob.${environment().suffixes.storage}/'
