# ACME Certificate Request Scripts

This directory contains utility scripts for requesting ACME certificates from Let's Encrypt using DNS-01 validation via Cloudflare DNS. Both Bash and PowerShell implementations are provided for cross-platform compatibility.

## Overview

These scripts automate the process of:
1. Requesting a new certificate from Let's Encrypt
2. Performing DNS-01 validation using Cloudflare DNS
3. Converting the certificate to a password-protected PFX file
4. Optionally importing the certificate to Azure Key Vault

## Prerequisites

### For Bash Script (`request-acme-cert.sh`)

- **Operating System:** Linux, macOS, Windows (WSL/Git Bash)
- **Dependencies:**
  - `bash` 4.0 or later
  - `curl` or `wget`
  - `openssl`
  - `acme.sh` (installed automatically by the script)

### For PowerShell Script (`request-acme-cert.ps1`)

- **Operating System:** Linux, macOS, Windows
- **Dependencies:**
  - PowerShell 7.0 or later (cross-platform)
  - `Posh-ACME` module (installed automatically by the script)

### Common Requirements

- **Cloudflare Account** with:
  - A domain managed by Cloudflare DNS
  - API token with DNS edit permissions
  - Zone read permissions

- **Azure CLI** (optional, for Key Vault import):
  - `az` CLI tool installed and authenticated

## Quick Start

### Bash

```bash
# Basic usage
./request-acme-cert.sh "example.com" "your-cloudflare-api-token"

# Wildcard certificate
./request-acme-cert.sh "*.example.com" "your-cloudflare-api-token"

# With custom PFX password
PFX_PASSWORD="MySecurePassword123!" ./request-acme-cert.sh "example.com" "your-cf-token"

# Using Let's Encrypt staging (for testing)
ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory" \
  ./request-acme-cert.sh "test.example.com" "your-cf-token"
```

### PowerShell

```powershell
# Basic usage
./request-acme-cert.ps1 -CertificateName "example.com" -CloudflareApiToken "your-token"

# Wildcard certificate
./request-acme-cert.ps1 -CertificateName "*.example.com" -CloudflareApiToken "your-token"

# With custom PFX password
$password = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force
./request-acme-cert.ps1 -CertificateName "example.com" -CloudflareApiToken "your-token" -PfxPassword $password

# Using Let's Encrypt staging (for testing)
./request-acme-cert.ps1 -CertificateName "test.example.com" -CloudflareApiToken "your-token" -AcmeServer "LetsEncrypt-Staging"

# Force renewal of existing certificate
./request-acme-cert.ps1 -CertificateName "example.com" -CloudflareApiToken "your-token" -Force
```

## Creating a Cloudflare API Token

1. Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Go to **My Profile** → **API Tokens**
3. Click **Create Token**
4. Use the **Edit zone DNS** template or create a custom token with:
   - **Permissions:**
     - `Zone` → `DNS` → `Edit`
     - `Zone` → `Zone` → `Read`
   - **Zone Resources:**
     - `Include` → `Specific zone` → Select your domain
5. Click **Continue to summary** → **Create Token**
6. **Copy the token** — it will only be shown once

## Script Parameters

### Bash Script

| Parameter | Description | Required | Default |
|---|---|---|---|
| `certificate-name` | Domain name for the certificate | Yes | - |
| `cloudflare-api-token` | Cloudflare API token | Yes | - |

**Environment Variables:**

| Variable | Description | Default |
|---|---|---|
| `ACME_SERVER` | ACME server URL | Let's Encrypt production |
| `ACME_EMAIL` | Email for ACME account | `admin@example.com` |
| `KEY_ALGORITHM` | Key algorithm (`ec-256`, `ec-384`, `rsa2048`, `rsa3072`, `rsa4096`) | `ec-256` |
| `PFX_PASSWORD` | Password for PFX file | Auto-generated |
| `OUTPUT_DIR` | Output directory for PFX file | `./certificates` |

### PowerShell Script

| Parameter | Description | Required | Default |
|---|---|---|---|
| `-CertificateName` | Domain name for the certificate | Yes | - |
| `-CloudflareApiToken` | Cloudflare API token | Yes | - |
| `-AcmeServer` | ACME server (`LetsEncrypt`, `LetsEncrypt-Staging`) | No | `LetsEncrypt` |
| `-PfxPassword` | Password for PFX file (SecureString) | No | Auto-generated |
| `-OutputDirectory` | Output directory for PFX file | No | `./certificates` |
| `-ContactEmail` | Email for ACME account | No | `admin@example.com` |
| `-Force` | Force renewal of existing certificate | No | `false` |

## Output

Both scripts produce the following outputs:

1. **PFX File:** `./certificates/<certificate-name>.pfx`
   - Password-protected PKCS#12 archive
   - Contains certificate, private key, and chain

2. **Certificate Metadata:**
   - Subject, issuer, validity dates, thumbprint
   - PFX password (store securely!)

3. **Console Output:**
   - Step-by-step progress
   - Validation results
   - Import command for Azure Key Vault

## Importing to Azure Key Vault

After obtaining the PFX file, import it to Azure Key Vault:

```bash
# Using Azure CLI
az keyvault certificate import \
  --vault-name <key-vault-name> \
  --name <certificate-name> \
  --file ./certificates/<certificate-name>.pfx \
  --password '<pfx-password>'
```

```powershell
# Using PowerShell
$password = ConvertTo-SecureString "<pfx-password>" -AsPlainText -Force
Import-AzKeyVaultCertificate `
  -VaultName "<key-vault-name>" `
  -Name "<certificate-name>" `
  -FilePath "./certificates/<certificate-name>.pfx" `
  -Password $password
```

## Certificate Lifecycle

### Renewal

Let's Encrypt certificates are valid for **90 days**. Renew certificates before they expire:

**Bash:**
```bash
# Renewal is automatic - just re-run the script
./request-acme-cert.sh "example.com" "your-cloudflare-api-token"
```

**PowerShell:**
```powershell
# Use -Force to renew an existing certificate
./request-acme-cert.ps1 -CertificateName "example.com" -CloudflareApiToken "your-token" -Force
```

### Automated Renewal

Set up a cron job (Linux/macOS) or scheduled task (Windows) to automate renewal:

**Linux cron example:**
```bash
# Run every 60 days at 3 AM
0 3 */60 * * /path/to/request-acme-cert.sh "example.com" "$CLOUDFLARE_TOKEN" && \
  az keyvault certificate import --vault-name my-vault --name example-com \
    --file /path/to/certificates/example.com.pfx --password "$PFX_PASSWORD"
```

**PowerShell scheduled task example:**
```powershell
$action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-File C:\Scripts\request-acme-cert.ps1 -CertificateName 'example.com' -CloudflareApiToken '$env:CLOUDFLARE_TOKEN' -Force"
$trigger = New-ScheduledTaskTrigger -Daily -At 3am -DaysInterval 60
Register-ScheduledTask -TaskName "RenewAcmeCert" -Action $action -Trigger $trigger
```

## Troubleshooting

### Common Issues

#### 1. DNS Validation Fails

**Symptom:** Certificate request fails with DNS validation error

**Solutions:**
- Verify the Cloudflare API token has DNS edit permissions
- Check that the domain is active in Cloudflare
- Ensure DNS propagation is complete (may take a few minutes)
- Try using Let's Encrypt staging server first to test

#### 2. Rate Limits

**Symptom:** Error message about rate limits

**Solutions:**
- Let's Encrypt has rate limits: 50 certificates per domain per week
- Use the staging server for testing: `ACME_SERVER=staging` (Bash) or `-AcmeServer LetsEncrypt-Staging` (PowerShell)
- Wait for the rate limit window to reset

#### 3. Wildcard Certificate Issues

**Symptom:** Wildcard certificate request fails

**Solutions:**
- Ensure the domain format is correct: `*.example.com` (not `example.com`)
- Quote the domain name in the command line: `"*.example.com"`
- Wildcard certificates require DNS-01 validation (HTTP-01 doesn't work)

#### 4. PFX Conversion Fails

**Symptom:** Certificate issued but PFX creation fails

**Solutions:**
- Verify OpenSSL is installed and in PATH
- Check file permissions in the output directory
- Ensure sufficient disk space

### Debug Mode

**Bash:**
```bash
# Enable debug output
set -x
./request-acme-cert.sh "example.com" "your-token"
```

**PowerShell:**
```powershell
# Enable verbose output
./request-acme-cert.ps1 -CertificateName "example.com" -CloudflareApiToken "your-token" -Verbose
```

## Security Best Practices

1. **Never commit credentials to version control**
   - Use environment variables or secret management systems
   - Add `*.pfx` and `*.key` to `.gitignore`

2. **Protect PFX passwords**
   - Store passwords in Azure Key Vault or similar
   - Use auto-generated passwords when possible
   - Rotate passwords regularly

3. **Limit API token permissions**
   - Use zone-scoped tokens (not account-wide)
   - Grant only DNS edit permissions
   - Rotate tokens periodically

4. **Secure certificate storage**
   - Store PFX files in encrypted storage
   - Use Azure Key Vault for production certificates
   - Delete local PFX files after importing to Key Vault

5. **Use staging for testing**
   - Test certificate requests with Let's Encrypt staging server
   - Avoid hitting production rate limits during development

## Integration with Azure Front Door

After obtaining the certificate, configure it for Azure Front Door:

1. **Import to Key Vault** (see above)
2. **Grant Front Door access to Key Vault:**
   ```bash
   # Get the Front Door resource principal ID
   AFD_PRINCIPAL_ID=$(az afd profile show \
     --profile-name <afd-profile-name> \
     --resource-group <resource-group> \
     --query identity.principalId -o tsv)

   # Grant certificate permissions
   az keyvault set-policy \
     --name <key-vault-name> \
     --object-id $AFD_PRINCIPAL_ID \
     --certificate-permissions get list
   ```

3. **Configure custom domain in Front Door:**
   - Add custom domain to AFD endpoint
   - Select certificate from Key Vault
   - Validate domain ownership
   - Update DNS records

## Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [acme.sh Documentation](https://github.com/acmesh-official/acme.sh)
- [Posh-ACME Documentation](https://poshac.me/)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Azure Front Door Custom Domains](https://learn.microsoft.com/azure/frontdoor/front-door-custom-domain)
- [Azure Key Vault Certificates](https://learn.microsoft.com/azure/key-vault/certificates/)

## Contributing

Improvements and bug fixes are welcome! Please follow the repository's coding standards:

- Use shellcheck for bash scripts
- Use PSScriptAnalyzer for PowerShell scripts
- Follow existing code style and formatting
- Add comments for complex logic
- Update documentation for new features

## License

This project is licensed under the MIT License. See the [LICENSE](/LICENSE) file in the repository root.
