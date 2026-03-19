#!/usr/bin/env pwsh
# ==============================================================================
# ACME Certificate Request Script (PowerShell)
# ==============================================================================
# Description: Requests a new ACME certificate from Let's Encrypt using DNS01
#              validation via Cloudflare DNS. Converts the certificate to a
#              password-protected PFX file.
#
# Author: Auto-generated for Afd-Blob-Storage repository
# License: MIT
#
# Prerequisites:
#   - PowerShell 7.0+ (cross-platform)
#   - Posh-ACME module (installed automatically if missing)
#   - Valid Cloudflare API token with DNS edit permissions
#
# Usage:
#   ./request-acme-cert.ps1 -CertificateName <name> -CloudflareApiToken <token>
#
# Example:
#   ./request-acme-cert.ps1 -CertificateName "example.com" -CloudflareApiToken "your-token"
#
# Output:
#   - <certificate-name>.pfx - Password-protected PFX file
#   - Certificate metadata stored in Posh-ACME directory
# ==============================================================================

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Domain name for the certificate")]
    [ValidateNotNullOrEmpty()]
    [string]$CertificateName,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Cloudflare API token with DNS edit permissions")]
    [ValidateNotNullOrEmpty()]
    [string]$CloudflareApiToken,

    [Parameter(Mandatory = $false, HelpMessage = "ACME server URL")]
    [ValidateSet('LetsEncrypt', 'LetsEncrypt-Staging')]
    [string]$AcmeServer = 'LetsEncrypt',

    [Parameter(Mandatory = $false, HelpMessage = "Password for PFX file (auto-generated if not provided)")]
    [SecureString]$PfxPassword,

    [Parameter(Mandatory = $false, HelpMessage = "Output directory for PFX file")]
    [string]$OutputDirectory = (Join-Path $PWD "certificates"),

    [Parameter(Mandatory = $false, HelpMessage = "Email address for ACME account registration")]
    [string]$ContactEmail = "admin@example.com",

    [Parameter(Mandatory = $false, HelpMessage = "Force certificate renewal even if valid")]
    [switch]$Force
)

# ==============================================================================
# Module and Error Handling Setup
# ==============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ==============================================================================
# Functions
# ==============================================================================

function Write-ColorOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    switch ($Level) {
        'Info' {
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor Blue
            Write-Host "[INFO] " -NoNewline -ForegroundColor Cyan
            Write-Host $Message
        }
        'Success' {
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor Blue
            Write-Host "[SUCCESS] " -NoNewline -ForegroundColor Green
            Write-Host $Message
        }
        'Warning' {
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor Blue
            Write-Host "[WARNING] " -NoNewline -ForegroundColor Yellow
            Write-Host $Message -ForegroundColor Yellow
        }
        'Error' {
            Write-Host "[$timestamp] " -NoNewline -ForegroundColor Blue
            Write-Host "[ERROR] " -NoNewline -ForegroundColor Red
            Write-Host $Message -ForegroundColor Red
        }
    }
}

function Test-PoshAcmeModule {
    [CmdletBinding()]
    param()

    Write-ColorOutput "Checking for Posh-ACME module..." -Level Info

    $module = Get-Module -ListAvailable -Name Posh-ACME | Select-Object -First 1

    if (-not $module) {
        Write-ColorOutput "Posh-ACME module not found. Installing..." -Level Warning

        try {
            Install-Module -Name Posh-ACME -Scope CurrentUser -Force -AllowClobber
            Write-ColorOutput "Posh-ACME module installed successfully" -Level Success
        }
        catch {
            Write-ColorOutput "Failed to install Posh-ACME module: $_" -Level Error
            throw
        }
    }
    else {
        Write-ColorOutput "Posh-ACME module version $($module.Version) found" -Level Success
    }

    # Import the module
    Import-Module Posh-ACME -ErrorAction Stop
}

function Test-DomainNameFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName
    )

    # Basic domain name validation (supports wildcards)
    $domainPattern = '^(\*\.)?([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

    if ($DomainName -notmatch $domainPattern) {
        Write-ColorOutput "Domain name '$DomainName' may not be a valid format" -Level Warning
        Write-ColorOutput "Expected format: example.com or *.example.com" -Level Warning
        return $false
    }

    return $true
}

function Test-CloudflareApiToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiToken
    )

    # Basic token format validation
    if ($ApiToken.Length -lt 40) {
        Write-ColorOutput "Cloudflare API token appears to be too short" -Level Warning
        Write-ColorOutput "Expected: 40+ character alphanumeric string" -Level Warning
        return $false
    }

    return $true
}

function New-RandomPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Length = 32
    )

    # Generate cryptographically secure random password
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()

    $password = [Convert]::ToBase64String($bytes)
    return ConvertTo-SecureString -String $password -AsPlainText -Force
}

function Request-AcmeCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$CfToken,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Email,

        [Parameter(Mandatory = $false)]
        [switch]$ForceRenewal
    )

    Write-ColorOutput "Requesting certificate for: $Domain" -Level Info
    Write-ColorOutput "Using ACME server: $Server" -Level Info

    try {
        # Set ACME server
        Set-PAServer -DirectoryUrl $Server

        # Get or create ACME account
        $account = Get-PAAccount -Contact $Email -ErrorAction SilentlyContinue

        if (-not $account) {
            Write-ColorOutput "Creating new ACME account with email: $Email" -Level Info
            $account = New-PAAccount -Contact $Email -AcceptTOS
        }
        else {
            Write-ColorOutput "Using existing ACME account: $($account.id)" -Level Info
        }

        # Prepare Cloudflare plugin parameters
        $cfParams = @{
            CFToken = $CfToken
        }

        # Check for existing certificate
        $existingOrder = Get-PAOrder -MainDomain $Domain -ErrorAction SilentlyContinue

        if ($existingOrder -and -not $ForceRenewal) {
            Write-ColorOutput "Certificate already exists for $Domain" -Level Warning
            Write-ColorOutput "Use -Force parameter to renew" -Level Warning

            # Check if certificate is still valid
            $cert = Get-PACertificate -MainDomain $Domain -ErrorAction SilentlyContinue
            if ($cert) {
                $expiryDate = $cert.NotAfter
                $daysRemaining = ($expiryDate - (Get-Date)).Days

                if ($daysRemaining -gt 0) {
                    Write-ColorOutput "Certificate is valid for $daysRemaining more days (expires: $expiryDate)" -Level Info
                    return $cert
                }
            }
        }

        # Request certificate using DNS-01 validation via Cloudflare
        Write-ColorOutput "Requesting certificate with DNS-01 validation..." -Level Info

        $certParams = @{
            Domain         = $Domain
            Plugin         = 'Cloudflare'
            PluginArgs     = $cfParams
            Contact        = $Email
            AcceptTOS      = $true
            Force          = $ForceRenewal.IsPresent
            Verbose        = $false
        }

        $certificate = New-PACertificate @certParams

        if ($certificate) {
            Write-ColorOutput "Certificate issued successfully!" -Level Success
            return $certificate
        }
        else {
            throw "Certificate request failed - no certificate returned"
        }
    }
    catch {
        Write-ColorOutput "Failed to request certificate: $_" -Level Error
        throw
    }
}

function Export-CertificateToPfx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Certificate,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [SecureString]$Password,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    Write-ColorOutput "Converting certificate to PFX format..." -Level Info

    try {
        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # Get certificate files from Posh-ACME
        $certFile = $Certificate.CertFile
        $keyFile = $Certificate.KeyFile
        $chainFile = $Certificate.ChainFile

        if (-not (Test-Path $certFile) -or -not (Test-Path $keyFile)) {
            throw "Certificate files not found"
        }

        # Read certificate and key
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFile)
        $keyPem = Get-Content $keyFile -Raw

        # Create X509Certificate2 with private key
        $certWithKey = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPemFile($certFile, $keyFile)

        # Create certificate collection
        $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
        $certCollection.Add($certWithKey)

        # Add chain certificates if available
        if (Test-Path $chainFile) {
            $chainContent = Get-Content $chainFile -Raw
            $chainCerts = $chainContent -split '(?=-----BEGIN CERTIFICATE-----)'

            foreach ($chainCertPem in $chainCerts) {
                if ($chainCertPem -match '-----BEGIN CERTIFICATE-----') {
                    $chainCertBytes = [System.Convert]::FromBase64String(
                        ($chainCertPem -replace '-----BEGIN CERTIFICATE-----' -replace '-----END CERTIFICATE-----' -replace '\s', '')
                    )
                    $chainCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($chainCertBytes)
                    $certCollection.Add($chainCert)
                }
            }
        }

        # Convert SecureString password to plain text for export
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        # Export to PFX
        $pfxBytes = $certCollection.Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12,
            $plainPassword
        )

        [System.IO.File]::WriteAllBytes($OutputPath, $pfxBytes)

        # Clear sensitive data
        $plainPassword = $null

        Write-ColorOutput "PFX file created: $OutputPath" -Level Success

        # Display certificate details
        Write-ColorOutput "Certificate details:" -Level Info
        Write-Host "  Subject:     $($cert.Subject)"
        Write-Host "  Issuer:      $($cert.Issuer)"
        Write-Host "  Valid From:  $($cert.NotBefore)"
        Write-Host "  Valid Until: $($cert.NotAfter)"
        Write-Host "  Thumbprint:  $($cert.Thumbprint)"

        return $OutputPath
    }
    catch {
        Write-ColorOutput "Failed to export certificate to PFX: $_" -Level Error
        throw
    }
}

function Show-Summary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$PfxPath,

        [Parameter(Mandatory = $true)]
        [SecureString]$Password
    )

    # Convert SecureString to plain text for display (only for summary)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    Write-Host ""
    Write-ColorOutput "Certificate request completed successfully!" -Level Success
    Write-Host ""
    Write-Host "========================================================================"
    Write-Host "  Certificate Summary"
    Write-Host "========================================================================"
    Write-Host "  Domain:           $Domain"
    Write-Host "  PFX File:         $PfxPath"
    Write-Host "  PFX Password:     $plainPassword"
    Write-Host "========================================================================"
    Write-Host ""
    Write-ColorOutput "IMPORTANT: Store the PFX password securely (e.g., a secrets manager)" -Level Warning
    Write-Host ""

    # Clear sensitive data
    $plainPassword = $null
}

# ==============================================================================
# Main Script
# ==============================================================================

try {
    Write-ColorOutput "Starting ACME certificate request process..." -Level Info
    Write-Host ""

    # Validate inputs
    Write-ColorOutput "Validating inputs..." -Level Info

    if (-not (Test-DomainNameFormat -DomainName $CertificateName)) {
        Write-ColorOutput "Continuing despite domain name format warning..." -Level Warning
    }

    if (-not (Test-CloudflareApiToken -ApiToken $CloudflareApiToken)) {
        Write-ColorOutput "Continuing despite API token format warning..." -Level Warning
    }

    # Generate PFX password if not provided
    if (-not $PfxPassword) {
        Write-ColorOutput "Generating secure random password for PFX file..." -Level Info
        $PfxPassword = New-RandomPassword
    }

    # Check and install Posh-ACME module
    Test-PoshAcmeModule

    # Determine ACME server URL
    $serverUrl = switch ($AcmeServer) {
        'LetsEncrypt' { 'https://acme-v02.api.letsencrypt.org/directory' }
        'LetsEncrypt-Staging' { 'https://acme-staging-v02.api.letsencrypt.org/directory' }
        default { 'https://acme-v02.api.letsencrypt.org/directory' }
    }

    # Request certificate
    $certificate = Request-AcmeCertificate `
        -Domain $CertificateName `
        -CfToken $CloudflareApiToken `
        -Server $serverUrl `
        -Email $ContactEmail `
        -ForceRenewal:$Force

    # Export to PFX
    $pfxPath = Join-Path $OutputDirectory "$CertificateName.pfx"
    $pfxPath = Export-CertificateToPfx `
        -Certificate $certificate `
        -Domain $CertificateName `
        -Password $PfxPassword `
        -OutputPath $pfxPath

    # Display summary
    Show-Summary `
        -Domain $CertificateName `
        -PfxPath $pfxPath `
        -Password $PfxPassword

    Write-ColorOutput "Process completed successfully!" -Level Success
    exit 0
}
catch {
    Write-ColorOutput "An error occurred: $_" -Level Error
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
