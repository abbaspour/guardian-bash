#!/usr/bin/env bash

##########################################################################################
# Author: Amin Abbaspour
# Date: 2026-02-20
# License: MIT (https://github.com/abbaspour/guardian-bash/blob/master/LICENSE)
##########################################################################################

# Guardian Device Unenrollment
# Removes previously enrolled devices from Auth0 Guardian MFA service

set -e

# Default values
CLIENT_NAME="Guardian.Shell"
CLIENT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENROLLMENTS_DIR="${SCRIPT_DIR}/.enrollments"

# Usage function
usage() {
    cat << EOF
Usage: $0 -d DOMAIN -i DEVICE_ID [-a AUTH0_CLIENT]

DESCRIPTION:
  Removes a previously enrolled device from Auth0 Guardian MFA service.
  Requires enrollment data saved during device enrollment.

Required arguments:
  -d DOMAIN         Base domain/URL (same as used during enrollment)
                    Examples: 'tenant.auth0.com' or 'tenant.guardian.auth0.com'
  -i DEVICE_ID      Device identifier (same as used during enrollment)

Optional arguments:
  -a AUTH0_CLIENT   Custom Auth0-Client header value (base64url-encoded JSON)
                    Default: {"name":"Guardian.Shell","version":"1.0.0"}
  -h                Show this help message

EXAMPLES:

  # Unenroll a device using custom domain
  $0 -d "tenant.auth0.com" -i "device-001"

  # Unenroll a device using Guardian hosted domain
  $0 -d "tenant.guardian.auth0.com" -i "device-001"

ENROLLMENT DATA:
  This script reads enrollment data from: .enrollments/{device_id}.json
  This file is created by enroll-device.sh during enrollment.
  The file contains enrollment_id and device_token needed for unenrollment.

  If the enrollment data file is missing, the device cannot be unenrolled
  using this script. You may need to unenroll through the Auth0 Dashboard.

EOF
    exit 1
}

# Parse command line arguments
while getopts "d:i:a:h" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        i) DEVICE_ID="$OPTARG" ;;
        a) AUTH0_CLIENT="$OPTARG" ;;
        h) usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

# Validate required parameters
if [[ -z "$DOMAIN" ]] || [[ -z "$DEVICE_ID" ]]; then
    echo "Error: Missing required arguments (DOMAIN and DEVICE_ID are required)" >&2
    usage
fi

# Check if enrollment data exists
ENROLLMENT_FILE="${ENROLLMENTS_DIR}/${DEVICE_ID}.json"
if [[ ! -f "$ENROLLMENT_FILE" ]]; then
    echo "Error: Enrollment data not found for device: $DEVICE_ID" >&2
    echo "Expected file: $ENROLLMENT_FILE" >&2
    echo "This device may not be enrolled or the enrollment data was removed." >&2
    exit 1
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

# Function to perform device unenrollment
unenroll_device() {
    echo "=== Guardian Device Unenrollment ===" >&2
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
unenroll_device
