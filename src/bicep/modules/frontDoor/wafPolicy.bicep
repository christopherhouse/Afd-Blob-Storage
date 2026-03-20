metadata name = 'WAF Policy Module'
metadata description = 'Deploys a Front Door WAF Policy (Premium_AzureFrontDoor SKU) with DRS 2.1 and BotManagerRuleSet 1.0 managed rule sets. Consumes AVM avm/res/network/front-door-web-application-firewall-policy:0.3.3.'
metadata owner = 'platform-team'

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region for the WAF Policy resource. AFD WAF policies are always global regardless of this value.')
param location string = 'global'

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

@description('WAF policy enforcement mode. Prevention blocks matched requests; Detection logs them only. Prefer Prevention in prod.')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Prevention'

@description('Resource tags applied to every resource in this module.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

// CAF naming for AFD WAF policies: only alphanumeric characters are permitted by the ARM API
// (no hyphens or underscores). Pattern: waf<workload><env><locationShort>, capped at 128 chars.
var rawWafPolicyName = toLower('waf${workloadName}${environmentName}${locationShort}')
var wafPolicyName    = take(rawWafPolicyName, 128)

// ── AVM: Front Door WAF Policy ────────────────────────────────────────────────
// AVM module: br/public:avm/res/network/front-door-web-application-firewall-policy:0.3.3
// Registry:   https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/front-door-web-application-firewall-policy

module wafPolicy 'br/public:avm/res/network/front-door-web-application-firewall-policy:0.3.3' = {
  name: 'wafPolicyDeployment'
  params: {
    name: wafPolicyName
    location: location

    // SKU: Premium_AzureFrontDoor is required to enable managed rule sets (DRS + BotManager)
    // and to support private-link origins on the associated AFD profile.
    sku: 'Premium_AzureFrontDoor'

    // Policy settings: enable WAF and apply the configured mode.
    // requestBodyCheck: 'Enabled' inspects the full request body for threats.
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: 'Enabled'
    }

    // Managed rules:
    //   Microsoft_DefaultRuleSet 2.1  — OWASP CRS-based ruleset with additional Azure-curated
    //     rules covering SQL injection, XSS, RCE, and more. ruleSetAction: 'Block' ensures
    //     matched requests are blocked at the WAF rather than only logged.
    //   Microsoft_BotManagerRuleSet 1.0 — Classifies and blocks known bad-bot signatures.
    //     ruleSetAction is omitted so individual rule actions within the set apply.
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleGroupOverrides: []
          exclusions: []
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleGroupOverrides: []
          exclusions: []
          // ruleSetAction is intentionally omitted so each individual bot-manager rule's
          // own configured action applies (allow, block, log, redirect) rather than
          // a single policy-level override.
        }
      ]
    }

    // Custom rules: block requests targeting the /health/* path so that internal health-probe
    // endpoints are not reachable by external clients. The regex uses an inline case-insensitive
    // flag (?i) to match regardless of casing.
    customRules: {
      rules: [
        {
          name: 'BlockHealthPath'
          priority: 100
          ruleType: 'MatchRule'
          action: 'Block'
          enabledState: 'Enabled'
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'RegEx'
              matchValue: [
                '(?i)health/'
              ]
              negateCondition: false
              transforms: []
            }
          ]
        }
      ]
    }

    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the deployed WAF Policy.')
output wafPolicyId string = wafPolicy.outputs.resourceId

@description('Name of the deployed WAF Policy.')
output wafPolicyName string = wafPolicy.outputs.name
