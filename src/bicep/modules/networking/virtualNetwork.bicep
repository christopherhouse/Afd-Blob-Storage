metadata name = 'Virtual Network Module'
metadata description = 'Deploys a Virtual Network with a dedicated private-endpoint subnet. Consumes AVM avm/res/network/virtual-network:0.7.2.'
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

@description('Address prefix (CIDR) for the Virtual Network.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix (CIDR) for the dedicated private-endpoint subnet.')
param privateEndpointSubnetPrefix string = '10.0.1.0/24'

@description('Resource ID of the Network Security Group to associate with the private-endpoint subnet. Required for zero-trust network policy enforcement.')
param networkSecurityGroupResourceId string

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

var resourcePrefix = '${workloadName}-${environmentName}'

// CAF naming: vnet- prefix, snet- prefix, -pe suffix denotes private-endpoint subnet
var vnetName    = 'vnet-${resourcePrefix}-${locationShort}'
var subnetName  = 'snet-${resourcePrefix}-pe-${locationShort}'

// ── AVM: Virtual Network ───────────────────────────────────────────────────────
// AVM module: br/public:avm/res/network/virtual-network:0.7.2
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/virtual-network

module vnet 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'virtualNetworkDeployment'
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        // Private-endpoint subnet: NSG is associated and network policies are
        // set to NetworkSecurityGroupEnabled so NSG rules are enforced on
        // private endpoint traffic (zero-trust posture).
        name: subnetName
        addressPrefix: privateEndpointSubnetPrefix
        privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
        networkSecurityGroupResourceId: networkSecurityGroupResourceId
      }
    ]
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Virtual Network.')
output vnetId string = vnet.outputs.resourceId

@description('Name of the deployed Virtual Network.')
output vnetName string = vnet.outputs.name

@description('Resource ID of the private-endpoint subnet.')
output privateEndpointSubnetId string = vnet.outputs.subnetResourceIds[0]

@description('Name of the private-endpoint subnet.')
output privateEndpointSubnetName string = subnetName
