# Azure Front Door Premium → Private Blob Storage

This repository contains Infrastructure-as-Code (IaC) — in both **Azure Bicep** and **Terraform** — for deploying Azure Front Door Premium with WAF that routes to an Azure Blob Storage account exposed exclusively via a Private Endpoint.

> **Status:** 🚧 In development — repository scaffolding complete; IaC implementation in progress.

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
├── infra/
│   ├── bicep/                   # Bicep modules + main deployment (coming soon)
│   └── terraform/               # Terraform root + child modules (coming soon)
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
