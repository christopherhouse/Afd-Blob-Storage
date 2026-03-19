metadata name = 'Storage Blob Data Reader Role Assignment'
metadata description = 'Assigns the Storage Blob Data Reader role to a principal on a given storage account. Used to grant the AFD UAMI read access for health probe authentication.'
metadata owner = 'platform-team'

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Name of the storage account to scope the role assignment to.')
param storageAccountName string

@description('Principal (object) ID of the identity to assign the role to.')
param principalId string

// ── Variables ─────────────────────────────────────────────────────────────────

// Storage Blob Data Reader built-in role definition ID.
// See: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-reader
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

// ── Resources ─────────────────────────────────────────────────────────────────

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, storageBlobDataReaderRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the role assignment.')
output roleAssignmentId string = roleAssignment.id
