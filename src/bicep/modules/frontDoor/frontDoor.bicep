metadata name = 'Azure Front Door Premium Module'
metadata description = 'Deploys an Azure Front Door Premium profile with a WAF security policy, a private-link origin pointing to an Azure Blob Storage account, and an AFD endpoint with route. Consumes AVM avm/res/cdn/profile:0.11.0.'
metadata owner = 'platform-team'

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region used as the Private Link origin location. The AFD profile itself is always deployed as a global resource.')
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

@description('Name of the Storage Account whose blob endpoint will serve as the AFD origin.')
param storageAccountName string

@description('Resource ID of the Storage Account used to configure the Private Link connection from AFD to blob storage.')
param storageAccountId string

@description('Resource ID of the WAF Policy to attach to this Front Door profile via the security policy.')
param wafPolicyId string

@description('Resource tags applied to every resource in this module.')
param tags object = {}

@description('Custom domain hostname for the AFD endpoint (e.g. blob.example.com). Leave empty to use the default .azurefd.net domain only.')
param customDomainHostName string = ''

@description('Resource ID of the Log Analytics Workspace to send AFD diagnostic logs and metrics to. Leave empty to skip diagnostic settings.')
param logAnalyticsWorkspaceId string = ''

@description('When true, configures the AFD origin group health probe to GET /health/health.txt. When false, uses a basic HEAD / probe. AFD does not support Managed Identity authentication over Private Link, so health probes rely on anonymous blob access when enabled.')
param enableFrontDoorHealthProbe bool = true

// ── Variables ─────────────────────────────────────────────────────────────────

var resourcePrefix = '${workloadName}-${environmentName}'

// CAF naming:
//   AFD profile:   afd-  prefix
//   AFD endpoint:  afdep- prefix
//   Origin group:  og-   prefix
var afdProfileName  = 'afd-${resourcePrefix}'
var afdEndpointName = 'afdep-${resourcePrefix}'
var originGroupName = 'og-${resourcePrefix}'
var originName      = 'origin-${resourcePrefix}-blob-${locationShort}'
var routeName       = 'route-${resourcePrefix}-blob-${locationShort}'
var secPolicyName   = 'secpol-${resourcePrefix}-${locationShort}'

// Custom domain: replace dots with hyphens to form a valid ARM resource name.
// e.g. 'blob.christopher-house.com' → 'blob-christopher-house-com'
var customDomainResourceName = replace(customDomainHostName, '.', '-')
var hasCustomDomain          = !empty(customDomainHostName)

// Storage Account blob FQDN — used as the origin hostname and origin host header.
// environment().suffixes.storage resolves to 'core.windows.net' in public cloud,
// ensuring this template is cloud-agnostic.
var blobHostName = '${storageAccountName}.blob.${environment().suffixes.storage}'

// Pre-compute the AFD endpoint resource ID for use in the security policy
// associations block. The security policy is deployed as a separate resource
// (after the AVM module) to avoid a race condition where ARM processes the
// security policy before the endpoint is fully created.
// resourceId() constructs: /subscriptions/{sub}/resourceGroups/{rg}/providers/
//   Microsoft.Cdn/profiles/{profile}/afdEndpoints/{endpoint}
var afdEndpointResourceId = resourceId(
  'Microsoft.Cdn/profiles/afdEndpoints',
  afdProfileName,
  afdEndpointName
)

// ── AVM: CDN / AFD Premium Profile ────────────────────────────────────────────
// AVM module: br/public:avm/res/cdn/profile:0.11.0
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/cdn/profile
// Upgraded from 0.8.0 → 0.11.0 to gain native diagnosticSettings parameter support.

module afdProfile 'br/public:avm/res/cdn/profile:0.11.0' = {
  name: 'afdProfileDeployment'
  params: {
    name: afdProfileName

    // SKU: Premium_AzureFrontDoor is required for WAF managed rule sets and Private Link origins.
    sku: 'Premium_AzureFrontDoor'

    // AFD profiles are always a global resource regardless of workload region.
    location: 'global'

    // ── AFD Endpoint ────────────────────────────────────────────────────────────
    // One endpoint exposes the auto-generated *.azurefd.net hostname to clients.
    // TenantReuse preserves the auto-generated hostname label across redeployments
    // so that DNS CNAMEs set up by consumers do not break on re-deploys.
    afdEndpoints: [
      {
        name: afdEndpointName
        enabledState: 'Enabled'
        autoGeneratedDomainNameLabelScope: 'TenantReuse'
        routes: [
          {
            name: routeName
            // Forward all matched traffic to the storage origin group over HTTPS only.
            originGroupName: originGroupName
            forwardingProtocol: 'HttpsOnly'
            // Redirect any plain-HTTP clients to HTTPS at the edge.
            httpsRedirect: 'Enabled'
            enabledState: 'Enabled'
            // Link the route to the auto-generated *.azurefd.net default domain.
            linkToDefaultDomain: 'Enabled'
            // Match all paths so the entire blob namespace is routable through AFD.
            patternsToMatch: [
              '/*'
            ]
            supportedProtocols: [
              'Http'
              'Https'
            ]
            customDomainNames: []
          }
        ]
      }
    ]

    // ── Origin Group ────────────────────────────────────────────────────────────
    // One origin group containing the blob storage endpoint as the single origin.
    originGroups: [
      {
        name: originGroupName
        // Health probe: when enableFrontDoorHealthProbe is true, GET requests are
        // sent to /health/health.txt (an anonymously readable blob) every 100 seconds.
        // When disabled, HEAD requests to / serve as a basic connectivity check.
        healthProbeSettings: {
          probeIntervalInSeconds: 100
          probePath: enableFrontDoorHealthProbe ? '/health/health.txt' : '/'
          probeProtocol: 'Https'
          probeRequestType: enableFrontDoorHealthProbe ? 'GET' : 'HEAD'
        }
        loadBalancingSettings: {
          additionalLatencyInMilliseconds: 50
          sampleSize: 4
          successfulSamplesRequired: 3
        }

        // ── Origin ──────────────────────────────────────────────────────────────
        origins: [
          {
            name: originName
            enabledState: 'Enabled'
            // Enforce TLS certificate name check to verify the Storage Account's certificate.
            enforceCertificateNameCheck: true
            hostName: blobHostName
            httpPort: 80
            httpsPort: 443
            // The origin host header MUST match the Storage Account FQDN; otherwise
            // the blob service returns HTTP 400 Bad Request.
            originHostHeader: blobHostName
            priority: 1
            weight: 1000

            // Private Link: AFD connects to the Storage Account through a managed
            // private endpoint rather than over the public internet.
            //
            // ⚠ MANUAL APPROVAL REQUIRED ⚠
            // After this deployment completes, the private endpoint connection request
            // must be approved before AFD can forward traffic to the blob origin.
            // Approve via the Azure portal:
            //   Storage Account → Networking → Private endpoint connections → Approve
            // Or via Azure CLI:
            //   az network private-endpoint-connection approve \
            //     --resource-group <rg> \
            //     --name <storage-account-name> \
            //     --type Microsoft.Storage/storageAccounts \
            //     --id <connection-id>
            sharedPrivateLinkResource: {
              privateLink: {
                id: storageAccountId
              }
              privateLinkLocation: location
              groupId: 'blob'
              requestMessage: 'Approved by Azure Front Door deployment'
            }
          }
        ]
      }
    ]

    // ── Diagnostic Settings ──────────────────────────────────────────────────────
    // Conditionally send all AFD logs and metrics to the Log Analytics Workspace
    // when a workspace resource ID is provided; otherwise pass an empty array so
    // the AVM module skips diagnostic settings entirely.
    diagnosticSettings: empty(logAnalyticsWorkspaceId) ? [] : [
      {
        name: 'afd-diagnostics'
        workspaceResourceId: logAnalyticsWorkspaceId
        logCategoriesAndGroups: [
          {
            categoryGroup: 'allLogs'
            enabled: true
          }
        ]
        metricCategories: [
          {
            category: 'AllMetrics'
            enabled: true
          }
        ]
      }
    ]

    tags: tags
  }
}

// ── Origin Group Authentication ──────────────────────────────────────────────
// NOTE: Origin group authentication via User Assigned Managed Identity was
// previously deployed here, but AFD does not support MI authentication over
// Private Link connections. Health probe authentication is now handled via
// anonymous blob access on the 'health' container (controlled by the
// enableFrontDoorHealthProbe parameter).

// ── Existing resource reference: AFD Endpoint hostname ────────────────────────
// The AVM cdn/profile:0.8.0 module does not surface per-endpoint hostnames as
// outputs for AFD endpoints (only classic CDN endpoints). We therefore read the
// hostname directly from the deployed AFD endpoint resource using `existing`.
// The local variable `afdProfileName` is used (instead of `afdProfile.outputs.name`)
// to avoid a nested reference() expression in the ARM output, which ARM template
// validation rejects. Outputs are always evaluated after all resources in the
// template are deployed, so the profile is guaranteed to exist at this point.
resource afdProfileRef 'Microsoft.Cdn/profiles@2025-04-15' existing = {
  name: afdProfileName

  resource afdEndpointRef 'afdEndpoints@2025-04-15' existing = {
    name: afdEndpointName
  }

  resource originGroupRef 'originGroups@2025-04-15' existing = {
    name: originGroupName
  }
}

// ── Custom Domain ──────────────────────────────────────────────────────────────
// Deployed as a separate resource (not inside the AVM module call) so that ARM
// guarantees the AFD profile exists before the custom domain is created, and so
// that the route update (below) can explicitly depend on the domain being fully
// provisioned. Passing customDomains inside the same AVM module call that also
// creates afdEndpoints/routes can trigger a ResourceNotFound error because ARM
// does not guarantee sub-deployment ordering within a single nested deployment.
// tlsSettings.certificateType and minimumTlsVersion are nested under tlsSettings
// as required by the Microsoft.Cdn/profiles/customDomains ARM resource schema.
//
// NOTE: The explicit dependsOn: [afdProfile] below is intentional and NOT
// redundant. `afdProfileRef` is an `existing` resource block — a separate
// symbolic reference that Bicep does not automatically link to the `afdProfile`
// module that creates the profile. Without this dependsOn, ARM could attempt to
// create the custom domain child resource before the parent profile deployment
// (the AVM module) has completed, causing a ResourceNotFound error.
resource customDomain 'Microsoft.Cdn/profiles/customDomains@2025-04-15' = if (hasCustomDomain) {
  parent: afdProfileRef
  name: customDomainResourceName
  properties: {
    hostName: customDomainHostName
    tlsSettings: {
      certificateType: 'ManagedCertificate'
      minimumTlsVersion: 'TLS12'
    }
  }
  dependsOn: [
    afdProfile
  ]
}

// ── Route update: associate custom domain ────────────────────────────────────
// After the custom domain is provisioned, update the route (which the AVM module
// created without a custom domain) to add the custom domain association. This is
// a full PUT on the route resource — all route properties must be repeated here.
// The explicit dependsOn ensures the custom domain exists before the route
// references it, matching the pattern in the official Azure quickstart template.
resource afdRouteWithCustomDomain 'Microsoft.Cdn/profiles/afdEndpoints/routes@2025-04-15' = if (hasCustomDomain) {
  parent: afdProfileRef::afdEndpointRef
  name: routeName
  properties: {
    customDomains: [
      {
        id: customDomain.id
      }
    ]
    originGroup: {
      id: afdProfileRef::originGroupRef.id
    }
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
    linkToDefaultDomain: 'Enabled'
    patternsToMatch: [
      '/*'
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
  }
}

// ── Security Policy ────────────────────────────────────────────────────────────
// Deployed as a separate resource (not inside the AVM module call) so that ARM
// guarantees the AFD endpoint exists before the security policy association is
// attempted. Passing securityPolicies inside the same AVM module call that also
// creates afdEndpoints can trigger a ResourceNotFound error because ARM does not
// guarantee child-resource ordering within a single nested deployment.
// The explicit dependsOn ensures the entire afdProfile module — including the
// endpoint — has completed before this resource is created.
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2025-04-15' = {
  parent: afdProfileRef
  name: secPolicyName
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          // Associate the WAF policy with the AFD endpoint and, when configured,
          // also with the custom domain so WAF inspection covers both entry points.
          domains: concat(
            [
              {
                id: afdEndpointResourceId
              }
            ],
            hasCustomDomain ? [
              {
                id: customDomain.id
              }
            ] : []
          )
          // Apply WAF inspection to all URL paths.
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
  dependsOn: [
    afdProfile
    afdRouteWithCustomDomain
  ]
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed Azure Front Door Premium profile.')
output frontDoorProfileId string = afdProfile.outputs.resourceId

@description('Name of the deployed Azure Front Door Premium profile.')
output frontDoorProfileName string = afdProfile.outputs.name

@description('Auto-generated hostname of the AFD endpoint (e.g. <label>.azurefd.net). Use this as the CNAME target for custom domains.')
output frontDoorEndpointHostName string = afdProfileRef::afdEndpointRef.properties.hostName

@description('Custom domain hostname configured on the AFD endpoint. Empty string when no custom domain is configured.')
output customDomainHostName string = customDomainHostName

@description('DNS validation token for custom domain ownership verification. Add this as a TXT record at _dnsauth.<customDomain> to allow Microsoft to issue a managed certificate. Empty string when no custom domain is configured.')
output customDomainValidationToken string = customDomain.?properties.?validationProperties.?validationToken ?? ''
