metadata name = 'Network Security Group Module'
metadata description = 'Deploys a Network Security Group with zero-trust rules for the private-endpoint subnet. Consumes AVM avm/res/network/network-security-group:0.5.0.'
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

var resourcePrefix = '${workloadName}-${environmentName}'

// CAF naming: nsg- prefix
var nsgName = 'nsg-${resourcePrefix}-pe-${locationShort}'

// ── Zero-Trust NSG Rules ──────────────────────────────────────────────────────
// Rules implement a zero-trust posture for the private-endpoint subnet:
//   Inbound:  Only Azure Front Door backend traffic on HTTPS (443) is allowed.
//   Outbound: All outbound traffic is explicitly denied.
// The explicit deny-all rules (priority 4096) override the Azure default
// AllowVNetInBound (65000), AllowAzureLoadBalancerInBound (65001),
// AllowVnetOutBound (65000), and AllowInternetOutBound (65001) rules.

var securityRules = [
  // ── Inbound Rules ─────────────────────────────────────────────────────
  {
    name: 'AllowAzureFrontDoorInbound'
    properties: {
      description: 'Allow Azure Front Door backend traffic to private endpoints over HTTPS.'
      access: 'Allow'
      direction: 'Inbound'
      priority: 100
      protocol: 'Tcp'
      sourceAddressPrefix: 'AzureFrontDoor.Backend'
      sourcePortRange: '*'
      destinationAddressPrefix: 'VirtualNetwork'
      destinationPortRange: '443'
    }
  }
  {
    name: 'DenyAllInbound'
    properties: {
      description: 'Zero-trust: deny all other inbound traffic.'
      access: 'Deny'
      direction: 'Inbound'
      priority: 4096
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
    }
  }
  // ── Outbound Rules ────────────────────────────────────────────────────
  {
    name: 'DenyAllOutbound'
    properties: {
      description: 'Zero-trust: deny all outbound traffic from the private-endpoint subnet.'
      access: 'Deny'
      direction: 'Outbound'
      priority: 4096
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
    }
  }
]

// ── AVM: Network Security Group ───────────────────────────────────────────────
// AVM module: br/public:avm/res/network/network-security-group:0.5.0
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/network-security-group

module nsg 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'nsgDeployment'
  params: {
    name: nsgName
    location: location
    securityRules: securityRules
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Network Security Group.')
output nsgId string = nsg.outputs.resourceId

@description('Name of the deployed Network Security Group.')
output nsgName string = nsg.outputs.name
