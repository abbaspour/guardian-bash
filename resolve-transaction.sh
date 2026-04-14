#!/usr/bin/env bash

##########################################################################################
# Author: Amin Abbaspour
# Date: 2026-01-21
# License: MIT (https://github.com/abbaspour/guardian-bash/blob/master/LICENSE)
##########################################################################################

# Guardian Transaction Resolver
# Mimics Guardian.Android SDK's transaction resolution behavior
# Sends allow/reject decision to Auth0 Guardian MFA service

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

# Default key file
DEFAULT_PRIVATE_KEY="${SCRIPT_DIR}/private.pem"
DEFAULT_EC_PRIVATE_KEY="${SCRIPT_DIR}/ec-private.pem"
ENROLLMENTS_DIR="${SCRIPT_DIR}/.enrollments"

# Usage function
usage() {
    cat << EOF
Usage: $0 [rs256|es256] [CHALLENGE DOMAIN DEVICE_ID [TXTKN]] [OPTIONS]

Positional arguments (new format, preferred):
  [rs256|es256]     Algorithm type (default: rs256 for backward compatibility)
                    rs256 = RSA-based RS256 JWT signing
                    es256 = ECDSA P-256 ES256 JWT signing

Flag-based arguments (legacy format):
  -c CHALLENGE      Challenge value from push notification (sets JWT 'sub' claim)
  -d DOMAIN         Base domain/URL (e.g., 'tenant.auth0.com' or 'tenant.guardian.auth0.com')
                    Can be set in .env as AUTH0_DOMAIN
  -i DEVICE_ID      Device identifier (sets JWT 'iss' claim)
                    Auto-detected if only one device enrolled in .enrollments/
  -k KEY_PATH       Path to RSA private key PEM file (default: ./private.pem)
  -t TXTKN          Transaction token from push notification

Optional arguments:
  -R REASON         Reject reason. If provided, rejects the transaction (auth0_guardian_accepted=false)
                    If omitted, allows the transaction (auth0_guardian_accepted=true)
  -s SIGNATURE      Optional consent signature (auth0_consent_signature JWT claim)
  -a AUTH0_CLIENT   Custom Auth0-Client header value (base64-encoded JSON)
                    Default: {"name":"Guardian.Shell","version":"1.0.0"}
  -h                Show this help message

Examples (new format):
  # Allow a transaction with RS256
  $0 rs256 "challenge_abc" "tenant.auth0.com" "device_123"

  # Allow a transaction with ES256
  $0 es256 "challenge_abc" "tenant.auth0.com" "device_123"

Examples (legacy format):
  # Allow a transaction
  $0 -c "challenge_abc" -d "tenant.auth0.com" -i "device_123" -k ./private.pem -t "txtkn_xyz"

  # Reject a transaction with reason
  $0 -c "challenge_abc" -d "tenant.auth0.com" -i "device_123" -k ./private.pem -t "txtkn_xyz" -R "Suspicious login"

  # Using a Guardian hosted domain (no /appliance-mfa prefix needed)
  $0 -c "challenge_abc" -d "tenant.guardian.auth0.com" -i "device_123" -k ./private.pem -t "txtkn_xyz"

EOF
    exit 1
}

# Initialize variables
ALGORITHM="rs256"
CHALLENGE=""
DOMAIN=""
DEVICE_ID=""
TXTKN=""
REASON=""
CONSENT_SIG=""
AUTH0_CLIENT=""
KEY_PATH=""

# Parse command line arguments (both new positional and legacy flag formats)
# Check if first argument is an algorithm specifier
if [[ $# -gt 0 ]] && ([[ "$1" == "rs256" ]] || [[ "$1" == "es256" ]]); then
    # New format: algorithm specified as first positional argument
    ALGORITHM="$1"
    shift

    # Parse remaining positional arguments
    if [[ $# -gt 0 ]]; then
        CHALLENGE="$1"
        shift
    fi
    if [[ $# -gt 0 ]]; then
        DOMAIN="$1"
        shift
    fi
    if [[ $# -gt 0 ]]; then
        DEVICE_ID="$1"
        shift
    fi
    if [[ $# -gt 0 ]]; then
        TXTKN="$1"
        shift
    fi

    # Parse any remaining flag arguments
    while getopts "R:s:a:h" opt; do
        case $opt in
            R) REASON="$OPTARG" ;;
            s) CONSENT_SIG="$OPTARG" ;;
            a) AUTH0_CLIENT="$OPTARG" ;;
            h) usage ;;
            \?) echo "Invalid option -$OPTARG" >&2; usage ;;
        esac
    done
else
    # Legacy format: flag-based arguments
    while getopts "c:d:i:k:t:R:s:a:h" opt; do
        case $opt in
            c) CHALLENGE="$OPTARG" ;;
            d) DOMAIN="$OPTARG" ;;
            i) DEVICE_ID="$OPTARG" ;;
            k) KEY_PATH="$OPTARG" ;;
            t) TXTKN="$OPTARG" ;;
            R) REASON="$OPTARG" ;;
            s) CONSENT_SIG="$OPTARG" ;;
            a) AUTH0_CLIENT="$OPTARG" ;;
            h) usage ;;
            \?) echo "Invalid option -$OPTARG" >&2; usage ;;
        esac
    done
fi

# Use AUTH0_DOMAIN from .env if DOMAIN not provided via command line
if [[ -z "$DOMAIN" ]] && [[ -n "$AUTH0_DOMAIN" ]]; then
    DOMAIN="$AUTH0_DOMAIN"
fi

# Use default private key if not provided (depends on algorithm)
if [[ -z "$KEY_PATH" ]]; then
    if [[ "$ALGORITHM" == "es256" ]]; then
        KEY_PATH="$DEFAULT_EC_PRIVATE_KEY"
    else
        KEY_PATH="$DEFAULT_PRIVATE_KEY"
    fi
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
if [[ -z "$CHALLENGE" ]] || [[ -z "$DOMAIN" ]] || [[ -z "$DEVICE_ID" ]] || [[ -z "$TXTKN" ]]; then
    echo "Error: Missing required arguments" >&2
    usage
fi

# Check if key file exists
if [[ ! -f "$KEY_PATH" ]]; then
    echo "Error: Private key file not found: $KEY_PATH" >&2
    exit 1
fi

# Validate algorithm
if [[ "$ALGORITHM" != "rs256" ]] && [[ "$ALGORITHM" != "es256" ]]; then
    echo "Error: Invalid algorithm '$ALGORITHM'. Must be 'rs256' or 'es256'" >&2
    exit 1
fi

# Function to perform base64url encoding (URL-safe, no padding)
base64url_encode() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

# Function to build the full URL with proper path handling
build_url() {
    local domain="$1"

    # Remove protocol if present
    domain="${domain#http://}"
    domain="${domain#https://}"

    # Remove trailing slash
    domain="${domain%/}"

    # Check if it's a Guardian hosted domain (*.guardian.*.auth0.com or *.guardian.auth0.com)
    if [[ "$domain" =~ guardian.*\.auth0\.com ]]; then
        # Guardian hosted domains don't need /appliance-mfa prefix
        echo "https://${domain}/api/resolve-transaction"
    elif [[ "$domain" =~ /appliance-mfa ]]; then
        # Domain already contains /appliance-mfa
        echo "https://${domain}/api/resolve-transaction"
    else
        # Custom domain needs /appliance-mfa prefix
        echo "https://${domain}/appliance-mfa/api/resolve-transaction"
    fi
}

# Build the full URL
FULL_URL=$(build_url "$DOMAIN")

# Determine if this is an allow or reject
if [[ -n "$REASON" ]]; then
    ACCEPTED="false"
else
    ACCEPTED="true"
fi

# Get current Unix timestamp
IAT=$(date +%s)
EXP=$((IAT + 30))

# Build JWT header based on algorithm
if [[ "$ALGORITHM" == "es256" ]]; then
    JWT_HEADER=$(echo -n '{"alg":"ES256","typ":"JWT"}' | base64url_encode)
else
    JWT_HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64url_encode)
fi

# Build JWT payload
if [[ "$ACCEPTED" == "true" ]]; then
    # Allow transaction (no reason field)
    JWT_PAYLOAD=$(cat <<EOF | jq -c --arg cs "${CONSENT_SIG:-}" 'if $cs != "" then . + {auth0_consent_signature: $cs} else . end' | base64url_encode
{
  "iat": $IAT,
  "exp": $EXP,
  "aud": "$FULL_URL",
  "iss": "$DEVICE_ID",
  "sub": "$CHALLENGE",
  "auth0_guardian_method": "push",
  "auth0_guardian_accepted": true
}
EOF
)
else
    # Reject transaction (with reason)
    JWT_PAYLOAD=$(cat <<EOF | jq -c --arg cs "${CONSENT_SIG:-}" 'if $cs != "" then . + {auth0_consent_signature: $cs} else . end' | base64url_encode
{
  "iat": $IAT,
  "exp": $EXP,
  "aud": "$FULL_URL",
  "iss": "$DEVICE_ID",
  "sub": "$CHALLENGE",
  "auth0_guardian_method": "push",
  "auth0_guardian_accepted": false,
  "auth0_guardian_reason": "$REASON"
}
EOF
)
fi

# Create the signature base
SIGNATURE_BASE="${JWT_HEADER}.${JWT_PAYLOAD}"

# Sign with private key
if [[ "$ALGORITHM" == "es256" ]]; then
    # ES256 signing (ECDSA P-256)
    # Step 1: Sign with openssl (produces DER-encoded ECDSA signature)
    DER_SIG=$(echo -n "$SIGNATURE_BASE" | openssl dgst -sha256 -sign "$KEY_PATH" | openssl base64 -e -A)

    # Step 2: Convert DER to raw r+s (64 bytes) using Node.js
    # DER format: 30 <len> 02 <rlen> <r> 02 <slen> <s>
    # Raw format: <r (32 bytes)> <s (32 bytes)>
    RAW_SIG=$(node -e "
      const sig = Buffer.from(process.argv[1], 'base64');
      let offset = 2;
      offset++;
      const rlen = sig[offset++];
      const r = sig.slice(offset + (rlen > 32 ? 1 : 0), offset + rlen);
      offset += rlen;
      offset++;
      const slen = sig[offset++];
      const s = sig.slice(offset + (slen > 32 ? 1 : 0), offset + slen);
      const raw = Buffer.concat([r.slice(-32), s.slice(-32)]);
      process.stdout.write(raw.toString('base64'));
    " "$DER_SIG" | tr '+/' '-_' | tr -d '=')

    JWT_SIGNATURE="$RAW_SIG"
else
    # RS256 signing (RSA with SHA-256)
    JWT_SIGNATURE=$(echo -n "$SIGNATURE_BASE" | openssl dgst -sha256 -sign "$KEY_PATH" | base64url_encode)
fi

# Construct final JWT
JWT="${SIGNATURE_BASE}.${JWT_SIGNATURE}"

# Generate Auth0-Client header if not provided
if [[ -z "$AUTH0_CLIENT" ]]; then
    AUTH0_CLIENT=$(echo -n "{\"name\":\"$CLIENT_NAME\",\"version\":\"$CLIENT_VERSION\"}" | base64url_encode)
fi

# Build request body
REQUEST_BODY=$(cat <<EOF | jq -c .
{
  "challenge_response": "$JWT"
}
EOF
)

# Print request details (for debugging)
echo "=== Guardian Transaction Resolution ===" >&2
echo "Algorithm: $(echo "$ALGORITHM" | tr '[:lower:]' '[:upper:]')" >&2
echo "Action: $([ "$ACCEPTED" == "true" ] && echo "ALLOW" || echo "REJECT")" >&2
echo "URL: $FULL_URL" >&2
echo "Device ID: $DEVICE_ID" >&2
echo "Challenge: $CHALLENGE" >&2
[[ -n "$REASON" ]] && echo "Reason: $REASON" >&2
echo "Transaction Token: ${TXTKN:0:20}..." >&2
echo "JWT Signature Length: ${#JWT_SIGNATURE} chars (base64url)" >&2
echo "" >&2
echo "Sending request..." >&2
echo "" >&2

# Send the request
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/guardian_response.txt \
    -X POST "$FULL_URL" \
    -H "Authorization: Bearer $TXTKN" \
    -H "Auth0-Client: $AUTH0_CLIENT" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")

# Print response
echo "=== Response ===" >&2
echo "HTTP Status Code: $HTTP_CODE" >&2

if [[ -s /tmp/guardian_response.txt ]]; then
    echo "Response Body:" >&2
    cat /tmp/guardian_response.txt >&2
    echo "" >&2
fi

# Clean up
rm -f /tmp/guardian_response.txt

# Check if request was successful
if [[ "$HTTP_CODE" == "204" ]] || [[ "$HTTP_CODE" == "200" ]]; then
    echo "" >&2
    echo "✓ Transaction $([ "$ACCEPTED" == "true" ] && echo "allowed" || echo "rejected") successfully" >&2
    exit 0
else
    echo "" >&2
    echo "✗ Request failed with HTTP $HTTP_CODE" >&2
    exit 1
fi
