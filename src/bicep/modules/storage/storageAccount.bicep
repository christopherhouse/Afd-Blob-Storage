metadata name = 'Storage Account Module'
metadata description = 'Deploys a hardened Storage Account with public network access disabled, shared-key access disabled, upload and health blob containers, and optional blob diagnostic settings. Consumes AVM avm/res/storage/storage-account:0.9.1.'
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

@description('Resource ID of the Log Analytics Workspace to send blob diagnostic logs and metrics to. Leave empty to skip diagnostic settings.')
param logAnalyticsWorkspaceId string = ''

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming for storage accounts: no hyphens, lowercase, max 24 chars.
// Pattern: st<workload><env><locationShort>
// take() safely caps the string at 24 characters regardless of input length,
// avoiding the BCP335 static-analysis warning produced by a conditional check.
var rawStorageName     = toLower('st${workloadName}${environmentName}${locationShort}')
var storageAccountName = take(rawStorageName, 24)

// Blob containers: 'upload' is private; 'health' allows anonymous blob reads
// so that the Azure Front Door health probe can GET health/health.txt without
// authentication through the Private Link connection.
var blobContainers = [
  {
    name: 'upload'
    // No public access — content is private and accessible via authenticated requests only.
    publicAccess: 'None'
  }
  {
    name: 'health'
    // Blob-level anonymous read access: individual blobs are publicly readable but
    // container enumeration is disabled.  Required for the AFD health probe to GET
    // health/health.txt through the Private Link endpoint without credentials.
    publicAccess: 'Blob'
  }
]

// Build the blobServices object: always include the two containers, and
// conditionally add diagnosticSettings when a Log Analytics Workspace ID is
// supplied. Using union() merges the base object (containers) with the optional
// diagnostics object so that no empty/null diagnosticSettings key is written
// when monitoring is not yet configured.
var blobServicesConfig = empty(logAnalyticsWorkspaceId) ? { containers: blobContainers } : union({ containers: blobContainers }, {
  diagnosticSettings: [
    {
      // Explicit name prevents ARM from generating a random GUID for the setting resource.
      name: 'blob-diagnostics'
      workspaceResourceId: logAnalyticsWorkspaceId
      logCategoriesAndGroups: [
        { category: 'StorageRead' }
        { category: 'StorageWrite' }
        { category: 'StorageDelete' }
      ]
      metricCategories: [
        { category: 'Transaction' }
      ]
    }
  ]
})

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

    // Security: allow blob-level anonymous access so that the 'health' container
    // can serve health.txt to the Azure Front Door health probe without credentials.
    // Anonymous access is restricted to the 'health' container (publicAccess: 'Blob');
    // all other containers remain private.  Public network access is still disabled,
    // so this only applies to traffic arriving via private endpoint (AFD Private Link).
    allowBlobPublicAccess: true

    // Security: block all network access by default; allow only from trusted Azure services.
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }

    // Security: enforce TLS 1.2+ for all client connections.
    minimumTlsVersion: 'TLS1_2'

    // Security: HTTPS-only transport.
    supportsHttpsTrafficOnly: true

    // Diagnostics: conditionally enable blob-service diagnostic settings when a
    // Log Analytics Workspace ID is provided; empty object means no diagnostics.
    blobServices: blobServicesConfig

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
