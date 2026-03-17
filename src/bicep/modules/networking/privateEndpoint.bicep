metadata name = 'Private Endpoint Module'
metadata description = 'Deploys a Private Endpoint for the Storage Account blob service and registers it with the Private DNS Zone. Consumes AVM avm/res/network/private-endpoint:0.9.1.'
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

@description('Resource ID of the subnet into which the Private Endpoint NIC will be placed.')
param subnetId string

@description('Resource ID of the Storage Account to connect via Private Endpoint.')
param storageAccountId string

@description('Resource ID of the Private DNS Zone (privatelink.blob.core.windows.net) for auto-registration.')
param privateDnsZoneId string

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming: pe- prefix, -blob suffix denotes the blob sub-resource group
var privateEndpointName = 'pe-${workloadName}-${environmentName}-blob-${locationShort}'

// ── AVM: Private Endpoint ─────────────────────────────────────────────────────
// AVM module: br/public:avm/res/network/private-endpoint:0.9.1
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/private-endpoint

module privateEndpoint 'br/public:avm/res/network/private-endpoint:0.9.1' = {
  name: 'privateEndpointDeployment'
  params: {
    name: privateEndpointName
    location: location
    subnetResourceId: subnetId
    // Connect the Private Endpoint to the storage account blob sub-resource.
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: [
            'blob'
          ]
        }
      }
    ]
    // Attach the DNS Zone Group so Azure automatically creates the A record in the
    // privatelink.blob.core.windows.net zone when the endpoint is provisioned.
    privateDnsZoneGroup: {
      name: 'default'
      privateDnsZoneGroupConfigs: [
        {
          name: 'blob-config'
          privateDnsZoneResourceId: privateDnsZoneId
        }
      ]
    }
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Private Endpoint.')
output privateEndpointId string = privateEndpoint.outputs.resourceId

@description('Name of the deployed Private Endpoint.')
output privateEndpointName string = privateEndpoint.outputs.name
