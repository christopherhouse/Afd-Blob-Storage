#!/usr/bin/env bash
# ==============================================================================
# ACME Certificate Request Script (Bash)
# ==============================================================================
# Description: Requests a new ACME certificate from Let's Encrypt using DNS01
#              validation via Cloudflare DNS. Converts the certificate to a
#              password-protected PFX file.
#
# Author: Auto-generated for Afd-Blob-Storage repository
# License: MIT
#
# Prerequisites:
#   - acme.sh installed (https://github.com/acmesh-official/acme.sh)
#   - curl or wget
#   - openssl
#   - Valid Cloudflare API token with DNS edit permissions
#
# Usage:
#   ./request-acme-cert.sh <certificate-name> <cloudflare-api-token>
#
# Example:
#   ./request-acme-cert.sh "example.com" "your-cloudflare-api-token"
#
# Output:
#   - <certificate-name>.pfx - Password-protected PFX file
#   - Certificate stored in ~/.acme.sh/<certificate-name>/
# ==============================================================================

set -e
set -o pipefail

# ==============================================================================
# Configuration
# ==============================================================================

# ACME server (production by default, set to staging for testing)
ACME_SERVER="${ACME_SERVER:-https://acme-v02.api.letsencrypt.org/directory}"
# ACME_SERVER="${ACME_SERVER:-https://acme-staging-v02.api.letsencrypt.org/directory}"

# Key algorithm (ec-256, ec-384, rsa2048, rsa3072, rsa4096)
KEY_ALGORITHM="${KEY_ALGORITHM:-ec-256}"

# PFX password (generate random if not provided)
PFX_PASSWORD="${PFX_PASSWORD:-$(openssl rand -base64 32)}"

# Output directory for certificates
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/certificates}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_dependencies() {
    local missing_deps=()

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing_deps+=("curl or wget")
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install the missing dependencies and try again."
        return 1
    fi

    return 0
}

install_acme_sh() {
    if [ -d "$HOME/.acme.sh" ]; then
        log_info "acme.sh already installed at $HOME/.acme.sh"
        return 0
    fi

    log_info "Installing acme.sh..."

    if command -v curl >/dev/null 2>&1; then
        curl -sSL https://get.acme.sh | sh -s email="${ACME_EMAIL:-admin@example.com}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O- https://get.acme.sh | sh -s email="${ACME_EMAIL:-admin@example.com}"
    else
        log_error "Neither curl nor wget is available"
        return 1
    fi

    # Source acme.sh environment
    if [ -f "$HOME/.acme.sh/acme.sh.env" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.acme.sh/acme.sh.env"
    fi

    log_success "acme.sh installed successfully"
}

validate_inputs() {
    local cert_name="$1"
    local cf_token="$2"

    if [ -z "$cert_name" ]; then
        log_error "Certificate name is required"
        return 1
    fi

    # Validate domain name format (basic check)
    if ! echo "$cert_name" | grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$|^\*\.([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
        log_warning "Certificate name '$cert_name' may not be a valid domain name"
        log_warning "Expected format: example.com or *.example.com"
    fi

    if [ -z "$cf_token" ]; then
        log_error "Cloudflare API token is required"
        return 1
    fi

    # Validate token format (basic check - should be 40 chars alphanumeric)
    if ! echo "$cf_token" | grep -qE '^[a-zA-Z0-9_-]{40,}$'; then
        log_warning "Cloudflare API token format may be invalid"
        log_warning "Expected: 40+ character alphanumeric string"
    fi

    return 0
}

request_certificate() {
    local cert_name="$1"
    local cf_token="$2"

    log_info "Requesting certificate for: $cert_name"
    log_info "Using ACME server: $ACME_SERVER"
    log_info "Key algorithm: $KEY_ALGORITHM"

    # Set Cloudflare credentials
    export CF_Token="$cf_token"
    export CF_Account_ID=""  # Not required for DNS API
    export CF_Zone_ID=""     # Auto-detected by acme.sh

    # Disable DNS-over-HTTPS (DOH) to avoid connectivity issues
    # acme.sh may fail with curl error 7 if DOH servers are unreachable
    export NO_DOH=1

    # Construct acme.sh command
    # Note: --dnssleep 60 waits for DNS propagation instead of using DOH verification
    # This prevents curl error 7 in networks where DOH is blocked
    local acme_cmd="$HOME/.acme.sh/acme.sh --issue"
    acme_cmd="$acme_cmd -d $cert_name"
    acme_cmd="$acme_cmd --dns dns_cf"
    acme_cmd="$acme_cmd --keylength $KEY_ALGORITHM"
    acme_cmd="$acme_cmd --server $ACME_SERVER"
    acme_cmd="$acme_cmd --dnssleep 60"
    acme_cmd="$acme_cmd --force"

    log_info "Executing: $acme_cmd"

    # Execute acme.sh
    if eval "$acme_cmd"; then
        log_success "Certificate issued successfully"
        return 0
    else
        log_error "Failed to issue certificate"
        return 1
    fi
}

convert_to_pfx() {
    local cert_name="$1"
    local password="$2"

    log_info "Converting certificate to PFX format..."

    local cert_dir="$HOME/.acme.sh/$cert_name"
    local cert_file="$cert_dir/$cert_name.cer"
    local key_file="$cert_dir/$cert_name.key"
    local ca_file="$cert_dir/ca.cer"
    local fullchain_file="$cert_dir/fullchain.cer"

    # Verify certificate files exist
    if [ ! -f "$cert_file" ]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi

    if [ ! -f "$key_file" ]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi

    # Use fullchain if available, otherwise use cert + ca
    local input_cert
    if [ -f "$fullchain_file" ]; then
        input_cert="$fullchain_file"
    else
        input_cert="$cert_file"
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    local pfx_file="$OUTPUT_DIR/$cert_name.pfx"

    # Convert to PFX with password protection
    if openssl pkcs12 -export \
        -out "$pfx_file" \
        -inkey "$key_file" \
        -in "$input_cert" \
        -certfile "$ca_file" \
        -password "pass:$password"; then

        log_success "PFX file created: $pfx_file"

        # Display PFX details
        log_info "Certificate details:"
        openssl pkcs12 -in "$pfx_file" -nokeys -passin "pass:$password" | \
            openssl x509 -noout -subject -issuer -dates

        return 0
    else
        log_error "Failed to create PFX file"
        return 1
    fi
}

display_summary() {
    local cert_name="$1"
    local password="$2"
    local pfx_file="$OUTPUT_DIR/$cert_name.pfx"

    echo ""
    log_success "Certificate request completed successfully!"
    echo ""
    echo "========================================================================"
    echo "  Certificate Summary"
    echo "========================================================================"
    echo "  Domain:           $cert_name"
    echo "  PFX File:         $pfx_file"
    echo "  PFX Password:     $password"
    echo "  Certificate Dir:  $HOME/.acme.sh/$cert_name/"
    echo "========================================================================"
    echo ""
    log_warning "IMPORTANT: Store the PFX password securely (e.g., Azure Key Vault)"
    log_info "You can import this certificate to Azure Key Vault using:"
    echo ""
    echo "  az keyvault certificate import \\"
    echo "    --vault-name <key-vault-name> \\"
    echo "    --name $cert_name \\"
    echo "    --file $pfx_file \\"
    echo "    --password '$password'"
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 <certificate-name> <cloudflare-api-token>

Request a new ACME certificate from Let's Encrypt using DNS01 validation
via Cloudflare DNS. The certificate will be converted to a password-protected
PFX file.

Arguments:
  certificate-name      Domain name for the certificate (e.g., example.com)
  cloudflare-api-token  Cloudflare API token with DNS edit permissions

Environment Variables:
  ACME_SERVER          ACME server URL (default: Let's Encrypt production)
  ACME_EMAIL           Email address for ACME account registration
  KEY_ALGORITHM        Key algorithm (default: ec-256)
                       Options: ec-256, ec-384, rsa2048, rsa3072, rsa4096
  PFX_PASSWORD         Password for PFX file (auto-generated if not provided)
  OUTPUT_DIR           Output directory for PFX file (default: ./certificates)

Examples:
  # Request certificate for example.com
  $0 example.com your-cloudflare-api-token

  # Request wildcard certificate with custom password
  PFX_PASSWORD="MySecurePassword123!" $0 "*.example.com" your-cf-token

  # Use Let's Encrypt staging server for testing
  ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory" \\
    $0 test.example.com your-cf-token

  # Use RSA 4096 key
  KEY_ALGORITHM=rsa4096 $0 example.com your-cf-token

EOF
}

# ==============================================================================
# Main Script
# ==============================================================================

main() {
    local cert_name="$1"
    local cf_token="$2"

    # Display usage if no arguments provided
    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi

    # Display usage if help flag provided
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        usage
        exit 0
    fi

    log_info "Starting ACME certificate request process..."

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Validate inputs
    if ! validate_inputs "$cert_name" "$cf_token"; then
        usage
        exit 1
    fi

    # Install acme.sh if not already installed
    if ! install_acme_sh; then
        exit 1
    fi

    # Request certificate
    if ! request_certificate "$cert_name" "$cf_token"; then
        exit 1
    fi

    # Convert to PFX
    if ! convert_to_pfx "$cert_name" "$PFX_PASSWORD"; then
        exit 1
    fi

    # Display summary
    display_summary "$cert_name" "$PFX_PASSWORD"

    exit 0
}

# Execute main function
main "$@"
