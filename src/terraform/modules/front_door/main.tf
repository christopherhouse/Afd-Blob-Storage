###############################################################################
# Front Door Module -- Main
#
# Deploys Azure Front Door Premium with integrated WAF (Web Application
# Firewall) to provide secure, global delivery of content from the private
# Storage Account blob service:
#   - AFD Premium profile (global, not region-bound)
#   - AFD Endpoint (unique .azurefd.net hostname)
#   - Custom Domain (optional, with Microsoft-managed TLS certificate)
#   - Origin Group with HTTPS health probes and weighted load balancing
#   - Origin targeting <storage>.blob.core.windows.net via Private Link
#   - Route forwarding HTTPS traffic from endpoint to origin group
#   - WAF Firewall Policy (Prevention mode) with DRS 2.1 + Bot Manager 1.0
#   - Security Policy associating the WAF policy with the AFD endpoint
#   - Diagnostic Settings (optional, sends logs & metrics to Log Analytics)
#
# NOTE: This module uses native azurerm_cdn_frontdoor_* resources instead of
# the AVM module (Azure/avm-res-cdn-profile/azurerm). The AVM module was
# previously used (v0.1.9) but caused the entire AFD profile and all child
# resources to be destroyed and recreated on every `terraform apply`, which
# is unacceptable for a production CDN endpoint. Native resources provide
# stable, incremental updates without unnecessary destroy/recreate cycles.
#
# IMPORTANT — Private Link Approval Required After Deployment:
#   After `terraform apply` completes, the Private Link connection from Azure
#   Front Door to the Storage Account will be in a PENDING state. Traffic will
#   NOT flow through the private link until the connection is manually approved:
#
#     Azure Portal → Storage Account → Networking
#       → Private endpoint connections
#       → Select the pending connection from "Azure Front Door"
#       → Click Approve
#
#   Alternatively, approve via Azure CLI:
#     az storage account private-endpoint-connection approve \
#       --account-name <storage_name> \
#       --name <connection_name> \
#       --resource-group <rg_name>
#
# NOTE: Health probe path targets /health/health.txt in an anonymously
# readable blob container. Update the probe path to a known-good blob URL
# if your container or blob name differs.
###############################################################################

###############################################################################
# AFD Premium Profile
###############################################################################

# Premium_AzureFrontDoor is required for Private Link origins and for the
# WAF managed rule sets used in this module (DRS 2.1 + Bot Manager 1.0).
resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = var.afd_profile_name
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}

###############################################################################
# AFD Endpoint
###############################################################################

# A single endpoint provides the public .azurefd.net hostname.
resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = var.endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  enabled                  = true
  tags                     = var.tags
}

###############################################################################
# Custom Domain (optional)
###############################################################################

# When custom_domain_host_name is provided, register it on the AFD profile
# with a Microsoft-managed TLS certificate. DNS ownership validation is
# required: create a CNAME from the hostname to the AFD endpoint hostname.
resource "azurerm_cdn_frontdoor_custom_domain" "this" {
  count = var.custom_domain_host_name != "" ? 1 : 0

  name                     = replace(var.custom_domain_host_name, ".", "-")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  host_name                = var.custom_domain_host_name

  tls {
    certificate_type    = "ManagedCertificate"
    minimum_tls_version = "TLS12"
  }
}

###############################################################################
# Origin Group
###############################################################################

# Groups origins for health monitoring and load-balancing decisions.
# HTTPS health probes run from AFD PoPs to the storage blob service
# through the private link connection once it has been approved.
# When enable_front_door_health_probe is true, probes GET /health/health.txt
# from an anonymously readable blob container. When false, the health probe
# is omitted entirely for the origin group.
resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = var.origin_group_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  # Load balancing: spread traffic across origins within the group using
  # a 50 ms latency window and requiring 3 of 4 recent samples to pass.
  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }

  # Health probe: GET /health/health.txt when enabled, omitted when false.
  # AFD does not support MI auth over Private Link, so health probes rely
  # on anonymous blob access when enabled.
  dynamic "health_probe" {
    for_each = var.enable_front_door_health_probe ? [1] : []
    content {
      interval_in_seconds = 30
      path                = "/health/health.txt"
      protocol            = "Https"
      request_type        = "GET"
    }
  }
}

###############################################################################
# Origin (Storage Blob via Private Link)
###############################################################################

# Points to the storage blob service via Azure Private Link so that all
# traffic between AFD and the storage account traverses the Microsoft
# backbone without exposure to the public internet.
#
# IMPORTANT: The private_link connection will be PENDING until manually
# approved — see the module header comment for approval steps.
resource "azurerm_cdn_frontdoor_origin" "this" {
  name                          = var.origin_name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                       = true

  # Blob service FQDN; used by AFD to route and for TLS SNI.
  host_name          = "${var.storage_account_name}.blob.core.windows.net"
  origin_host_header = "${var.storage_account_name}.blob.core.windows.net"

  # Verify that the TLS certificate's CN/SAN matches host_name.
  certificate_name_check_enabled = true

  http_port  = 80
  https_port = 443
  priority   = 1
  weight     = 500

  # Private Link: routes origin traffic through a managed private endpoint
  # inside the AFD infrastructure rather than over the public internet.
  # target_type = "blob" selects the Blob service sub-resource.
  private_link {
    request_message        = "Approved by Azure Front Door deployment"
    target_type            = "blob"
    location               = var.location
    private_link_target_id = var.storage_account_id
  }
}

###############################################################################
# Route
###############################################################################

# Maps incoming requests on the endpoint to the origin group.
# HTTP requests are redirected to HTTPS; forwarding to the origin is
# HTTPS-only so no unencrypted traffic reaches the storage account.
resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "route-blob"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this.id]

  # Forward all traffic to the origin as HTTPS.
  forwarding_protocol = "HttpsOnly"

  # Accept both HTTP and HTTPS; HTTP is redirected to HTTPS by the rule below.
  supported_protocols = ["Http", "Https"]

  # Match all URL paths.
  patterns_to_match = ["/*"]

  # Use the endpoint's default .azurefd.net domain.
  link_to_default_domain = true

  # Redirect any plain-HTTP request to HTTPS automatically.
  https_redirect_enabled = true

  # Associate the custom domain with this route when one is configured.
  cdn_frontdoor_custom_domain_ids = var.custom_domain_host_name != "" ? [
    azurerm_cdn_frontdoor_custom_domain.this[0].id
  ] : []
}

###############################################################################
# WAF Firewall Policy
###############################################################################

# Prevention mode blocks requests matching managed rule sets.
# Two managed rule sets are enabled:
#   - Microsoft_DefaultRuleSet 2.1 (OWASP-based DRS): blocks common web
#     attack patterns (SQLi, XSS, RFI, LFI, RCE, etc.)
#   - Microsoft_BotManagerRuleSet 1.0: blocks malicious bot traffic.
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                              = var.waf_policy_name
  resource_group_name               = var.resource_group_name
  sku_name                          = azurerm_cdn_frontdoor_profile.this.sku_name
  enabled                           = true
  mode                              = var.waf_mode
  request_body_check_enabled        = true

  # OWASP-based Default Rule Set (DRS) 2.1 — blocks common application
  # layer attacks. "Block" means matching requests are rejected with 403.
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  # Bot Manager Rule Set 1.0 — classifies and blocks malicious bot
  # traffic identified by Microsoft's threat intelligence.
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  tags = var.tags
}

###############################################################################
# Security Policy
###############################################################################

# Associates the WAF firewall policy with the AFD endpoint (and custom
# domain when configured) so that all inbound requests matching the "/*"
# pattern are evaluated by the WAF before being forwarded to the origin.
resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "secpol-${var.afd_profile_name}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id

      association {
        # Apply the WAF policy to the AFD endpoint for all URL patterns.
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }

        # Also associate with the custom domain when one is configured.
        dynamic "domain" {
          for_each = var.custom_domain_host_name != "" ? ["custom_domain"] : []
          content {
            cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_custom_domain.this[0].id
          }
        }

        patterns_to_match = ["/*"]
      }
    }
  }
}

###############################################################################
# Diagnostic Settings (optional)
###############################################################################

# Send all AFD logs (access, health probe, WAF) and metrics to the central
# Log Analytics Workspace. Only enabled when a workspace ID is provided.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = "afd-diagnostics"
  target_resource_id         = azurerm_cdn_frontdoor_profile.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Send all log categories to Log Analytics.
  enabled_log {
    category_group = "allLogs"
  }

  # Send all metrics to Log Analytics.
  metric {
    category = "AllMetrics"
  }
}
