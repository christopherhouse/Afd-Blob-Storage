# GitHub Copilot Instructions

## Project Overview

This repository contains Infrastructure-as-Code (IaC) for deploying **Azure Front Door Premium with WAF** connected to a **private Azure Blob Storage** endpoint. The solution routes traffic through Azure Front Door Premium (with a Web Application Firewall policy) via a custom domain, route, and origin group to a storage account exposed only through a private endpoint inside a Virtual Network with private DNS resolution.

### Deployed Resources

- **Azure Front Door Premium** – global load balancer with WAF
- **WAF Policy** – prevention-mode policy attached to the Front Door
- **Custom Domain & Route** – configures the AFD endpoint routing rules
- **Origin Group & Origin** – points to the storage account private endpoint
- **Azure Storage Account** – blob storage, public network access disabled
- **Private Endpoint** – connects the storage account into the VNet
- **Virtual Network (VNet) + Subnet** – hosts the private endpoint
- **Private DNS Zone** (`privatelink.blob.core.windows.net`) + VNet link – resolves the storage account private IP
- **AFD Private Link Approval** – approves the private link connection from AFD to the storage account

### IaC Tooling

Both **Bicep** and **Terraform** implementations are maintained in parallel under:

```
infra/
  bicep/       # Azure Bicep modules and main deployment files
  terraform/   # Terraform root module and child modules
```

### CI/CD

GitHub Actions workflows live in `.github/workflows/` and handle linting, validation, and deployment for both Bicep and Terraform.

---

## Coding Standards & Conventions

### General

- Follow the **Azure Well-Architected Framework (WAF)** and **Cloud Adoption Framework (CAF)** naming conventions for all Azure resources.
- All resource names should use the CAF recommended abbreviation prefix (e.g., `afd-`, `st`, `pe-`, `vnet-`, `snet-`, `pdnsz-`, `waf-`).
- Parameterize environment (`dev`, `staging`, `prod`), location, and workload name in every module/template.
- Never hard-code subscription IDs, tenant IDs, or credentials.
- Store sensitive outputs (keys, connection strings) in Azure Key Vault; never in state files or workflow logs.

### Bicep

- Use **modules** for logical grouping (networking, storage, frontDoor, dns).
- Follow [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) patterns where applicable.
- Every module must include a `metadata` block with `name`, `description`, and `owner`.
- Use `@description()` decorators on every parameter and output.
- Target API versions should be recent and stable (prefer GA over preview).
- Use `existing` references rather than embedding resource IDs as raw strings.

### Terraform

- Use **child modules** under `infra/terraform/modules/` for each logical resource group.
- Follow the [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) best practices.
- All resources must include a `tags` argument populated from a local `common_tags` map.
- Use `terraform.tfvars` for environment-specific values; never commit secrets.
- State must be stored in **Azure Blob Storage** with state locking via Azure Blob lease.
- Pin provider versions in `required_providers`.

### GitHub Actions

- Workflows must use **OIDC (Workload Identity Federation)** for Azure authentication – no stored secrets for Azure credentials.
- Separate jobs for `lint`, `validate`, and `deploy`.
- Use `environment` protection rules for production deployments.
- Cache tool installations (Bicep CLI, Terraform) where possible.
- Emit workflow summaries with deployment results.

### Security

- Storage account must have `publicNetworkAccess: Disabled` and `allowBlobPublicAccess: false`.
- WAF policy must be in **Prevention** mode for production environments.
- Private endpoint subnet must have `privateEndpointNetworkPolicies: Disabled` (required by Azure).
- Use **Managed Identities** (system or user-assigned) instead of service principals with secrets wherever possible.

---

## Repository Structure (Target)

```
.
├── .github/
│   ├── agents/             # Copilot custom coding agents
│   ├── workflows/          # GitHub Actions workflows
│   └── copilot-instructions.md
├── infra/
│   ├── bicep/
│   │   ├── modules/        # Reusable Bicep modules
│   │   └── main.bicep      # Entry-point deployment
│   └── terraform/
│       ├── modules/        # Reusable Terraform child modules
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── providers.tf
└── README.md
```

---

## References

- [Azure Front Door Private Link to Storage](https://learn.microsoft.com/azure/frontdoor/private-link)
- [Azure Verified Modules – Bicep](https://azure.github.io/Azure-Verified-Modules/)
- [CAF Naming Convention](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [GitHub Actions OIDC with Azure](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
