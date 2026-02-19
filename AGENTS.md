# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Guardian Push is a collection of bash scripts that interact with the Auth0 Guardian API for multi-factor authentication (MFA). The project enables device enrollment, push notification handling, and transaction resolution for Auth0 Guardian MFA.

## Key Scripts

### enroll.sh
Enrolls or unenrolls a device to Guardian push notifications. This script:
- Requires an enrollment ticket from Auth0
- Supports both GCM (Google Cloud Messaging) and APNS (Apple Push Notification Service)
- Needs a client public key in PEM format (uses `create-jwk.sh` to convert to JWK format)
- Sends enrollment request to Auth0 Guardian API

Example usage pattern:
```bash
./enroll-device.sh -t <tenant> -l <enrollment-ticket> -i <device-identifier> -n <device-name> -g <gcm-token> -f <public.pem>
```

### resolve-transaction.sh
Resolves (allows/rejects) Guardian MFA transactions. This script:
- Mimics Guardian.Android SDK behavior
- Creates and signs JWT tokens using RS256 with a private RSA key
- Handles both Guardian-hosted domains (*.guardian.*.auth0.com) and custom domains
- Automatically adds `/appliance-mfa` prefix for custom domains, but not for Guardian-hosted domains
- Requires challenge, domain, device ID, private key, and transaction token
- Rejects transactions when `-R` flag is provided with a reason

Example usage pattern:
```bash
# Allow transaction
./resolve-transaction.sh -c <challenge> -d <domain> -i <device-id> -k <private-key.pem> -t <txtkn>

# Reject transaction
./resolve-transaction.sh -c <challenge> -d <domain> -i <device-id> -k <private-key.pem> -t <txtkn> -R "Suspicious login"
```

### scan-qr.sh
Utility for extracting enrollment data from QR codes using screen capture. Requires `zbar` package (`brew install zbar` on macOS). Extracts `enrollment_tx_id` and `secret` parameters from QR code data.

## Infrastructure (tf/ directory)

The `tf/` directory contains Terraform configurations for deploying AWS SNS and Auth0 resources needed for Guardian push notifications.

### Terraform Commands (via Makefile)
```bash
cd tf/

# Initialize Terraform
make init

# Plan changes
make plan

# Apply changes
make apply

# Show current state
make show

# View API logs (AWS CloudWatch)
make logs-api

# Generate dependency graph
make graph
```

### Terraform Configuration
- **Providers**: AWS (~> 6.28) and Auth0 (~> 1.38)
- **Region**: Default is ap-southeast-2 (can be overridden in terraform.auto.tfvars)
- **Auth0 variables**: Requires auth0_domain, auth0_tf_client_id, and auth0_tf_client_secret
- **Guardian app name**: Defaults to "auth0-bash"

The Makefile includes logic to detect hostname and prefix commands with `gk e -p pro-services-dev --` for specific environments.

## Architecture Notes

### Authentication Flow
1. User initiates Guardian enrollment via Auth0
2. QR code contains enrollment ticket and secret
3. `enroll-device.sh` registers device with push credentials (GCM/APNS token) and public key
4. When MFA is triggered, Guardian sends push notification with challenge and transaction token
5. `resolve-transaction.sh` creates signed JWT and sends allow/reject decision

### JWT Structure for Transaction Resolution
- **Header**: RS256 algorithm
- **Payload**: Contains iat, exp, aud (API endpoint), iss (device ID), sub (challenge), auth0_guardian_method ("push"), auth0_guardian_accepted (boolean), and optional auth0_guardian_reason (for rejections)
- **Signature**: Signed with device's private RSA key

### Domain Handling
Guardian-hosted domains (*.guardian.*.auth0.com) use direct `/api/resolve-transaction` endpoint, while custom domains require `/appliance-mfa/api/resolve-transaction` path.

## Dependencies

### Required Tools
- `bash` - Shell scripts require bash
- `curl` - For API requests
- `jq` - JSON processing
- `openssl` - Cryptographic operations (JWT signing, base64url encoding)
- `zbar` (specifically `zbarimg`) - QR code scanning (for scan-qr.sh)
- `screencapture` - macOS screenshot utility (for scan-qr.sh)
- `terraform` - Infrastructure provisioning (in tf/ directory)

### Environment Variables
Scripts support loading environment variables from `.env` file in the project directory. Common variables:
- `AUTH0_DOMAIN` - Auth0 tenant domain
- Device credentials and tokens passed via command-line flags

## Testing Scripts

To test scripts locally, you'll need:
1. Valid Auth0 Guardian enrollment ticket
2. RSA key pair (private key for transaction resolution, public key for enrollment)
3. Device push notification token (GCM or APNS)
4. For transaction resolution: challenge and transaction token from an actual Guardian push notification
