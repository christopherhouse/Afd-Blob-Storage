metadata name = 'Storage Account Module'
metadata description = 'Deploys a hardened Storage Account with public network access disabled, shared-key access disabled, an upload blob container, and optional blob diagnostic settings. When enableFrontDoorHealthProbe is true, a health container with anonymous blob read access is also created. Consumes AVM avm/res/storage/storage-account:0.9.1.'
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

@description('When true, creates a "health" blob container with anonymous read access so that the AFD health probe can HEAD /health/health.txt without authentication. AFD does not support Managed Identity authentication over Private Link, so anonymous blob access is required for health probes.')
param enableFrontDoorHealthProbe bool = true

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming for storage accounts: no hyphens, lowercase, max 24 chars.
// Pattern: st<workload><env><locationShort>
// take() safely caps the string at 24 characters regardless of input length,
// avoiding the BCP335 static-analysis warning produced by a conditional check.
var rawStorageName     = toLower('st${workloadName}${environmentName}${locationShort}')
var storageAccountName = take(rawStorageName, 24)

// Blob containers: 'upload' is always private.
// When enableFrontDoorHealthProbe is true, a 'health' container is created
// with anonymous blob-level read access so that AFD health probes can read
// /health/health.txt without authentication (AFD does not support MI auth
// over Private Link).
var blobContainers = concat(
  [
    {
      name: 'upload'
      publicAccess: 'None'
    }
  ],
  enableFrontDoorHealthProbe ? [
    {
      name: 'health'
      publicAccess: 'Blob'
    }
  ] : []
)

// Build the blobServices object: always include the containers array, and
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

    // Security: allow blob-level anonymous access at the account level only when
    // the AFD health probe is enabled. This lets the 'health' container expose
    // /health/health.txt anonymously so AFD can probe origin health (AFD does not
    // support MI auth over Private Link). When disabled, no anonymous access is
    // permitted.
    allowBlobPublicAccess: enableFrontDoorHealthProbe

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
