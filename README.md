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

## CI/CD Setup

The GitHub Actions workflow automates linting and deployment of both the Bicep and Terraform tracks. Authentication to Azure uses **OIDC / Workload Identity Federation** — no client secrets or long-lived credentials are ever stored in GitHub.

### Overview

- **Single workflow file:** `.github/workflows/deploy.yml`
- **Bicep** deploys to its own Azure resource group; **Terraform** deploys to a separate resource group — both can coexist in the same subscription without naming conflicts.
- **No stored secrets:** the workflow exchanges GitHub's short-lived OIDC token for an Azure access token at runtime.
- **Triggers:** `push` to `main` (full deploy), `pull_request` (lint / validate only), `workflow_dispatch` (manual deploy).

---

### Step 1 — Create an Azure Managed Identity

Create a **User-Assigned Managed Identity** that GitHub Actions will impersonate.

```bash
# Create a resource group to hold the managed identity (or use an existing one)
az group create --name rg-github-oidc --location eastus

# Create the User-Assigned Managed Identity
az identity create \
  --name mi-github-afd-blob-storage \
  --resource-group rg-github-oidc \
  --location eastus
```

Capture the `clientId` and `principalId` for use in later steps:

```bash
CLIENT_ID=$(az identity show \
  --name mi-github-afd-blob-storage \
  --resource-group rg-github-oidc \
  --query clientId -o tsv)

PRINCIPAL_ID=$(az identity show \
  --name mi-github-afd-blob-storage \
  --resource-group rg-github-oidc \
  --query principalId -o tsv)
```

Assign the **Contributor** role so the identity can create resource groups and resources:

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

> **Least-privilege tip:** For tighter security, scope the role assignment to the specific resource groups (`rg-afdblobbic-dev-eus2` for Bicep and your Terraform RG) rather than the full subscription. Subscription-level Contributor is simpler for initial setup.

---

### Step 2 — Configure Federated Credentials (OIDC)

Federated credentials allow GitHub Actions to exchange a short-lived OIDC token for an Azure access token. No password or client secret is ever stored in GitHub or Azure.

Create **three** federated credentials — one for `push` to `main`, one for `pull_request`, and one for `workflow_dispatch` (environment-scoped):

```bash
# Credential for push to main (used by deploy jobs)
az identity federated-credential create \
  --name fc-github-main \
  --identity-name mi-github-afd-blob-storage \
  --resource-group rg-github-oidc \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:christopherhouse/Afd-Blob-Storage:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"

# Credential for pull requests (used by lint jobs that also call azure/login)
az identity federated-credential create \
  --name fc-github-pr \
  --identity-name mi-github-afd-blob-storage \
  --resource-group rg-github-oidc \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:christopherhouse/Afd-Blob-Storage:pull_request" \
  --audiences "api://AzureADTokenExchange"

# Credential for manual workflow_dispatch runs (environment-scoped)
az identity federated-credential create \
  --name fc-github-dispatch \
  --identity-name mi-github-afd-blob-storage \
  --resource-group rg-github-oidc \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:christopherhouse/Afd-Blob-Storage:environment:dev" \
  --audiences "api://AzureADTokenExchange"
```

> Replace `christopherhouse/Afd-Blob-Storage` with your `{org}/{repo}` if you fork this repository.

The environment-scoped credential (`environment:dev`) is what authorises the **deploy jobs**, which run with `environment: dev` in the workflow.

---

### Step 3 — Set up Terraform State Storage

Terraform state is stored in Azure Blob Storage. The backend uses **OIDC authentication** — no storage account access keys are stored or used.

**Create the state storage resources:**

```bash
# Variables — customise to match your naming convention
TF_STATE_RG="rg-tfstate-dev"
TF_STATE_SA="stafdblobstate$(openssl rand -hex 3)"   # must be globally unique
TF_STATE_CONTAINER="tfstate"

# Resource group for state storage
az group create --name "$TF_STATE_RG" --location eastus

# Storage account — Standard_LRS is appropriate for a dev state backend.
# Use Standard_ZRS or geo-redundant SKUs for production state storage.
az storage account create \
  --name "$TF_STATE_SA" \
  --resource-group "$TF_STATE_RG" \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2

# Blob container for state files
az storage container create \
  --name "$TF_STATE_CONTAINER" \
  --account-name "$TF_STATE_SA" \
  --auth-mode login
```

**Grant the Managed Identity access to the state storage:**

```bash
# Storage Blob Data Contributor allows Terraform to read/write state blobs
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show \
      --name "$TF_STATE_SA" \
      --resource-group "$TF_STATE_RG" \
      --query id -o tsv)"
```

> The `providers.tf` backend block is an empty `backend "azurerm" {}` declaration — all configuration is supplied at runtime via `-backend-config` flags (see the workflow's "Terraform init" step). `use_oidc = true` is passed as a backend-config flag, ensuring no storage account access keys are ever used or stored.

---

### Step 4 — Configure GitHub Repository Variables

All workflow configuration is stored as **GitHub Variables** (not secrets), since none of these values are sensitive credentials.

**Repository-level variables** (Settings → Secrets and variables → Variables → Repository variables):

| Variable | Description | Example |
|---|---|---|
| `AZURE_CLIENT_ID` | Client ID of the Managed Identity | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_SUBSCRIPTION_ID` | Target Azure Subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_LOCATION` | Primary Azure region | `eastus` |

**`dev` environment variables** (Settings → Environments → dev → Environment variables):

| Variable | Description | Example |
|---|---|---|
| `BICEP_RESOURCE_GROUP` | Resource group for the Bicep deployment | `rg-afdblobbic-dev-eus2` |
| `TF_STATE_RESOURCE_GROUP` | Resource group holding TF state storage | `rg-tfstate-dev` |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account name for TF state | `stafdblobstateabc123` |
| `TF_STATE_CONTAINER` | Blob container name for TF state files | `tfstate` |

Use the `gh` CLI to set all variables at once:

```bash
# Retrieve values captured in earlier steps
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
CLIENT_ID=$(az identity show \
  --name mi-github-afd-blob-storage \
  --resource-group rg-github-oidc \
  --query clientId -o tsv)

# Set repository-level variables
gh variable set AZURE_CLIENT_ID       --body "$CLIENT_ID"
gh variable set AZURE_TENANT_ID       --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh variable set AZURE_LOCATION        --body "eastus"

# Set dev environment variables
gh variable set BICEP_RESOURCE_GROUP      --env dev --body "rg-afdblobbic-dev-eus2"
gh variable set TF_STATE_RESOURCE_GROUP   --env dev --body "$TF_STATE_RG"
gh variable set TF_STATE_STORAGE_ACCOUNT  --env dev --body "$TF_STATE_SA"
gh variable set TF_STATE_CONTAINER        --env dev --body "$TF_STATE_CONTAINER"
```

---

### Step 5 — Create the `dev` GitHub Environment

1. In your repository go to **Settings → Environments → New environment**.
2. Name the environment **`dev`**.
3. Optionally configure **protection rules** (e.g., required reviewers) to gate deployments — recommended when promoting this pattern to a production environment.

The workflow deploy jobs reference `environment: dev`, which ties them to this environment's variables and any protection rules you configure.

---

### Resource Naming — Avoiding Clashes

The Bicep and Terraform deployments intentionally use distinct `workloadName` / `workload_name` values so that both tracks can be deployed to the same Azure subscription without storage account or other globally-unique name conflicts:

| IaC Tool | `workloadName` / `workload_name` | Example Storage Account Name |
|---|---|---|
| Bicep | `afdblobbic` | `stafdblobbicdeveus2` |
| Terraform | `afdblobtf` | `stafdblobtfdeveus2` |

Both stacks can coexist in the same subscription simultaneously.

---

## Contributing

See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for coding standards and conventions.

## References

- [Azure Front Door Private Link](https://learn.microsoft.com/azure/frontdoor/private-link)
- [CAF Naming Convention](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Azure Verified Modules – Bicep](https://azure.github.io/Azure-Verified-Modules/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [GitHub Actions OIDC with Azure](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
