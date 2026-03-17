# Azure Front Door Premium → Private Blob Storage

This repository contains Infrastructure-as-Code (IaC) — in both **Azure Bicep** and **Terraform** — for deploying Azure Front Door Premium with WAF that routes to an Azure Blob Storage account exposed exclusively via a Private Endpoint.

> **Status:** 🚧 In development — foundational infrastructure implemented; AFD and WAF integration in progress.

## Architecture Overview

```
Internet ──► Azure Front Door Premium (WAF) ──► [Private Link] ──► Private Endpoint ──► Azure Blob Storage
                                                                          │
                                                             Private DNS Zone (privatelink.blob.core.windows.net)
                                                                     linked to VNet
```

### Deployed Resources

| Resource | Purpose |
|---|---|
| Azure Front Door Premium | Global load balancer, TLS termination, caching |
| WAF Policy (Prevention Mode) | OWASP + Bot Manager managed rule sets |
| Custom Domain + Route | Routes requests to the blob origin |
| Origin Group + Origin | Points AFD to storage via Private Link |
| Storage Account | Blob storage, public network access disabled |
| Private Endpoint | Connects storage into the VNet |
| Virtual Network + Subnet | Hosts the private endpoint NIC |
| Private DNS Zone | Resolves storage FQDN to private IP |
| Log Analytics Workspace | Centralised diagnostic logs and metrics |
| Key Vault | Stores secrets and certificates; no public network access |

## Foundational Infrastructure

The following foundational resources are implemented in both `src/bicep/` and `src/terraform/`:

| Resource | Module Path (Bicep) | Module Path (Terraform) | Key Security Settings |
|---|---|---|---|
| Virtual Network + PE Subnet | `modules/networking/virtualNetwork.bicep` | `modules/networking/` | Private endpoint network policies disabled on PE subnet |
| Storage Account | `modules/storage/storageAccount.bicep` | `modules/storage/` | `publicNetworkAccess: Disabled`, `allowBlobPublicAccess: false`, TLS 1.2 minimum |
| Log Analytics Workspace | `modules/monitoring/logAnalyticsWorkspace.bicep` | `modules/monitoring/` | 30-day retention; receives diagnostic logs from all resources |
| Key Vault | `modules/security/keyVault.bicep` | `modules/security/` | RBAC authorisation mode; public network access disabled; soft-delete and purge protection enabled |

All modules use **Azure Verified Modules (AVM)** as the implementation foundation. Environment-specific values are supplied via `src/bicep/parameters/main.dev.bicepparam` (Bicep) and `src/terraform/terraform.tfvars` (Terraform).

---

## Repository Structure

```
.
├── .github/
│   ├── agents/                  # Copilot custom coding agents
│   │   ├── azure.md             # Azure WAF/CAF alignment agent
│   │   ├── bicep.md             # Bicep IaC agent
│   │   ├── documentation.md     # Documentation agent
│   │   ├── github-actions.md    # GitHub Actions CI/CD agent
│   │   ├── planning.md          # Planning agent
│   │   └── terraform.md         # Terraform IaC agent
│   ├── workflows/               # GitHub Actions CI/CD workflows (coming soon)
│   └── copilot-instructions.md  # Project-wide Copilot instructions
├── src/
│   ├── bicep/                   # Bicep modules + main deployment
│   │   ├── modules/
│   │   │   ├── monitoring/      # Log Analytics Workspace (AVM)
│   │   │   ├── networking/      # VNet + PE subnet (AVM)
│   │   │   ├── security/        # Key Vault (AVM)
│   │   │   └── storage/         # Storage account (AVM)
│   │   ├── parameters/
│   │   │   └── main.dev.bicepparam
│   │   └── main.bicep
│   └── terraform/               # Terraform root module + child modules
│       ├── modules/
│       │   ├── monitoring/      # Log Analytics Workspace (AVM)
│       │   ├── networking/      # VNet + PE subnet (AVM)
│       │   ├── security/        # Key Vault (AVM)
│       │   └── storage/         # Storage account (AVM)
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       └── terraform.tfvars
└── README.md
```

## Prerequisites

- Azure subscription with Contributor + User Access Administrator rights
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥ 2.55
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) ≥ 0.25 *(for Bicep track)*
- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.7 *(for Terraform track)*
- GitHub repository environment secrets configured for OIDC authentication

## Contributing

See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for coding standards and conventions.

## References

- [Azure Front Door Private Link](https://learn.microsoft.com/azure/frontdoor/private-link)
- [CAF Naming Convention](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Azure Verified Modules – Bicep](https://azure.github.io/Azure-Verified-Modules/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [GitHub Actions OIDC with Azure](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
