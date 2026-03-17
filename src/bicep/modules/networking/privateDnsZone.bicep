metadata name = 'Private DNS Zone Module'
metadata description = 'Deploys the privatelink.blob.core.windows.net Private DNS Zone and links it to the workload VNet. Consumes AVM avm/res/network/private-dns-zone:0.8.1.'
metadata owner = 'platform-team'

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────

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

@description('Resource ID of the Virtual Network to link to this Private DNS Zone.')
param vnetId string

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming: Private DNS zones use the well-known Azure service FQDN as the zone name.
// Using environment().suffixes.storage ensures multi-cloud portability:
//   AzureCloud       → privatelink.blob.core.windows.net
//   AzureUSGovernment → privatelink.blob.core.usgovcloudapi.net
//   AzureChinaCloud  → privatelink.blob.core.chinacloudapi.cn
// The VNet link name follows the pattern: pdnslink-<workload>-<env>-<locationShort>
var privateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var vnetLinkName       = 'pdnslink-${workloadName}-${environmentName}-${locationShort}'

// ── AVM: Private DNS Zone ─────────────────────────────────────────────────────
// AVM module: br/public:avm/res/network/private-dns-zone:0.8.1
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/private-dns-zone

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  name: 'privateDnsZoneDeployment'
  params: {
    // Private DNS Zones are a global resource; location must be 'global'.
    name: privateDnsZoneName
    location: 'global'
    virtualNetworkLinks: [
      {
        name: vnetLinkName
        virtualNetworkResourceId: vnetId
        // Auto-registration is disabled: the A record is managed by the Private Endpoint
        // DNS Zone Group, which registers it automatically on endpoint creation.
        registrationEnabled: false
      }
    ]
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Private DNS Zone.')
output privateDnsZoneId string = privateDnsZone.outputs.resourceId

@description('Name of the deployed Private DNS Zone (e.g. privatelink.blob.core.windows.net).')
output privateDnsZoneName string = privateDnsZone.outputs.name
