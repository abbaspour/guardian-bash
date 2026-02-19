#!/usr/bin/env bash

##########################################################################################
# Author: Amin Abbaspour
# Date: 2026-02-19
# License: MIT (https://github.com/abbaspour/guardian-bash/blob/master/LICENSE)
##########################################################################################

# Guardian Device Enrollment
# Enrolls or unenrolls devices to Auth0 Guardian MFA service
# Supports FCM (Firebase Cloud Messaging) push notifications

set -e

# Default values
CLIENT_NAME="Guardian.Shell"
CLIENT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENROLLMENTS_DIR="${SCRIPT_DIR}/.enrollments"

# Usage function
usage() {
    cat << EOF
Usage: $0 -t TICKET -d DOMAIN -i DEVICE_ID -n NAME -g FCM_TOKEN -f PUBLIC_KEY_PEM [-a AUTH0_CLIENT]
       $0 -U -d DOMAIN -i DEVICE_ID [-a AUTH0_CLIENT]

ENROLLMENT MODE (default):
  Enrolls a new device with Auth0 Guardian using an enrollment ticket.

Required arguments:
  -t TICKET         Enrollment ticket from Auth0 (enrollment_tx_id from QR code)
  -d DOMAIN         Base domain/URL (e.g., 'tenant.auth0.com' or 'tenant.guardian.auth0.com')
  -i DEVICE_ID      Device identifier (unique ID for this device)
  -n NAME           Device name (human-readable name shown in Auth0 dashboard)
  -g FCM_TOKEN      Firebase Cloud Messaging token from Android/iOS app
  -f PUBLIC_KEY_PEM Path to RSA public key PEM file (generated with openssl genrsa + rsa -pubout)

Optional arguments:
  -a AUTH0_CLIENT   Custom Auth0-Client header value (base64url-encoded JSON)
                    Default: {"name":"Guardian.Shell","version":"1.0.0"}
  -h                Show this help message

UNENROLLMENT MODE:
  Removes a previously enrolled device from Auth0 Guardian.

Required arguments:
  -U                Enable unenrollment mode
  -d DOMAIN         Base domain/URL (same as used during enrollment)
  -i DEVICE_ID      Device identifier (same as used during enrollment)

Optional arguments:
  -a AUTH0_CLIENT   Custom Auth0-Client header value (base64url-encoded JSON)
  -h                Show this help message

EXAMPLES:

  # Generate RSA keypair (2048-bit recommended)
  openssl genrsa -out private.pem 2048
  openssl rsa -in private.pem -pubout -out public.pem

  # Enroll a device with FCM token
  $0 -t "enrollment_ticket_abc123" \\
     -d "tenant.auth0.com" \\
     -i "device-001" \\
     -n "My Test Device" \\
     -g "fcm_token_xyz789" \\
     -f public.pem

  # Enroll with Guardian hosted domain
  $0 -t "enrollment_ticket_abc123" \\
     -d "tenant.guardian.auth0.com" \\
     -i "device-001" \\
     -n "Production Device" \\
     -g "fcm_token_xyz789" \\
     -f public.pem

  # Unenroll a device
  $0 -U -d "tenant.auth0.com" -i "device-001"

ENROLLMENT DATA STORAGE:
  Enrollment data is saved to: .enrollments/{device_id}.json
  This file contains enrollment_id and device_token needed for unenrollment.

EOF
    exit 1
}

# Parse command line arguments
UNENROLL_MODE=false

while getopts "t:d:i:n:g:f:a:Uh" opt; do
    case $opt in
        t) TICKET="$OPTARG" ;;
        d) DOMAIN="$OPTARG" ;;
        i) DEVICE_ID="$OPTARG" ;;
        n) DEVICE_NAME="$OPTARG" ;;
        g) FCM_TOKEN="$OPTARG" ;;
        f) PUBLIC_KEY_PEM="$OPTARG" ;;
        a) AUTH0_CLIENT="$OPTARG" ;;
        U) UNENROLL_MODE=true ;;
        h) usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

# Validate common required parameters
if [[ -z "$DOMAIN" ]] || [[ -z "$DEVICE_ID" ]]; then
    echo "Error: Missing required arguments (DOMAIN and DEVICE_ID are always required)" >&2
    usage
fi

# Mode-specific validation
if [[ "$UNENROLL_MODE" == "false" ]]; then
    # Enrollment mode - validate enrollment-specific parameters
    if [[ -z "$TICKET" ]] || [[ -z "$DEVICE_NAME" ]] || [[ -z "$FCM_TOKEN" ]] || [[ -z "$PUBLIC_KEY_PEM" ]]; then
        echo "Error: Missing required arguments for enrollment mode" >&2
        usage
    fi

    # Check if public key file exists
    if [[ ! -f "$PUBLIC_KEY_PEM" ]]; then
        echo "Error: Public key file not found: $PUBLIC_KEY_PEM" >&2
        exit 1
    fi

    # Verify it's a valid PEM file
    if ! openssl rsa -pubin -in "$PUBLIC_KEY_PEM" -noout 2>/dev/null; then
        echo "Error: Invalid RSA public key PEM file: $PUBLIC_KEY_PEM" >&2
        exit 1
    fi
else
    # Unenrollment mode - check if enrollment data exists
    ENROLLMENT_FILE="${ENROLLMENTS_DIR}/${DEVICE_ID}.json"
    if [[ ! -f "$ENROLLMENT_FILE" ]]; then
        echo "Error: Enrollment data not found for device: $DEVICE_ID" >&2
        echo "Expected file: $ENROLLMENT_FILE" >&2
        echo "This device may not be enrolled or the enrollment data was removed." >&2
        exit 1
    fi
fi

# Function to perform base64url encoding (URL-safe, no padding)
base64url_encode() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

# Function to build the full URL with proper path handling
build_url() {
    local domain="$1"
    local endpoint="$2"

    # Remove protocol if present
    domain="${domain#http://}"
    domain="${domain#https://}"

    # Remove trailing slash
    domain="${domain%/}"

    # Check if it's a Guardian hosted domain (*.guardian.*.auth0.com or *.guardian.auth0.com)
    if [[ "$domain" =~ guardian.*\.auth0\.com ]]; then
        # Guardian hosted domains don't need /appliance-mfa prefix
        echo "https://${domain}${endpoint}"
    elif [[ "$domain" =~ /appliance-mfa ]]; then
        # Domain already contains /appliance-mfa
        echo "https://${domain}${endpoint}"
    else
        # Custom domain needs /appliance-mfa prefix
        echo "https://${domain}/appliance-mfa${endpoint}"
    fi
}

# Function to extract modulus from PEM file (hex format)
extract_modulus_from_pem() {
    local pem_file="$1"

    # Get modulus in hex format from openssl output
    # The output looks like:
    #   Modulus:
    #       00:a3:df:66:...
    #       d4:e5:f6:...
    #   Exponent: 65537 (0x10001)
    # Note: Leading 00 byte is ASN.1 padding and must be stripped

    local modulus_hex=$(openssl rsa -pubin -in "$pem_file" -text -noout 2>/dev/null | \
        awk '/Modulus:/,/Exponent:/ {print}' | \
        grep -v "Modulus:" | \
        grep -v "Exponent:" | \
        tr -d ' :\n')

    # Strip leading 00 byte if present (common in RSA modulus)
    if [[ "$modulus_hex" =~ ^00 ]]; then
        echo "${modulus_hex:2}"
    else
        echo "$modulus_hex"
    fi
}

# Function to extract exponent from PEM file
extract_exponent_from_pem() {
    local pem_file="$1"

    # Extract exponent value (typically 65537 = 0x10001)
    # Output format: "Exponent: 65537 (0x10001)"
    local exp_line=$(openssl rsa -pubin -in "$pem_file" -text -noout 2>/dev/null | grep "Exponent:")

    # Extract hex value from parentheses and strip 0x prefix
    echo "$exp_line" | sed -n 's/.*0x\([0-9a-fA-F]*\).*/\1/p'
}

# Function to convert hex string to base64url
hex_to_base64url() {
    local hex_string="$1"

    # Pad hex string to even length if necessary (xxd requires even-length hex)
    if (( ${#hex_string} % 2 != 0 )); then
        hex_string="0${hex_string}"
    fi

    # Convert hex to binary, then to base64url
    echo -n "$hex_string" | xxd -r -p | base64url_encode
}

# Function to build public key JWK from PEM file
build_public_key_jwk() {
    local pem_file="$1"

    # Extract modulus and exponent
    local modulus_hex=$(extract_modulus_from_pem "$pem_file")
    local exponent_hex=$(extract_exponent_from_pem "$pem_file")

    # Convert to base64url
    local n=$(hex_to_base64url "$modulus_hex")
    local e=$(hex_to_base64url "$exponent_hex")

    # Build JWK JSON object
    jq -n \
        --arg kty "RSA" \
        --arg alg "RS256" \
        --arg use "sig" \
        --arg e "$e" \
        --arg n "$n" \
        '{kty: $kty, alg: $alg, use: $use, e: $e, n: $n}'
}

# Function to save enrollment data
save_enrollment_data() {
    local device_id="$1"
    local response_json="$2"
    local domain="$3"

    # Create enrollments directory if it doesn't exist
    mkdir -p "$ENROLLMENTS_DIR"

    # Extract fields from response
    local enrollment_id=$(echo "$response_json" | jq -r '.id')
    local device_token=$(echo "$response_json" | jq -r '.token')
    local user_id=$(echo "$response_json" | jq -r '.user_id')
    local issuer=$(echo "$response_json" | jq -r '.issuer // ""')
    local totp_secret=$(echo "$response_json" | jq -r '.totp.secret // ""')
    local enrolled_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build enrollment data JSON
    local enrollment_data=$(jq -n \
        --arg device_id "$device_id" \
        --arg enrollment_id "$enrollment_id" \
        --arg device_token "$device_token" \
        --arg domain "$domain" \
        --arg enrolled_at "$enrolled_at" \
        --arg user_id "$user_id" \
        --arg issuer "$issuer" \
        --arg totp_secret "$totp_secret" \
        '{
            device_id: $device_id,
            enrollment_id: $enrollment_id,
            device_token: $device_token,
            domain: $domain,
            enrolled_at: $enrolled_at,
            user_id: $user_id,
            issuer: $issuer,
            totp_secret: $totp_secret
        }')

    # Save to file
    local enrollment_file="${ENROLLMENTS_DIR}/${device_id}.json"
    echo "$enrollment_data" > "$enrollment_file"

    echo "$enrollment_file"
}

# Function to perform device enrollment
enroll_device() {
    echo "=== Guardian Device Enrollment ===" >&2
    echo "Mode: ENROLLMENT" >&2
    echo "Domain: $DOMAIN" >&2
    echo "Device ID: $DEVICE_ID" >&2
    echo "Device Name: $DEVICE_NAME" >&2
    echo "FCM Token: ${FCM_TOKEN:0:20}..." >&2
    echo "" >&2

    # Build enrollment URL
    local url=$(build_url "$DOMAIN" "/api/enroll")
    echo "URL: $url" >&2
    echo "" >&2

    # Convert PEM to JWK
    echo "Converting public key to JWK format..." >&2
    local public_key_jwk=$(build_public_key_jwk "$PUBLIC_KEY_PEM")

    # Build push credentials object
    local push_credentials=$(jq -n \
        --arg service "GCM" \
        --arg token "$FCM_TOKEN" \
        '{service: $service, token: $token}')

    # Build enrollment request body
    local request_body=$(jq -n \
        --arg identifier "$DEVICE_ID" \
        --arg name "$DEVICE_NAME" \
        --argjson push_credentials "$push_credentials" \
        --argjson public_key "$public_key_jwk" \
        '{
            identifier: $identifier,
            name: $name,
            push_credentials: $push_credentials,
            public_key: $public_key
        }')

    # Generate Auth0-Client header if not provided
    if [[ -z "$AUTH0_CLIENT" ]]; then
        AUTH0_CLIENT=$(echo -n "{\"name\":\"$CLIENT_NAME\",\"version\":\"$CLIENT_VERSION\"}" | base64url_encode)
    fi

    # Send enrollment request
    echo "Sending enrollment request..." >&2
    echo "" >&2

    local response_file="/tmp/guardian_enroll_response_$$.txt"
    local http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
        -X POST "$url" \
        -H "Authorization: Ticket id=\"$TICKET\"" \
        -H "Auth0-Client: $AUTH0_CLIENT" \
        -H "Content-Type: application/json" \
        -d "$request_body")

    # Print response
    echo "=== Response ===" >&2
    echo "HTTP Status Code: $http_code" >&2

    local response_body=""
    if [[ -s "$response_file" ]]; then
        response_body=$(cat "$response_file")
        echo "Response Body:" >&2
        echo "$response_body" | jq '.' >&2 2>/dev/null || echo "$response_body" >&2
        echo "" >&2
    fi

    # Handle response
    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        echo "✓ Device enrolled successfully" >&2

        # Save enrollment data
        local enrollment_file=$(save_enrollment_data "$DEVICE_ID" "$response_body" "$DOMAIN")
        echo "Saved enrollment data to $enrollment_file" >&2
        echo "" >&2

        # Print response to stdout for piping
        echo "$response_body"

        # Clean up
        rm -f "$response_file"
        exit 0
    elif [[ "$http_code" == "401" ]]; then
        echo "✗ Enrollment failed: Unauthorized (invalid or expired ticket)" >&2
        rm -f "$response_file"
        exit 1
    elif [[ "$http_code" == "409" ]]; then
        echo "✗ Enrollment failed: Device already enrolled (conflict)" >&2
        rm -f "$response_file"
        exit 1
    elif [[ "$http_code" == "400" ]]; then
        echo "✗ Enrollment failed: Bad request (check parameters)" >&2
        rm -f "$response_file"
        exit 1
    else
        echo "✗ Enrollment failed with HTTP $http_code" >&2
        rm -f "$response_file"
        exit 1
    fi
}

# Function to perform device unenrollment
unenroll_device() {
    echo "=== Guardian Device Unenrollment ===" >&2
    echo "Mode: UNENROLLMENT" >&2
    echo "Domain: $DOMAIN" >&2
    echo "Device ID: $DEVICE_ID" >&2
    echo "" >&2

    # Read enrollment data
    local enrollment_file="${ENROLLMENTS_DIR}/${DEVICE_ID}.json"
    local enrollment_data=$(cat "$enrollment_file")

    local enrollment_id=$(echo "$enrollment_data" | jq -r '.enrollment_id')
    local device_token=$(echo "$enrollment_data" | jq -r '.device_token')

    echo "Enrollment ID: $enrollment_id" >&2
    echo "Device Token: ${device_token:0:20}..." >&2
    echo "" >&2

    # Build unenrollment URL
    local url=$(build_url "$DOMAIN" "/api/device-accounts/${enrollment_id}")
    echo "URL: $url" >&2
    echo "" >&2

    # Generate Auth0-Client header if not provided
    if [[ -z "$AUTH0_CLIENT" ]]; then
        AUTH0_CLIENT=$(echo -n "{\"name\":\"$CLIENT_NAME\",\"version\":\"$CLIENT_VERSION\"}" | base64url_encode)
    fi

    # Send unenrollment request
    echo "Sending unenrollment request..." >&2
    echo "" >&2

    local response_file="/tmp/guardian_unenroll_response_$$.txt"
    local http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
        -X DELETE "$url" \
        -H "Authorization: Bearer $device_token" \
        -H "Auth0-Client: $AUTH0_CLIENT")

    # Print response
    echo "=== Response ===" >&2
    echo "HTTP Status Code: $http_code" >&2

    if [[ -s "$response_file" ]]; then
        local response_body=$(cat "$response_file")
        echo "Response Body:" >&2
        echo "$response_body" | jq '.' >&2 2>/dev/null || echo "$response_body" >&2
        echo "" >&2
    fi

    # Handle response
    if [[ "$http_code" == "204" ]] || [[ "$http_code" == "200" ]]; then
        echo "✓ Device unenrolled successfully" >&2

        # Remove enrollment data file
        rm -f "$enrollment_file"
        echo "Removed enrollment data file: $enrollment_file" >&2
        echo "" >&2

        # Clean up
        rm -f "$response_file"
        exit 0
    elif [[ "$http_code" == "404" ]]; then
        # Device not found - treat as success (idempotent)
        echo "✓ Device already unenrolled (not found on server)" >&2

        # Remove enrollment data file anyway
        rm -f "$enrollment_file"
        echo "Removed enrollment data file: $enrollment_file" >&2
        echo "" >&2

        # Clean up
        rm -f "$response_file"
        exit 0
    elif [[ "$http_code" == "401" ]]; then
        echo "✗ Unenrollment failed: Unauthorized (invalid device token)" >&2
        rm -f "$response_file"
        exit 1
    else
        echo "✗ Unenrollment failed with HTTP $http_code" >&2
        rm -f "$response_file"
        exit 1
    fi
}

# Main execution
if [[ "$UNENROLL_MODE" == "true" ]]; then
    unenroll_device
else
    enroll_device
fi
