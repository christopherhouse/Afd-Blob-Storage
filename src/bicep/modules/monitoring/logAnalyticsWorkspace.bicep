metadata name = 'Log Analytics Workspace Module'
metadata description = 'Deploys a Log Analytics Workspace for centralised monitoring and diagnostics. Consumes AVM avm/res/operational-insights/workspace:0.9.1.'
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

@description('Log Analytics SKU.')
@allowed([
  'CapacityReservation'
  'Free'
  'LACluster'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param skuName string = 'PerGB2018'

@description('Data retention period in days. Must be between 30 and 730.')
@minValue(30)
@maxValue(730)
param dataRetentionInDays int = 30

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming: law- prefix
var workspaceName = 'law-${workloadName}-${environmentName}-${locationShort}'

// ── AVM: Log Analytics Workspace ──────────────────────────────────────────────
// AVM module: br/public:avm/res/operational-insights/workspace:0.9.1
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/operational-insights/workspace

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.9.1' = {
  name: 'logAnalyticsWorkspaceDeployment'
  params: {
    name: workspaceName
    location: location
    skuName: skuName
    dataRetention: dataRetentionInDays
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Log Analytics Workspace.')
output workspaceId string = logAnalyticsWorkspace.outputs.resourceId

@description('Name of the deployed Log Analytics Workspace.')
output workspaceName string = logAnalyticsWorkspace.outputs.name

@description('Workspace GUID (customerId) used when configuring diagnostic settings.')
output workspaceCustomerId string = logAnalyticsWorkspace.outputs.logAnalyticsWorkspaceId
