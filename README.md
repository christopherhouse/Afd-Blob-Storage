# Azure Front Door Premium → Private Blob Storage

This repository contains Infrastructure-as-Code (IaC) — in both **Azure Bicep** and **Terraform** — for deploying Azure Front Door Premium with WAF that routes to an Azure Blob Storage account exposed exclusively via a Private Endpoint.

> **Status:** ✅ Fully implemented — foundational infrastructure, AFD Premium, and WAF integration deployed via both Bicep and Terraform.

## Architecture Overview

![Architecture Diagram](docs/architecture.svg)

### Deployed Resources

| Resource | Bicep Module | Terraform Module | Purpose |
|---|---|---|---|
| Azure Front Door Premium | `modules/frontDoor/frontDoor.bicep` | `modules/front_door/` | Global load balancer, TLS termination, caching |
| WAF Policy (Prevention Mode) | `modules/frontDoor/wafPolicy.bicep` | `modules/front_door/` | OWASP + Bot Manager managed rule sets |
| Custom Domain + Route | `modules/frontDoor/frontDoor.bicep` | `modules/front_door/` | Routes requests to the blob origin |
| Origin Group + Origin | `modules/frontDoor/frontDoor.bicep` | `modules/front_door/` | Points AFD to storage via Private Link |
| Storage Account | `modules/storage/storageAccount.bicep` | `modules/storage/` | Blob storage, public network access disabled |
| Private Endpoint | `modules/networking/privateEndpoint.bicep` | `modules/private_endpoint/` | Connects storage into the VNet |
| Virtual Network + Subnet | `modules/networking/virtualNetwork.bicep` | `modules/networking/` | Hosts the private endpoint NIC |
| Private DNS Zone | `modules/networking/privateDnsZone.bicep` | `modules/private_dns/` | Resolves storage FQDN to private IP |
| Log Analytics Workspace | `modules/monitoring/logAnalyticsWorkspace.bicep` | `modules/monitoring/` | Centralised diagnostic logs and metrics |

## Foundational Infrastructure

The following foundational resources are implemented in both `src/bicep/` and `src/terraform/`:

| Resource | Module Path (Bicep) | Module Path (Terraform) | Key Security Settings |
|---|---|---|---|
| Azure Front Door Premium | `modules/frontDoor/frontDoor.bicep` | `modules/front_door/` | Premium SKU, Private Link origin to blob storage |
| WAF Policy | `modules/frontDoor/wafPolicy.bicep` | `modules/front_door/` | Prevention mode; OWASP DRS 2.1 + Bot Manager 1.0 |
| Virtual Network + PE Subnet | `modules/networking/virtualNetwork.bicep` | `modules/networking/` | Private endpoint network policies disabled on PE subnet |
| Storage Account | `modules/storage/storageAccount.bicep` | `modules/storage/` | `publicNetworkAccess: Disabled`, `allowBlobPublicAccess: false`, TLS 1.2 minimum |
| Log Analytics Workspace | `modules/monitoring/logAnalyticsWorkspace.bicep` | `modules/monitoring/` | 30-day retention; receives diagnostic logs from all resources |

All modules use **Azure Verified Modules (AVM)** as the implementation foundation, with the exception of the Terraform Front Door module which uses native `azurerm_cdn_frontdoor_*` resources due to a lifecycle issue in the AVM CDN module (v0.1.9) that causes a destroy/recreate cycle on every apply. Environment-specific values are supplied via `src/bicep/parameters/main.dev.bicepparam` (Bicep) and `src/terraform/terraform.tfvars` (Terraform).

---

## Post-Deployment: Approve the AFD Private Link Connection

After deploying (via either Bicep or Terraform), the Private Link connection from Azure Front Door to the storage account starts in a **Pending** state. **Traffic will not flow through AFD to storage until this connection is explicitly approved.**

### Why approval is required

Azure Front Door initiates a Private Link connection to the storage account's private endpoint. Because this connection crosses trust boundaries, Azure requires a storage account owner to manually approve it before traffic can flow.

### Approve via Azure Portal

1. Navigate to your **Storage Account** in the Azure Portal.
2. Select **Networking** → **Private endpoint connections**.
3. Find the connection with a description referencing **Azure Front Door** (the status will show **Pending**).
4. Select the connection and click **Approve**.
5. Confirm the approval in the dialog.

### Approve via Azure CLI

```bash
# Get the pending private endpoint connection name
az storage account show \
  --name <storage-account-name> \
  --resource-group <resource-group-name> \
  --query "privateEndpointConnections[?privateLinkServiceConnectionState.status=='Pending'].name" \
  -o tsv

# Approve the connection (substitute the name returned above)
az storage account private-endpoint-connection approve \
  --account-name <storage-account-name> \
  --resource-group <resource-group-name> \
  --name <connection-name>
```

> **Note:** DNS propagation and AFD origin health checks may take a few minutes to complete after approval. Monitor the AFD origin health in the Azure Portal under **Azure Front Door → Origin groups** to confirm the origin transitions to a **Healthy** state.

---

## AFD Health Probes

Azure Front Door uses health probes to determine whether each origin in an origin group is available and healthy. Understanding how health probes work with private blob storage origins is critical to a successful deployment.

### How Health Probes Work

When enabled (`enableFrontDoorHealthProbe = true` in Bicep / `enable_front_door_health_probe = true` in Terraform), the AFD origin group is configured with a health probe that periodically sends an HTTPS `GET` request to:

```
/health/health.txt
```

The probe interval is **100 seconds** (Bicep) or **30 seconds** (Terraform) — the values differ because each IaC track can be tuned independently; adjust the interval in the respective module to match your availability requirements. The origin group's load balancer evaluates health based on a sample of **4 probes**, requiring **3 successful responses** within a **50 ms additional-latency window** to consider the origin healthy.

When the health probe is **disabled**, the origin group's health probe settings are omitted entirely (`healthProbeSettings: null` in Bicep, empty `health_probe {}` block in Terraform), and AFD assumes the origin is always healthy.

### Why Anonymous Blob Access Is Required

**Azure Front Door does not support Managed Identity authentication over Private Link connections for health probes.** Because the storage account has public network access disabled, the health probe traffic traverses the Private Link, where MI-based authentication is unavailable.

To work around this limitation, the deployment:

1. **Creates a `health` container** in the storage account with **anonymous blob-level read access** (`publicAccess: 'Blob'`). This container is only created when the health probe is enabled.
2. **Sets `allowBlobPublicAccess: true`** (or `allow_nested_items_to_be_public = true` in Terraform) at the storage account level — but only when the health probe is enabled. This is required by Azure to permit anonymous access on individual containers.
3. **Keeps the `upload` container fully private** — anonymous access is scoped to the `health` container only.

After deployment, you must upload a small `health.txt` file to the `health` container so the probe has a resource to check:

```bash
echo "healthy" > /tmp/health.txt
az storage blob upload \
  --account-name <storage-account-name> \
  --container-name health \
  --name health.txt \
  --file /tmp/health.txt \
  --auth-mode login
```

> **Security note:** Only the `health` container is anonymously readable. The `upload` container — where actual content is stored — remains fully private and requires authentication for all operations. If you prefer not to allow any anonymous access, set `enableFrontDoorHealthProbe = false` and AFD will skip health checks entirely (treating the origin as always healthy).

---

## Uploading Content with azcopy

Because the storage account has public network access disabled and shared-key access disabled, uploading content requires authentication via Microsoft Entra ID (Azure AD). The recommended approach for automation is to use **azcopy** with a **service principal**.

### Prerequisites

- [azcopy](https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10) ≥ 10.x installed
- A service principal (app registration) with the **Storage Blob Data Contributor** role assigned on the target storage account or the `upload` container
- The service principal's tenant ID, application (client) ID, and client secret (or certificate)

### Authenticate azcopy with a Service Principal

Set the required environment variables before running azcopy:

```bash
export AZCOPY_SPA_CLIENT_SECRET="<service-principal-client-secret>"
export AZCOPY_TENANT_ID="<azure-ad-tenant-id>"

azcopy login --service-principal --application-id "<service-principal-app-id>"
```

### Upload Files

When uploading to a storage account that is fronted by Azure Front Door with a custom domain, you must include two additional arguments:

| Argument | Value | Why |
|---|---|---|
| `--from-to` | `LocalBlob` | Tells azcopy the transfer direction explicitly (local file system → Azure Blob Storage). Required for private storage accounts where automatic endpoint detection fails due to disabled public network access. |
| `--trusted-microsoft-suffixes` | Your AFD endpoint hostname or custom domain (e.g., `blob.christopher-house.com`) | Allows azcopy to trust the non-standard hostname for authentication token scoping. Without this flag, azcopy may refuse to send credentials to a hostname that doesn't match `*.blob.core.windows.net`. |

**Upload a single file:**

```bash
azcopy copy "./my-file.txt" \
  "https://<storage-account-name>.blob.core.windows.net/upload/my-file.txt" \
  --from-to LocalBlob \
  --trusted-microsoft-suffixes "<your-afd-or-custom-domain>"
```

**Upload an entire directory:**

```bash
azcopy copy "./my-folder" \
  "https://<storage-account-name>.blob.core.windows.net/upload/" \
  --from-to LocalBlob \
  --trusted-microsoft-suffixes "<your-afd-or-custom-domain>" \
  --recursive
```

> **Tip:** If your storage account is configured with a custom domain via Azure Front Door (e.g., `blob.christopher-house.com`), use that domain as the `--trusted-microsoft-suffixes` value. If you are only using the default `.azurefd.net` endpoint, use that hostname instead.

> **Note:** Because `shared_access_key_enabled` is set to `false` on the storage account, SAS tokens and storage account keys cannot be used for authentication. Service principal or managed identity authentication via Microsoft Entra ID is the only supported method.

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
│   ├── workflows/               # GitHub Actions CI/CD workflows
│   └── copilot-instructions.md  # Project-wide Copilot instructions
├── src/
│   ├── bicep/                   # Bicep modules + main deployment
│   │   ├── modules/
│   │   │   ├── frontDoor/       # AFD Premium profile + WAF policy (AVM)
│   │   │   ├── identity/       # User Assigned Managed Identity + RBAC (AVM)
│   │   │   ├── monitoring/      # Log Analytics Workspace (AVM)
│   │   │   ├── networking/      # VNet + PE subnet (AVM)
│   │   │   └── storage/         # Storage account (AVM)
│   │   ├── parameters/
│   │   │   └── main.dev.bicepparam
│   │   └── main.bicep
│   └── terraform/               # Terraform root module + child modules
│       ├── modules/
│       │   ├── front_door/      # AFD Premium profile + WAF policy (native azurerm)
│       │   ├── monitoring/      # Log Analytics Workspace (AVM)
│       │   ├── networking/      # VNet + PE subnet (AVM)
│       │   ├── private_dns/     # Private DNS zone + VNet link (AVM)
│       │   ├── private_endpoint/ # Private endpoint + NIC (AVM)
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
| `TF_RESOURCE_GROUP` | Pre-existing resource group for the Terraform deployment | `rg-afdblobtf-dev` |
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
gh variable set TF_RESOURCE_GROUP         --env dev --body "rg-afdblobtf-dev"
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
