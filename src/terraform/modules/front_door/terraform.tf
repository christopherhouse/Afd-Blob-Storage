###############################################################################
# Front Door Module -- Provider Requirements
#
# The azapi provider is required for the origin group authentication
# configuration, which is not yet supported by the azurerm provider or the
# AVM CDN module natively.
###############################################################################

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    azapi = {
      source = "Azure/azapi"
    }
  }
}
