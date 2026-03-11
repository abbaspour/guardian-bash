#!/usr/bin/env bash
set -euo pipefail

##########################################################################################
# pem-to-jwk.sh - Convert RSA PEM files to JWK (JSON Web Key) format
#
# Usage:
#   ./pem-to-jwk.sh <pem-file>       # Convert from file
#   ./pem-to-jwk.sh -                # Read from stdin
#   ./pem-to-jwk.sh                  # Read from stdin
#   cat public.pem | ./pem-to-jwk.sh # Pipe from stdin
#
# Examples:
#   ./pem-to-jwk.sh public.pem
#   ./pem-to-jwk.sh public.pem | jq '.n'
#   cat public.pem | ./pem-to-jwk.sh | jq -r '.n, .e'
#
# Requirements:
#   - openssl: For RSA key operations
#   - jq: For JSON generation
#   - xxd: For hex-to-binary conversion
##########################################################################################

usage() {
    cat <<EOF
Usage: $(basename "$0") [PEM_FILE]

Convert RSA PEM files (public or private keys) to JWK (JSON Web Key) format.

Arguments:
  PEM_FILE    Path to PEM file (optional, reads from stdin if omitted or "-")

Options:
  -h, --help  Show this help message

Examples:
  $(basename "$0") public.pem              # Convert from file
  $(basename "$0") -                       # Read from stdin
  cat public.pem | $(basename "$0")        # Pipe from stdin
  $(basename "$0") public.pem | jq '.n'    # Extract modulus

Output:
  JSON object with JWK fields: kty, alg, use, e (exponent), n (modulus)

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

        # Validate it's a valid RSA key
        if ! openssl rsa -pubin -in "$temp_file" -noout 2>/dev/null; then
            echo "Error: Invalid RSA key in PEM input" >&2
            exit 1
        fi

        # Convert to JWK
        build_public_key_jwk "$temp_file"

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

        # Validate it's a valid RSA key
        if ! openssl rsa -pubin -in "$pem_file" -noout 2>/dev/null; then
            echo "Error: Invalid RSA key in PEM file: $pem_file" >&2
            exit 1
        fi

        # Convert to JWK
        build_public_key_jwk "$pem_file"
    fi
}

# Run main function
main "$@"
