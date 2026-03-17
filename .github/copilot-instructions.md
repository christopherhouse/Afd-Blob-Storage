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

## Available MCP Servers

The following Model Context Protocol (MCP) servers are available to all agents in this repository. **Always prefer these tools over relying on training-data knowledge** when looking up service documentation, API schemas, provider resources, or code examples — they return current, authoritative content.

### Microsoft Learn MCP Server (`microsoft-docs`)

Provides direct access to official Microsoft and Azure documentation.

| Tool | When to Use |
|---|---|
| `microsoft_docs_search(query)` | Find Azure service docs, CAF/WAF guidance, API reference, how-to articles. Returns up to 10 relevant chunks. |
| `microsoft_code_sample_search(query, language?)` | Retrieve official code examples from MS Learn (Bicep, ARM, PowerShell, Azure CLI, etc.). Specify `language` for better results. |
| `microsoft_docs_fetch(url)` | Fetch the **full content** of a specific MS Learn page as markdown when a search result is incomplete or you need the complete procedure. |

**Use MS Learn MCP for:**
- Azure resource property reference (e.g., valid values for `publicNetworkAccess`, WAF rule set versions)
- CAF naming convention lookups
- Front Door, WAF, Private Endpoint, Storage configuration guidance
- Required RBAC roles and permissions
- Bicep `@description` decorator examples and AVM module patterns
- Troubleshooting guidance (Private Link approval, DNS resolution, WAF false positives)

**Usage pattern:**
```
1. microsoft_docs_search("azure front door private link blob storage")
2. If a result page looks highly relevant → microsoft_docs_fetch(<url>) for full detail
```

### Context7 MCP Server (`context7`)

Provides up-to-date library and SDK documentation with real code snippets, sourced from official registries and documentation sites.

| Tool | When to Use |
|---|---|
| `context7-resolve-library-id(libraryName, query)` | Resolve a package/library name to a Context7 library ID. **Must be called first** before querying documentation. |
| `get-library-docs(libraryId, topic?, tokens?)` | Fetch documentation and code examples for the resolved library. |

**Use Context7 MCP for:**
- **Terraform AzureRM provider** resource schemas and argument references (`hashicorp/terraform-provider-azurerm`)
- **Bicep / Azure Verified Modules (AVM)** registry patterns
- **GitHub Actions** — finding correct action versions, input/output schemas (e.g., `azure/login`, `hashicorp/setup-terraform`)
- Any npm, pip, or other package documentation needed during workflow authoring

**Usage pattern (two-step — always follow this order):**
```
1. context7-resolve-library-id("azurerm", "azurerm_cdn_frontdoor_profile resource")
   → returns libraryId, e.g. "/hashicorp/terraform-provider-azurerm"
2. get-library-docs("/hashicorp/terraform-provider-azurerm", topic="cdn_frontdoor_profile")
```

> **Note:** Never skip step 1. The `libraryId` from `resolve-library-id` is required for `get-library-docs`. If `resolve-library-id` returns multiple matches, select the one with the highest benchmark score and most relevant description.

---

## Working with Agents

This repository includes a set of **custom Copilot agents** under `.github/agents/`. Each agent is a domain specialist. Use them together in a structured workflow — starting with the Planning Agent — to deliver well-architected, consistent results.

### Always Start with the Planning Agent

> **Rule: Begin every new feature, module, or significant change by engaging the Planning Agent first.**

The Planning Agent (`planning.md`) breaks down requirements into a phased, dependency-ordered task list before any code is written. This prevents wasted effort caused by building things in the wrong order (e.g., deploying an origin before the storage account exists, or writing Bicep before the resource model is agreed upon).

```
User request
    │
    ▼  (1) Always first
Planning Agent        ← decompose, sequence, identify dependencies
    │
    ▼  (2) Validate design
Azure Agent           ← WAF/CAF review, App Reg + azcopy guidance
    │
    ▼  (3) Implement IaC
Bicep Agent and/or Terraform Agent
    │
    ▼  (4) Wire up CI/CD
GitHub Actions Agent
    │
    ▼  (5) Document
Documentation Agent
```

### Agent Roster

| Agent File | Specialisation | Engage When |
|---|---|---|
| `planning.md` | Phased task decomposition, dependency mapping, ADRs | **Always first** — for any new work, feature, or cross-cutting change |
| `azure.md` | WAF/CAF alignment, RBAC, App Registrations, azcopy | Reviewing Azure resource config, auth patterns, security posture |
| `bicep.md` | Bicep module authoring, AVM patterns, linting | Writing or reviewing any file under `infra/bicep/` |
| `terraform.md` | Terraform HCL authoring, AzureRM provider, state | Writing or reviewing any file under `infra/terraform/` |
| `github-actions.md` | CI/CD workflows, OIDC auth, environment protection | Writing or reviewing files under `.github/workflows/` |
| `documentation.md` | README files, Mermaid diagrams, parameter tables | Creating or updating any documentation |

### Recommended Workflow

1. **Planning Agent** – Describe the goal; receive a phased task list with dependencies and acceptance criteria.
2. **Azure Agent** – Validate the proposed resource design against WAF/CAF; confirm RBAC, naming, and security settings before writing IaC.
3. **Bicep Agent and/or Terraform Agent** – Implement the agreed design in IaC.
4. **GitHub Actions Agent** – Add or update CI/CD workflows to lint, validate, and deploy the new IaC.
5. **Documentation Agent** – Update README files, architecture diagrams, and parameter tables to reflect the changes.

> You do not need to engage every agent for every task. For a small change (e.g., adjusting a WAF rule), skip directly to the Azure Agent and the relevant IaC agent. Use the Planning Agent any time scope or sequencing is unclear.

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
