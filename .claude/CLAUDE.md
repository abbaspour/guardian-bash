# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Guardian Push is a collection of bash scripts that interact with the Auth0 Guardian API for MFA. It supports the full device lifecycle: enrollment, push notification receipt, transaction resolution (allow/reject), and unenrollment. Companion Android and macOS (APNS) apps provide real FCM/APNS device tokens for testing.

## Script Inventory

| Script | Purpose |
|---|---|
| `enroll-device.sh` | Enroll a device using an enrollment ticket |
| `unenroll-device.sh` | Remove an enrolled device |
| `update-device.sh` | Update device name, identifier, or FCM token |
| `resolve-transaction.sh` | Allow or reject a Guardian MFA challenge |
| `rich-consents.sh` | Fetch rich consent data using DPoP auth |
| `auto-enroll.sh` | End-to-end ROPG → MFA associate → enroll |
| `scan-qr.sh` | Extract enrollment ticket from QR code via screen capture |
| `pem-to-jwk.js` | Node.js utility: convert RSA or EC PEM to JWK (used by enroll-device.sh) |

## Common Commands

```bash
# Generate RSA key pair
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem

# Generate EC P-256 key
openssl ecparam -genkey -name prime256v1 -noout -out ec-private.pem

# Enroll a device (FCM)
./enroll-device.sh -t <enrollment_tx_id> -d <tenant.auth0.com> -i <device-id> -n <device-name> -g <fcm-token> [-f private.pem]

# Resolve (allow) a transaction
./resolve-transaction.sh -c <challenge> -d <domain> -i <device-id> -t <txtkn> [-k private.pem]

# Reject a transaction
./resolve-transaction.sh -c <challenge> -d <domain> -i <device-id> -t <txtkn> -R "Reason"

# Unenroll a device
./unenroll-device.sh -d <domain> -i <device-id>

# Update FCM token
./update-device.sh -i <device-id> -g <new-fcm-token>

# Fetch rich consent
./rich-consents.sh -c <consent-id> -d <domain> -t <txtkn> -i <device-id> -k private.pem -f public.pem

# Auto enroll (ROPG flow)
./auto-enroll.sh -d <domain> -c <client-id> -x <client-secret> -u <username> -p <password> -g <fcm-token>
```

## Terraform (tf/)

```bash
cd tf/
make init    # terraform init
make plan    # terraform plan
make apply   # terraform apply
make show    # terraform show
make logs-api  # AWS CloudWatch logs
make graph   # dependency graph
```

Required `terraform.auto.tfvars`:
- `auth0_domain`, `auth0_tf_client_id`, `auth0_tf_client_secret`
- Optional: `sns_apns_platform_application_arn`, `sns_gcm_platform_application_arn`

The Makefile prefixes commands with `gk e -p pro-services-dev --` when run on specific internal hosts.

## APNS Companion App (apns/)

macOS Swift app that registers for remote notifications and prints the APNS device token to stdout.

```bash
cd apns/
make          # compile (requires swiftc, arm64-apple-macos11.0)
make sign     # codesign with push.entitlements (requires Apple Developer cert)
make run      # run the app — prints device token to stdout
```

Edit `MEMBER_ID` and `NAME` in the Makefile to match your Apple Developer account.

## Android Companion App (android/)

Android app (Java) that receives FCM tokens and Guardian push notifications, displaying them in the UI with a copy-to-clipboard button. Uses `GuardianMessagingService` extending `FirebaseMessagingService` to receive and broadcast incoming push payloads.

Build/run with Android Studio. Replace `android/app/google-services.json` (currently `old-google-services.json`) with your Firebase project's config.

## Architecture

### Enrollment Data Persistence
`enroll-device.sh` saves enrollment state to `.enrollments/{device_id}.json` containing `enrollment_id`, `device_token`, `domain`, and TOTP secret. `unenroll-device.sh` and `update-device.sh` read this file to authenticate requests. The `device_token` (Bearer auth) is distinct from the FCM/APNS push token.

### Key Type Auto-Detection
Both `enroll-device.sh` and `resolve-transaction.sh` auto-detect whether the key is RSA (RS256) or EC P-256 (ES256) by delegating to Node.js crypto APIs. `pem-to-jwk.js` is a required dependency of enrollment.

### Domain Routing Logic
All scripts share the same URL construction rule: domains matching `guardian.*\.auth0\.com` use the path directly; all other (custom) domains prepend `/appliance-mfa`. `rich-consents.sh` additionally strips `.guardian.` and `/appliance-mfa` from the domain since the rich-consents endpoint lives on the normalized tenant domain.

### DPoP Authentication (rich-consents.sh)
Rich consent fetches use `MFA-DPoP` scheme. The script creates a DPoP proof JWT (RS256) with `htu`, `htm=GET`, `jti` (UUID), `iat`, and `ath` (SHA-256 hash of the transaction token, base64url-encoded), signed with the device private key.

### ES256 JWT Signing
When signing with EC keys, openssl produces DER-encoded ECDSA output. `resolve-transaction.sh` converts DER → raw R+S (64 bytes) via inline Node.js, because the Guardian API expects the compact JWT-standard format.

## Dependencies

- `bash`, `curl`, `jq`, `openssl` — required by all scripts
- `node` — required by `enroll-device.sh` (pem-to-jwk.js) and `resolve-transaction.sh` (key-type detection, ES256 DER→raw conversion)
- `zbarimg` (`brew install zbar`) + `screencapture` — required by `scan-qr.sh`
- `terraform` — required for `tf/`
- `swiftc` — required to build the APNS app

## Environment

All scripts load `.env` from the script directory if present. `AUTH0_DOMAIN` can be set there to avoid passing `-d` every invocation. Device IDs are auto-detected when exactly one enrollment exists in `.enrollments/`.
