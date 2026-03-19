metadata name = 'User Assigned Managed Identity Module'
metadata description = 'Deploys a User Assigned Managed Identity for use by Azure Front Door to authenticate to origins via Entra ID. Consumes AVM avm/res/managed-identity/user-assigned-identity:0.4.0.'
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

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming: id-<workload>-<env>-<locationShort>
var uamiName = 'id-${workloadName}-${environmentName}-${locationShort}'

// ── AVM: User Assigned Managed Identity ───────────────────────────────────────
// AVM module: br/public:avm/res/managed-identity/user-assigned-identity:0.4.0
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/managed-identity/user-assigned-identity

module userAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'userAssignedIdentityDeployment'
  params: {
    name: uamiName
    location: location
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed User Assigned Managed Identity.')
output userAssignedIdentityId string = userAssignedIdentity.outputs.resourceId

@description('Name of the deployed User Assigned Managed Identity.')
output userAssignedIdentityName string = userAssignedIdentity.outputs.name

@description('Principal (object) ID of the deployed User Assigned Managed Identity.')
output userAssignedIdentityPrincipalId string = userAssignedIdentity.outputs.principalId

@description('Client ID of the deployed User Assigned Managed Identity.')
output userAssignedIdentityClientId string = userAssignedIdentity.outputs.clientId
