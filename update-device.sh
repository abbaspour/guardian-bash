#!/usr/bin/env bash

##########################################################################################
# Author: Amin Abbaspour
# Date: 2026-02-20
# License: MIT (https://github.com/abbaspour/guardian-bash/blob/master/LICENSE)
##########################################################################################

# Guardian Device Update
# Updates device information for previously enrolled devices

set -e

# Default values
CLIENT_NAME="Guardian.Shell"
CLIENT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENROLLMENTS_DIR="${SCRIPT_DIR}/.enrollments"

# Load .env file if it exists
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# Global variables
DEVICE_ID=""
NAME=""
IDENTIFIER=""
GCM_TOKEN=""
DOMAIN=""
AUTH0_CLIENT=""

# Usage function
usage() {
    cat << EOF
Usage: $0 -i DEVICE_ID -g GCM_TOKEN [-n NAME] [-I IDENTIFIER] [-d DOMAIN] [-a AUTH0_CLIENT]

DESCRIPTION:
  Updates device information for a previously enrolled Guardian device.
  The FCM token is always required by the API (use current token if not changing).

Required arguments:
  -i DEVICE_ID      Device identifier (same as used during enrollment)
                    Auto-detected if only one device enrolled in .enrollments/
  -g GCM_TOKEN      Firebase Cloud Messaging token (required by API, use current value if unchanged)

Optional update fields:
  -n NAME           New device display name
  -I IDENTIFIER     New device identifier (capital I)

Optional control arguments:
  -d DOMAIN         Override domain (defaults to value in enrollment file or AUTH0_DOMAIN in .env)
  -a AUTH0_CLIENT   Custom Auth0-Client header value (base64url-encoded JSON)
                    Default: {"name":"Guardian.Shell","version":"1.0.0"}
  -h                Show this help message

EXAMPLES:

  # Update device name (FCM token must be provided even if unchanged)
  $0 -i "device-001" -n "New Device Name" -g "current_fcm_token"

  # Update multiple fields including new FCM token
  $0 -i "device-001" -n "Updated Name" -I "new-device-id" -g "new_fcm_token"

  # Update only FCM token
  $0 -i "device-001" -g "new_fcm_token_xyz..."

  # Update with custom domain override
  $0 -i "device-001" -n "New Name" -g "current_fcm_token" -d "tenant.auth0.com"

ENROLLMENT DATA:
  This script reads enrollment data from: .enrollments/{device_id}.json
  This file is created by enroll-device.sh during enrollment.
  The file contains enrollment_id, device_token, and domain needed for updates.

EOF
    exit 1
}

# Parse command line arguments
while getopts "i:n:I:g:d:a:h" opt; do
    case $opt in
        i) DEVICE_ID="$OPTARG" ;;
        n) NAME="$OPTARG" ;;
        I) IDENTIFIER="$OPTARG" ;;
        g) GCM_TOKEN="$OPTARG" ;;
        d) DOMAIN="$OPTARG" ;;
        a) AUTH0_CLIENT="$OPTARG" ;;
        h) usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

# Use AUTH0_DOMAIN from .env if DOMAIN not provided via command line
# (Note: DOMAIN can be overridden or will fall back to enrollment file value)
if [[ -z "$DOMAIN" ]] && [[ -n "$AUTH0_DOMAIN" ]]; then
    DOMAIN="$AUTH0_DOMAIN"
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
if [[ -z "$DEVICE_ID" ]]; then
    echo "Error: DEVICE_ID is required (-i)" >&2
    usage
fi

if [[ -z "$GCM_TOKEN" ]]; then
    echo "Error: GCM_TOKEN is required (-g). The Guardian API requires push_credentials in all update requests." >&2
    usage
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


# Function to build update payload JSON
build_update_payload() {
    local jq_args=()
    local jq_object_parts=()

    # push_credentials is always required by the API
    jq_args+=(--arg gcm_token "$GCM_TOKEN")
    jq_object_parts+=("push_credentials: {service: \"GCM\", token: \$gcm_token}")

    if [[ -n "$NAME" ]]; then
        jq_args+=(--arg name "$NAME")
        jq_object_parts+=("name: \$name")
    fi

    if [[ -n "$IDENTIFIER" ]]; then
        jq_args+=(--arg identifier "$IDENTIFIER")
        jq_object_parts+=("identifier: \$identifier")
    fi

    # Build jq object string
    local jq_filter=$(IFS=,; echo "{${jq_object_parts[*]}}")

    # Execute jq with collected arguments
    jq -n "${jq_args[@]}" "$jq_filter" | jq -c .
}

# Function to perform device update
update_device() {
    echo "=== Guardian Device Update ===" >&2
    echo "Device ID: $DEVICE_ID" >&2

    # Check if enrollment data exists
    local enrollment_file="${ENROLLMENTS_DIR}/${DEVICE_ID}.json"
    if [[ ! -f "$enrollment_file" ]]; then
        echo "Error: Enrollment data not found for device: $DEVICE_ID" >&2
        echo "Expected file: $enrollment_file" >&2
        echo "This device may not be enrolled or the enrollment data was removed." >&2
        exit 1
    fi

    # Read enrollment data
    local enrollment_data=$(cat "$enrollment_file")
    local enrollment_id=$(echo "$enrollment_data" | jq -r '.enrollment_id')
    local device_token=$(echo "$enrollment_data" | jq -r '.device_token')
    local enrollment_domain=$(echo "$enrollment_data" | jq -r '.domain')

    # Use override domain if provided, otherwise use enrollment domain
    if [[ -z "$DOMAIN" ]]; then
        DOMAIN="$enrollment_domain"
    fi

    echo "Enrollment ID: $enrollment_id" >&2
    echo "Domain: $DOMAIN" >&2

    # Show which fields are being updated
    local update_fields=()
    [[ -n "$NAME" ]] && update_fields+=("name")
    [[ -n "$IDENTIFIER" ]] && update_fields+=("identifier")
    [[ -n "$GCM_TOKEN" ]] && update_fields+=("push_credentials")
    echo "Update Fields: $(IFS=, ; echo "${update_fields[*]}")" >&2
    echo "" >&2

    # Build update URL
    local url=$(build_url "$DOMAIN" "/api/device-accounts/${enrollment_id}")
    echo "URL: $url" >&2
    echo "" >&2

    # Build request body
    local request_body=$(build_update_payload)
    echo "Request Body:" >&2
    echo "$request_body" | jq '.' >&2 2>/dev/null || echo "$request_body" >&2
    echo "" >&2

    # Generate Auth0-Client header if not provided
    if [[ -z "$AUTH0_CLIENT" ]]; then
        AUTH0_CLIENT=$(echo -n "{\"name\":\"$CLIENT_NAME\",\"version\":\"$CLIENT_VERSION\"}" | base64url_encode)
    fi

    # Send update request
    echo "Sending update request..." >&2
    echo "" >&2

    local response_file="/tmp/guardian_update_response_$$.txt"
    local http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
        -X PATCH "$url" \
        -H "Authorization: Bearer $device_token" \
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
    if [[ "$http_code" == "200" ]]; then
        echo "✓ Device updated successfully" >&2
        echo "" >&2

        # Print response to stdout for piping
        echo "$response_body"

        # Clean up
        rm -f "$response_file"
        exit 0
    elif [[ "$http_code" == "401" ]]; then
        echo "✗ Update failed: Invalid or expired device token" >&2
        rm -f "$response_file"
        exit 1
    elif [[ "$http_code" == "404" ]]; then
        echo "✗ Update failed: Device not found (may have been deleted)" >&2
        rm -f "$response_file"
        exit 1
    elif [[ "$http_code" == "400" ]]; then
        echo "✗ Update failed: Invalid request parameters" >&2
        rm -f "$response_file"
        exit 1
    else
        echo "✗ Update failed with HTTP $http_code" >&2
        rm -f "$response_file"
        exit 1
    fi
}

# Main execution
update_device
