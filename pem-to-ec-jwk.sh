#!/usr/bin/env bash
set -euo pipefail

##########################################################################################
# pem-to-ec-jwk.sh - Convert EC P-256 PEM files to JWK (JSON Web Key) format
#
# Usage:
#   ./pem-to-ec-jwk.sh <pem-file>       # Convert from file
#   ./pem-to-ec-jwk.sh -                # Read from stdin
#   ./pem-to-ec-jwk.sh                  # Read from stdin
#   cat ec-private.pem | ./pem-to-ec-jwk.sh # Pipe from stdin
#
# Examples:
#   ./pem-to-ec-jwk.sh ec-private.pem
#   ./pem-to-ec-jwk.sh ec-private.pem | jq '.crv'
#   cat ec-private.pem | ./pem-to-ec-jwk.sh | jq -r '.x, .y'
#
# Requirements:
#   - openssl: For EC key operations
#   - jq: For JSON generation
#   - xxd: For hex-to-binary conversion
##########################################################################################

usage() {
    cat <<EOF
Usage: $(basename "$0") [PEM_FILE]

Convert EC P-256 PEM files (public or private keys) to JWK (JSON Web Key) format.

Arguments:
  PEM_FILE    Path to PEM file (optional, reads from stdin if omitted or "-")

Options:
  -h, --help  Show this help message

Examples:
  $(basename "$0") ec-private.pem              # Convert from file
  $(basename "$0") -                           # Read from stdin
  cat ec-private.pem | $(basename "$0")        # Pipe from stdin
  $(basename "$0") ec-private.pem | jq '.x'    # Extract x coordinate

Output:
  JSON object with JWK fields: kty, crv, x, y, alg, use

EOF
    exit 0
}

##########################################################################################
# Utility Functions
##########################################################################################

# Function to perform base64url encoding (URL-safe, no padding)
base64url_encode() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

# Function to extract EC public key coordinates from PEM file
# Returns x and y coordinates as hex strings
extract_ec_coordinates_from_pem() {
    local pem_file="$1"

    # Use openssl ec to extract the public key in text format
    # For P-256, we get uncompressed format: 04 || x (32 bytes) || y (32 bytes)
    local pub_key_text=$(openssl ec -in "$pem_file" -text -noout 2>/dev/null | grep -A 10 "pub:" | tail -n +2)

    # Extract hex bytes (remove colons and whitespace)
    local pub_key_hex=$(echo "$pub_key_text" | tr -d ' :\n')

    # P-256 uncompressed format starts with "04" (65 bytes total: 1 + 32 + 32)
    if [[ ! "$pub_key_hex" =~ ^04 ]]; then
        echo "Error: Expected uncompressed EC point (04 prefix)" >&2
        exit 1
    fi

    # Extract x and y coordinates (skip the 04 prefix, take 32 bytes each = 64 hex chars each)
    local x_hex="${pub_key_hex:2:64}"
    local y_hex="${pub_key_hex:66:64}"

    # Verify we got 32 bytes for each
    if [[ ${#x_hex} -ne 64 ]] || [[ ${#y_hex} -ne 64 ]]; then
        echo "Error: Failed to extract valid P-256 coordinates" >&2
        exit 1
    fi

    echo "$x_hex" "$y_hex"
}

# Function to convert hex string to base64url
hex_to_base64url() {
    local hex_string="$1"

    # Pad hex string to even length if necessary
    if (( ${#hex_string} % 2 != 0 )); then
        hex_string="0${hex_string}"
    fi

    # Convert hex to binary, then to base64url
    echo -n "$hex_string" | xxd -r -p | base64url_encode
}

# Function to build EC P-256 JWK from PEM file
build_ec_jwk() {
    local pem_file="$1"

    # Extract x and y coordinates
    read x_hex y_hex < <(extract_ec_coordinates_from_pem "$pem_file")

    # Convert to base64url
    local x=$(hex_to_base64url "$x_hex")
    local y=$(hex_to_base64url "$y_hex")

    # Build JWK JSON object
    jq -n \
        --arg kty "EC" \
        --arg crv "P-256" \
        --arg x "$x" \
        --arg y "$y" \
        --arg alg "ES256" \
        --arg use "sig" \
        '{kty: $kty, crv: $crv, x: $x, y: $y, alg: $alg, use: $use}'
}

##########################################################################################
# Dependency Checks
##########################################################################################

check_dependencies() {
    local missing_deps=()

    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if ! command -v xxd &> /dev/null; then
        missing_deps+=("xxd")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install the missing tools and try again." >&2
        exit 1
    fi
}

##########################################################################################
# Main Logic
##########################################################################################

main() {
    # Check dependencies first
    check_dependencies

    # Parse arguments
    if [[ $# -eq 0 ]] || [[ "$1" == "-" ]]; then
        # Read from stdin
        local temp_file=$(mktemp)
        trap "rm -f '$temp_file'" EXIT

        cat > "$temp_file"

        # Check if stdin was empty
        if [[ ! -s "$temp_file" ]]; then
            echo "Error: No input provided" >&2
            exit 1
        fi

        # Validate it's a valid EC key
        if ! openssl ec -in "$temp_file" -noout 2>/dev/null; then
            echo "Error: Invalid EC key in PEM input" >&2
            exit 1
        fi

        # Convert to JWK
        build_ec_jwk "$temp_file"

    elif [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage

    else
        # Read from file
        local pem_file="$1"

        # Check if file exists
        if [[ ! -f "$pem_file" ]]; then
            echo "Error: File not found: $pem_file" >&2
            exit 1
        fi

        # Validate it's a valid EC key
        if ! openssl ec -in "$pem_file" -noout 2>/dev/null; then
            echo "Error: Invalid EC key in PEM file: $pem_file" >&2
            exit 1
        fi

        # Convert to JWK
        build_ec_jwk "$pem_file"
    fi
}

# Run main function
main "$@"
