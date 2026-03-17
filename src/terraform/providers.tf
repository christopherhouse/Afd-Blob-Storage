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
  #
  # The backend block is intentionally empty — all configuration is supplied at
  # runtime via -backend-config flags (CI) or a local .tfbackend file (local dev)
  # so that no real resource names, keys, or subscription IDs are committed.
  #
  # CI (GitHub Actions) passes these flags automatically:
  #   -backend-config="resource_group_name=<var>"
  #   -backend-config="storage_account_name=<var>"
  #   -backend-config="container_name=<var>"
  #   -backend-config="key=dev/afd-blob-storage.tfstate"
  #   -backend-config="use_oidc=true"
  #   -backend-config="use_azuread_auth=true"
  #   -backend-config="subscription_id=<var>"
  #
  # use_azuread_auth=true is required to prevent the backend from falling back
  # to storage account key enumeration (listKeys), which would fail with 403
  # when the identity lacks the Storage Account Contributor role. With this flag
  # the backend uses the Entra ID token obtained via OIDC for all blob operations.
  #
  # Local development:
  #   Create src/terraform/backend.dev.tfbackend (git-ignored) with the same
  #   key=value pairs and run:
  #     terraform init -backend-config=backend.dev.tfbackend
  ###############################################################################
  backend "azurerm" {}
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

  use_oidc                    = true
  skip_provider_registration  = true
}

###############################################################################
# AzAPI Provider
# Used internally by AVM modules. An empty configuration block inherits
# authentication from the azurerm provider's OIDC / environment configuration.
###############################################################################
provider "azapi" {
  use_oidc = true
}
