###############################################################################
# Provider Configuration
# Pinned provider versions following pessimistic constraint operator (~>).
# The azapi provider is required by AVM modules (storage, key vault, LAW).
###############################################################################

terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
      # Effective minimum: 4.37 (required by avm-res-storage-storageaccount)
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
      # Required by AVM modules: storage, key vault, log analytics workspace
    }
  }

  ###############################################################################
  # Remote State Backend (Azure Blob Storage)
  # Uncomment and populate via -backend-config or environment variables.
  # Never commit real values to source control.
  ###############################################################################
  # backend "azurerm" {
  #   resource_group_name  = "<tfstate-resource-group>"
  #   storage_account_name = "<tfstate-storage-account>"
  #   container_name       = "tfstate"
  #   key                  = "<environment>/afd-blob-storage.tfstate"
  #   use_oidc             = true
  # }
}

###############################################################################
# AzureRM Provider
# use_oidc = true enables Workload Identity Federation / OIDC authentication,
# which is required for GitHub Actions deployments without stored secrets.
###############################################################################
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy               = false
      purge_soft_deleted_secrets_on_destroy      = false
      purge_soft_deleted_certificates_on_destroy = false
      recover_soft_deleted_key_vaults            = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  use_oidc = true
}

###############################################################################
# AzAPI Provider
# Used internally by AVM modules. An empty configuration block inherits
# authentication from the azurerm provider's OIDC / environment configuration.
###############################################################################
provider "azapi" {
  use_oidc = true
}
