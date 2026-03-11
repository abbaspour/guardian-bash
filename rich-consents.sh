#!/usr/bin/env bash

##########################################################################################
# Author: Amin Abbaspour
# Date: 2026-02-23
# License: MIT (https://github.com/abbaspour/guardian-bash/blob/master/LICENSE)
##########################################################################################

# Guardian Rich Consents Fetcher
# Fetches rich consent data for Auth0 Guardian MFA transactions
# Uses DPoP (Demonstrating Proof-of-Possession) authentication

set -e

# Default values
CLIENT_NAME="Guardian.Shell"
CLIENT_VERSION="1.0.0"

# Load .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# Default key paths
DEFAULT_PRIVATE_KEY="${SCRIPT_DIR}/private.pem"
DEFAULT_PUBLIC_KEY="${SCRIPT_DIR}/public.pem"
ENROLLMENTS_DIR="${SCRIPT_DIR}/.enrollments"

# Usage function
usage() {
    cat << EOF
Usage: $0 -c CONSENT_ID -d DOMAIN -t TXTKN -i DEVICE_ID -k PRIVATE_KEY -f PUBLIC_KEY [-a AUTH0_CLIENT]

DESCRIPTION:
  Fetches rich consent data from Auth0 Guardian MFA service using DPoP authentication.
  Rich consents provide detailed context for MFA transactions (payment details, scopes, etc.)

Required arguments:
  -c CONSENT_ID     Consent identifier from push notification
  -d DOMAIN         Base domain/URL (e.g., 'tenant.auth0.com' or 'tenant.guardian.auth0.com')
                    Can be set in .env as AUTH0_DOMAIN
  -t TXTKN          Transaction token from push notification
  -i DEVICE_ID      Device identifier (used for DPoP proof JWT)
                    Auto-detected if only one device enrolled in .enrollments/
  -k KEY_PATH       Path to RSA private key PEM file (default: ./private.pem)
  -f PUBLIC_KEY     Path to RSA public key PEM file (default: ./public.pem)

Optional arguments:
  -a AUTH0_CLIENT   Custom Auth0-Client header value (base64url-encoded JSON)
                    Default: {"name":"Guardian.Shell","version":"1.0.0"}
  -h                Show this help message

EXAMPLES:

  # Fetch rich consent data
  $0 -c "consent_abc123" \\
     -d "tenant.auth0.com" \\
     -t "transaction_token_xyz" \\
     -i "device-001" \\
     -k ./private.pem \\
     -f ./public.pem

  # With Guardian hosted domain
  $0 -c "consent_abc123" \\
     -d "tenant.guardian.auth0.com" \\
     -t "transaction_token_xyz" \\
     -i "device-001"

  # Pipe output to jq for specific field extraction
  $0 -c "consent_abc123" -d "tenant.auth0.com" -t "txtkn" -i "device-001" | jq '.requested_details'

EOF
    exit 1
}

# Parse command line arguments
while getopts "c:d:t:i:k:f:a:h" opt; do
    case $opt in
        c) CONSENT_ID="$OPTARG" ;;
        d) DOMAIN="$OPTARG" ;;
        t) TRANSACTION_TOKEN="$OPTARG" ;;
        i) DEVICE_ID="$OPTARG" ;;
        k) PRIVATE_KEY_PATH="$OPTARG" ;;
        f) PUBLIC_KEY_PATH="$OPTARG" ;;
        a) AUTH0_CLIENT="$OPTARG" ;;
        h) usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

# Use AUTH0_DOMAIN from .env if DOMAIN not provided via command line
if [[ -z "$DOMAIN" ]] && [[ -n "$AUTH0_DOMAIN" ]]; then
    DOMAIN="$AUTH0_DOMAIN"
fi

# Use default key paths if not provided
if [[ -z "$PRIVATE_KEY_PATH" ]]; then
    PRIVATE_KEY_PATH="$DEFAULT_PRIVATE_KEY"
fi

if [[ -z "$PUBLIC_KEY_PATH" ]]; then
    PUBLIC_KEY_PATH="$DEFAULT_PUBLIC_KEY"
fi

# Auto-detect device ID if not provided and only one device is enrolled
if [[ -z "$DEVICE_ID" ]] && [[ -d "$ENROLLMENTS_DIR" ]]; then
    enrollment_files=("$ENROLLMENTS_DIR"/*.json)
    if [[ ${#enrollment_files[@]} -eq 1 ]] && [[ -f "${enrollment_files[0]}" ]]; then
        # Extract device_id from filename (format: {device_id}.json)
        DEVICE_ID=$(basename "${enrollment_files[0]}" .json)
        echo "Auto-detected device ID: $DEVICE_ID" >&2
    fi
fi

# Validate required parameters
if [[ -z "$CONSENT_ID" ]] || [[ -z "$DOMAIN" ]] || [[ -z "$TRANSACTION_TOKEN" ]] || [[ -z "$DEVICE_ID" ]]; then
    echo "Error: Missing required arguments" >&2
    usage
fi

# Check if private key file exists
if [[ ! -f "$PRIVATE_KEY_PATH" ]]; then
    echo "Error: Private key file not found: $PRIVATE_KEY_PATH" >&2
    exit 1
fi

# Check if public key file exists and is valid
if [[ ! -f "$PUBLIC_KEY_PATH" ]]; then
    echo "Error: Public key file not found: $PUBLIC_KEY_PATH" >&2
    exit 1
fi

# Verify it's a valid RSA public key PEM file
if ! openssl rsa -pubin -in "$PUBLIC_KEY_PATH" -noout 2>/dev/null; then
    echo "Error: Invalid RSA public key PEM file: $PUBLIC_KEY_PATH" >&2
    exit 1
fi

##########################################################################################
# Utility Functions
##########################################################################################

# Function to perform base64url encoding (URL-safe, no padding)
base64url_encode() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

##########################################################################################
# DPoP-Specific Functions
##########################################################################################

# Function to compute SHA-256 hash of transaction token (for DPoP ath claim)
compute_token_hash() {
    local token="$1"
    # SHA-256 hash of transaction token, base64url-encoded
    echo -n "$token" | openssl dgst -sha256 -binary | base64url_encode
}

# Function to build rich consents URL
build_rich_consents_url() {
    local domain="$1"
    local consent_id="$2"

    # Remove protocol if present
    domain="${domain#http://}"
    domain="${domain#https://}"

    # Remove trailing slash
    domain="${domain%/}"

    # Remove .guardian subdomain if present (rich-consents uses normalized domain)
    domain="${domain//.guardian./.}"

    # Remove /appliance-mfa prefix if present (rich-consents doesn't use it)
    domain="${domain//\/appliance-mfa/}"

    # Build final URL
    echo "https://${domain}/rich-consents/${consent_id}"
}

# Function to generate UUID (for DPoP jti claim)
generate_uuid() {
    # Try uuidgen first (macOS/Linux standard)
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Fallback: generate random hex string formatted as UUID
        local hex=$(xxd -l 16 -p /dev/urandom | tr -d '\n')
        # Format as UUID: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
        echo "${hex:0:8}-${hex:8:4}-4${hex:13:3}-${hex:16:4}-${hex:20:12}"
    fi
}

# Function to create DPoP proof JWT
create_dpop_jwt() {
    local full_url="$1"
    local token_hash="$2"
    local public_key_path="$3"
    local private_key_path="$4"

    # Build public key JWK
    local public_key_jwk=$("${SCRIPT_DIR}/pem-to-jwk.sh" "$public_key_path")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to convert PEM to JWK" >&2
        exit 1
    fi

    # Build DPoP header with embedded public key
    local dpop_header=$(jq -n \
        --arg alg "RS256" \
        --arg typ "dpop+jwt" \
        --argjson jwk "$public_key_jwk" \
        '{alg: $alg, typ: $typ, jwk: $jwk}')

    # Get current timestamp and generate UUID
    local iat=$(date +%s)
    local jti=$(generate_uuid)

    # Build DPoP payload
    local dpop_payload=$(jq -n \
        --arg htu "$full_url" \
        --arg htm "GET" \
        --arg ath "$token_hash" \
        --arg jti "$jti" \
        --arg iat "$iat" \
        '{htu: $htu, htm: $htm, ath: $ath, jti: $jti, iat: ($iat | tonumber)}')

    # Base64url encode header and payload
    local header_b64=$(echo -n "$dpop_header" | jq -c . | base64url_encode)
    local payload_b64=$(echo -n "$dpop_payload" | jq -c . | base64url_encode)

    # Sign with private key (RS256)
    local signature_base="${header_b64}.${payload_b64}"
    local signature_b64=$(echo -n "$signature_base" | \
        openssl dgst -sha256 -sign "$private_key_path" | \
        base64url_encode)

    # Return complete JWT
    echo "${signature_base}.${signature_b64}"
}

##########################################################################################
# Main Execution
##########################################################################################

# Print diagnostic info to stderr
echo "=== Guardian Rich Consent Fetch ===" >&2
echo "Consent ID: $CONSENT_ID" >&2
echo "Domain: $DOMAIN" >&2
echo "Device ID: $DEVICE_ID" >&2
echo "Transaction Token: ${TRANSACTION_TOKEN:0:20}..." >&2
echo "" >&2

# Build full URL
FULL_URL=$(build_rich_consents_url "$DOMAIN" "$CONSENT_ID")
echo "URL: $FULL_URL" >&2

# Compute token hash for DPoP
TOKEN_HASH=$(compute_token_hash "$TRANSACTION_TOKEN")

# Create DPoP proof JWT
echo "Creating DPoP proof JWT..." >&2
DPOP_JWT=$(create_dpop_jwt "$FULL_URL" "$TOKEN_HASH" "$PUBLIC_KEY_PATH" "$PRIVATE_KEY_PATH")

# Generate Auth0-Client header if not provided
if [[ -z "$AUTH0_CLIENT" ]]; then
    AUTH0_CLIENT=$(echo -n "{\"name\":\"$CLIENT_NAME\",\"version\":\"$CLIENT_VERSION\"}" | base64url_encode)
fi

# Send GET request
echo "Sending request..." >&2
echo "" >&2

RESPONSE_FILE="/tmp/guardian_rich_consent_$$.txt"
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
    -X GET "$FULL_URL" \
    -H "Authorization: MFA-DPoP $TRANSACTION_TOKEN" \
    -H "MFA-DPoP: $DPOP_JWT" \
    -H "Auth0-Client: $AUTH0_CLIENT")

# Print response
echo "=== Response ===" >&2
echo "HTTP Status Code: $HTTP_CODE" >&2

if [[ -s "$RESPONSE_FILE" ]]; then
    RESPONSE_BODY=$(cat "$RESPONSE_FILE")
    echo "Response Body:" >&2
    echo "$RESPONSE_BODY" | jq '.' >&2 2>/dev/null || echo "$RESPONSE_BODY" >&2
    echo "" >&2
fi

# Handle success and errors
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✓ Rich consent fetched successfully" >&2
    # Output to stdout for piping
    echo "$RESPONSE_BODY" | jq '.'
    rm -f "$RESPONSE_FILE"
    exit 0
elif [[ "$HTTP_CODE" == "401" ]]; then
    echo "✗ Unauthorized: Invalid token or DPoP signature" >&2
    rm -f "$RESPONSE_FILE"
    exit 1
elif [[ "$HTTP_CODE" == "404" ]]; then
    echo "✗ Not Found: Consent ID does not exist" >&2
    rm -f "$RESPONSE_FILE"
    exit 1
else
    echo "✗ Request failed with HTTP $HTTP_CODE" >&2
    rm -f "$RESPONSE_FILE"
    exit 1
fi
