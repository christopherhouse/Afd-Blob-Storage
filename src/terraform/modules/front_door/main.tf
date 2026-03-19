###############################################################################
# Front Door Module -- Main
#
# Deploys Azure Front Door Premium with integrated WAF (Web Application
# Firewall) to provide secure, global delivery of content from the private
# Storage Account blob service:
#   - AFD Premium profile (global, not region-bound)
#   - AFD Endpoint (unique .azurefd.net hostname)
#   - Origin Group with HTTPS health probes and weighted load balancing
#   - Origin targeting <storage>.blob.core.windows.net via Private Link
#   - Route forwarding HTTPS traffic from endpoint to origin group
#   - WAF Firewall Policy (Prevention mode) with DRS 2.1 + Bot Manager 1.0
#   - Security Policy associating the WAF policy with the AFD endpoint
#
# AVM Used: Azure/avm-res-cdn-profile/azurerm @ 0.1.9
# Registry: https://registry.terraform.io/modules/Azure/avm-res-cdn-profile/azurerm/0.1.9
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
# NOTE: Health probe path "/" targets the blob service root, which returns
# HTTP 400 (container name required). Update the probe path to a known-good
# blob URL (e.g., /health-container/probe.txt) once a suitable blob exists.
###############################################################################

module "afd_profile" {
  source  = "Azure/avm-res-cdn-profile/azurerm"
  version = "0.1.9"

  # --- Identity & Placement ---
  name                = var.afd_profile_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # --- SKU ---
  # Premium_AzureFrontDoor is required for Private Link origins and for the
  # WAF managed rule sets used in this module (DRS 2.1 + Bot Manager 1.0).
  sku = "Premium_AzureFrontDoor"

  # --- Endpoint ---
  # A single endpoint provides the public .azurefd.net hostname.
  front_door_endpoints = {
    "endpoint" = {
      name    = var.endpoint_name
      enabled = true
      tags    = var.tags
    }
  }

  # --- Custom Domain ---
  # When custom_domain_host_name is provided, register it on the AFD profile
  # with a Microsoft-managed TLS certificate. DNS ownership validation is
  # required: create a CNAME from the hostname to the AFD endpoint hostname.
  front_door_custom_domains = var.custom_domain_host_name != "" ? {
    "custom" = {
      name      = replace(var.custom_domain_host_name, ".", "-")
      host_name = var.custom_domain_host_name
      tls = {
        certificate_type    = "ManagedCertificate"
        minimum_tls_version = "TLS12"
      }
    }
  } : {}

  # --- Origin Group ---
  # Groups origins for health monitoring and load-balancing decisions.
  # HTTPS health probes run from AFD PoPs to the storage blob service
  # through the private link connection once it has been approved.
  front_door_origin_groups = {
    "og" = {
      name = var.origin_group_name

      # Health probe: GET /health/health.txt every 30 seconds over HTTPS.
      # The health container is configured with blob-level anonymous read access,
      # allowing the probe to receive a 200 OK without credentials through the
      # Private Link connection.  Ensure health/health.txt exists in the
      # storage account before expecting 200 responses.
      health_probe = {
        "hp" = {
          interval_in_seconds = 30
          path                = "/health/health.txt"
          protocol            = "Https"
          request_type        = "GET"
        }
      }

      # Load balancing: spread traffic across origins within the group using
      # a 50 ms latency window and requiring 3 of 4 recent samples to pass.
      load_balancing = {
        "lb" = {
          additional_latency_in_milliseconds = 50
          sample_size                        = 4
          successful_samples_required        = 3
        }
      }
    }
  }

  # --- Origin ---
  # Points to the storage blob service via Azure Private Link so that all
  # traffic between AFD and the storage account traverses the Microsoft
  # backbone without exposure to the public internet.
  #
  # IMPORTANT: The private_link connection will be PENDING until manually
  # approved — see the module header comment for approval steps.
  front_door_origins = {
    "origin" = {
      name             = var.origin_name
      origin_group_key = "og"

      # Blob service FQDN; used by AFD to route and for TLS SNI.
      host_name   = "${var.storage_account_name}.blob.core.windows.net"
      host_header = "${var.storage_account_name}.blob.core.windows.net"

      # Verify that the TLS certificate's CN/SAN matches host_name.
      certificate_name_check_enabled = true

      enabled    = true
      http_port  = 80
      https_port = 443
      priority   = 1
      weight     = 500

      # Private Link: routes origin traffic through a managed private endpoint
      # inside the AFD infrastructure rather than over the public internet.
      # target_type = "blob" selects the Blob service sub-resource.
      private_link = {
        "pl" = {
          request_message        = "Approved by Azure Front Door deployment"
          target_type            = "blob"
          location               = var.location
          private_link_target_id = var.storage_account_id
        }
      }
    }
  }

  # --- Route ---
  # Maps incoming requests on the endpoint to the origin group.
  # HTTP requests are redirected to HTTPS; forwarding to the origin is
  # HTTPS-only so no unencrypted traffic reaches the storage account.
  front_door_routes = {
    "route" = {
      name             = "route-blob"
      origin_group_key = "og"
      origin_keys      = ["origin"]
      endpoint_key     = "endpoint"

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
      custom_domain_keys = var.custom_domain_host_name != "" ? ["custom"] : []
    }
  }

  # --- WAF Firewall Policy ---
  # Prevention mode blocks requests matching managed rule sets.
  # Two managed rule sets are enabled:
  #   - Microsoft_DefaultRuleSet 2.1 (OWASP-based DRS): blocks common web
  #     attack patterns (SQLi, XSS, RFI, LFI, RCE, etc.)
  #   - Microsoft_BotManagerRuleSet 1.0: blocks malicious bot traffic.
  front_door_firewall_policies = {
    "waf" = {
      name                       = var.waf_policy_name
      resource_group_name        = var.resource_group_name
      sku_name                   = "Premium_AzureFrontDoor"
      enabled                    = true
      mode                       = var.waf_mode
      request_body_check_enabled = true

      managed_rules = {
        # OWASP-based Default Rule Set (DRS) 2.1 — blocks common application
        # layer attacks. "Block" means matching requests are rejected with 403.
        "drs" = {
          type    = "Microsoft_DefaultRuleSet"
          version = "2.1"
          action  = "Block"
        }
        # Bot Manager Rule Set 1.0 — classifies and blocks malicious bot
        # traffic identified by Microsoft's threat intelligence.
        "bot" = {
          type    = "Microsoft_BotManagerRuleSet"
          version = "1.0"
          action  = "Block"
        }
      }

      tags = var.tags
    }
  }

  # --- Security Policy ---
  # Associates the WAF firewall policy with the AFD endpoint so that all
  # inbound requests matching the "/*" pattern are evaluated by the WAF
  # before being forwarded to the origin.
  front_door_security_policies = {
    "secpol" = {
      name = "secpol-${var.afd_profile_name}"
      firewall = {
        front_door_firewall_policy_key = "waf"
        association = {
          # Apply the WAF policy to the AFD endpoint for all URL patterns.
          endpoint_keys      = ["endpoint"]
          custom_domain_keys = var.custom_domain_host_name != "" ? ["custom"] : []
          patterns_to_match  = ["/*"]
        }
      }
    }
  }

  # --- Telemetry & Tags ---
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}
