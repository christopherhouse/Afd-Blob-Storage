metadata name = 'Afd-Blob-Storage — Foundational Infrastructure'
metadata description = 'Entry-point template that orchestrates VNet, Storage Account, Log Analytics Workspace, and Key Vault modules for the Afd-Blob-Storage workload.'
metadata owner = 'platform-team'

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region for all deployed resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short workload identifier used in all CAF-compliant resource names (2–10 alphanumeric chars, no hyphens).')
@minLength(2)
@maxLength(10)
param workloadName string

@description('Deployment environment. Controls naming, SKUs, and security posture.')
@allowed(['dev', 'staging', 'prod'])
param environmentName string

@description('Short location code appended to resource names (e.g. "eus2", "weu", "aue").')
@minLength(2)
@maxLength(6)
param locationShort string

@description('Address space (CIDR) assigned to the Virtual Network.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix (CIDR) for the dedicated private-endpoint subnet inside the VNet.')
param privateEndpointSubnetPrefix string = '10.0.1.0/24'

@description('Storage Account SKU. Use Standard_LRS for dev/staging; Standard_ZRS or Standard_GRS for prod.')
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
param storageSkuName string = 'Standard_LRS'

@description('Log Analytics data retention in days (30–730).')
@minValue(30)
@maxValue(730)
param logRetentionInDays int = 30

@description('Soft-delete retention period (days) for Key Vault objects (7–90).')
@minValue(7)
@maxValue(90)
param kvSoftDeleteRetentionInDays int = 90

@description('Azure Front Door WAF policy enforcement mode. Prevention blocks matched requests; Detection only logs them. Use Detection for initial rollout validation.')
@allowed(['Detection', 'Prevention'])
param afdWafMode string = 'Prevention'

@description('Custom domain hostname for the AFD endpoint (e.g. blob.example.com). Leave empty to use the default .azurefd.net domain only.')
param afdCustomDomainHostName string = ''

@description('Additional resource tags to merge with the standard deployment tags. Use this to supply workload-specific tags (e.g. cost centre, security controls).')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// Common tags applied to every resource in this deployment.
// Extend this object or pass additional tags via parameters as needed.
var commonTags = union(tags, {
  workload: workloadName
  environment: environmentName
  deployedBy: 'bicep'
  costCenter: workloadName
})

// ── Module: Virtual Network ────────────────────────────────────────────────────

module networking 'modules/networking/virtualNetwork.bicep' = {
  name: 'networkingDeployment-${deployment().name}'
  params: {
    location: location
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    vnetAddressPrefix: vnetAddressPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    tags: commonTags
  }
}

// ── Module: Log Analytics Workspace ───────────────────────────────────────────
// Deployed before storage and key vault so their diagnostic settings can
// reference the workspace resource ID.

module monitoring 'modules/monitoring/logAnalyticsWorkspace.bicep' = {
  name: 'monitoringDeployment-${deployment().name}'
  params: {
    location: location
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    dataRetentionInDays: logRetentionInDays
    tags: commonTags
  }
}

// ── Module: Storage Account ────────────────────────────────────────────────────

module storage 'modules/storage/storageAccount.bicep' = {
  name: 'storageDeployment-${deployment().name}'
  params: {
    location: location
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    skuName: storageSkuName
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: commonTags
  }
}

// ── Module: Key Vault ──────────────────────────────────────────────────────────

module security 'modules/security/keyVault.bicep' = {
  name: 'securityDeployment-${deployment().name}'
  params: {
    location: location
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    softDeleteRetentionInDays: kvSoftDeleteRetentionInDays
    tags: commonTags
  }
}

// ── Module: Private DNS Zone ───────────────────────────────────────────────────
// Deploys the privatelink.blob.core.windows.net zone and links it to the VNet so
// that storage account FQDNs resolve to the private endpoint IP within the VNet.

module privateDns 'modules/networking/privateDnsZone.bicep' = {
  name: 'privateDnsDeployment-${deployment().name}'
  params: {
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    vnetId: networking.outputs.vnetId
    tags: commonTags
  }
}

// ── Module: Private Endpoint ───────────────────────────────────────────────────
// Places the storage account blob service private endpoint in the dedicated subnet
// and attaches the DNS Zone Group to auto-register the A record in the private DNS zone.

module privateEndpoint 'modules/networking/privateEndpoint.bicep' = {
  name: 'privateEndpointDeployment-${deployment().name}'
  params: {
    location: location
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    subnetId: networking.outputs.privateEndpointSubnetId
    storageAccountId: storage.outputs.storageAccountId
    privateDnsZoneId: privateDns.outputs.privateDnsZoneId
    tags: commonTags
  }
}

// ── Module: WAF Policy ─────────────────────────────────────────────────────────
// Deploys the Azure Front Door Premium WAF policy (DRS 2.1 + BotManagerRuleSet 1.0).
// Must be deployed before the Front Door profile so its resource ID can be passed
// to the security policy association.

module wafPolicy 'modules/frontDoor/wafPolicy.bicep' = {
  name: 'wafPolicyDeployment-${deployment().name}'
  params: {
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    wafMode: afdWafMode
    tags: commonTags
  }
}

// ── Module: User Assigned Managed Identity ────────────────────────────────────
// Deploys a UAMI that will be attached to the Azure Front Door profile to
// authenticate origin requests (health probes) to the storage account's health
// container using Entra ID instead of anonymous access.

module identity 'modules/identity/userAssignedIdentity.bicep' = {
  name: 'identityDeployment-${deployment().name}'
  params: {
    location: location
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    tags: commonTags
  }
}

// ── Module: Storage Blob Data Reader Role Assignment ──────────────────────────
// Grants the User Assigned Managed Identity the Storage Blob Data Reader role on
// the 'health' blob container so that the AFD health probe can read
// health/health.txt through the origin group authentication mechanism.
// Scoped to the container (not the entire storage account) for least privilege.

module storageBlobDataReaderRole 'modules/identity/storageBlobDataReaderRoleAssignment.bicep' = {
  name: 'storageBlobDataReaderRoleDeployment-${deployment().name}'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    containerName: 'health'
    principalId: identity.outputs.userAssignedIdentityPrincipalId
  }
}

// ── Module: Azure Front Door Premium ──────────────────────────────────────────
// Deploys the AFD Premium profile, endpoint, blob origin group (via Private Link),
// route, and security policy linking the WAF policy to the endpoint.
// Depends on: storage (for storageAccountId/Name), wafPolicy (for wafPolicyId),
// and identity (for UAMI to authenticate origin requests).

module frontDoor 'modules/frontDoor/frontDoor.bicep' = {
  name: 'frontDoorDeployment-${deployment().name}'
  params: {
    location: location
    workloadName: workloadName
    environmentName: environmentName
    locationShort: locationShort
    storageAccountName: storage.outputs.storageAccountName
    storageAccountId: storage.outputs.storageAccountId
    wafPolicyId: wafPolicy.outputs.wafPolicyId
    customDomainHostName: afdCustomDomainHostName
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    userAssignedIdentityId: identity.outputs.userAssignedIdentityId
    tags: commonTags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

// Networking
@description('Resource ID of the deployed Virtual Network.')
output vnetId string = networking.outputs.vnetId

@description('Name of the deployed Virtual Network.')
output vnetName string = networking.outputs.vnetName

@description('Resource ID of the private-endpoint subnet.')
output privateEndpointSubnetId string = networking.outputs.privateEndpointSubnetId

// Monitoring
@description('Resource ID of the Log Analytics Workspace.')
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId

@description('Name of the Log Analytics Workspace.')
output logAnalyticsWorkspaceName string = monitoring.outputs.workspaceName

@description('Workspace GUID (customerId) for diagnostic settings configuration.')
output logAnalyticsWorkspaceCustomerId string = monitoring.outputs.workspaceCustomerId

// Storage
@description('Resource ID of the Storage Account.')
output storageAccountId string = storage.outputs.storageAccountId

@description('Name of the Storage Account.')
output storageAccountName string = storage.outputs.storageAccountName

@description('Primary blob endpoint of the Storage Account.')
output primaryBlobEndpoint string = storage.outputs.primaryBlobEndpoint

// Security
@description('Resource ID of the Key Vault.')
output keyVaultId string = security.outputs.keyVaultId

@description('Name of the Key Vault.')
output keyVaultName string = security.outputs.keyVaultName

@description('URI of the Key Vault.')
output keyVaultUri string = security.outputs.keyVaultUri

// Private DNS & Private Endpoint
@description('Resource ID of the Private DNS Zone (privatelink.blob.core.windows.net).')
output privateDnsZoneId string = privateDns.outputs.privateDnsZoneId

@description('Name of the Private DNS Zone.')
output privateDnsZoneName string = privateDns.outputs.privateDnsZoneName

@description('Resource ID of the Storage Account Private Endpoint.')
output privateEndpointId string = privateEndpoint.outputs.privateEndpointId

@description('Name of the Storage Account Private Endpoint.')
output privateEndpointName string = privateEndpoint.outputs.privateEndpointName

// Front Door & WAF
@description('Resource ID of the deployed WAF Policy.')
output wafPolicyId string = wafPolicy.outputs.wafPolicyId

@description('Name of the deployed WAF Policy.')
output wafPolicyName string = wafPolicy.outputs.wafPolicyName

@description('Resource ID of the deployed Azure Front Door Premium profile.')
output frontDoorProfileId string = frontDoor.outputs.frontDoorProfileId

@description('Name of the deployed Azure Front Door Premium profile.')
output frontDoorProfileName string = frontDoor.outputs.frontDoorProfileName

@description('Auto-generated hostname of the AFD endpoint (e.g. <label>.azurefd.net).')
output frontDoorEndpointHostName string = frontDoor.outputs.frontDoorEndpointHostName

@description('Custom domain hostname configured for the AFD endpoint.')
output frontDoorCustomDomainHostName string = frontDoor.outputs.customDomainHostName

// Identity
@description('Resource ID of the User Assigned Managed Identity attached to AFD.')
output userAssignedIdentityId string = identity.outputs.userAssignedIdentityId

@description('Name of the User Assigned Managed Identity.')
output userAssignedIdentityName string = identity.outputs.userAssignedIdentityName

@description('Principal (object) ID of the User Assigned Managed Identity.')
output userAssignedIdentityPrincipalId string = identity.outputs.userAssignedIdentityPrincipalId
