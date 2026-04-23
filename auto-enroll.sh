#!/usr/bin/env bash

set -eo pipefail

##########################################################################################
# Author: Amin Abbaspour
# Date: 2022-06-12
# License: MIT (https://github.com/abbaspour/guardian-bash/blob/master/LICENSE)
##########################################################################################

# Prerequisites:
# 1. Enabled Actions can control MFA context in Multifactor setting
#   Manage > Security > Multi-factor Auth > Additional Settings > Customize MFA Factors using Actions
# 2. Application with ROPG and MFA grants
# 3. Post-login Action that triggers MFA on ROPG grant for this application
#   Sample at:
# 4. Users that authenticate against token endpoint (ROPG, RT, Passkey)

# For more generic version of this see https://github.com/abbaspour/auth0-bash/blob/master/multifactor/
# - `./01-start-flow.sh`
# - `./02-start-associate.sh`
# - `./03-complete-challenge.sh`
# This script is a combined version above tailored for PN

command -v curl >/dev/null || { echo >&2 "error: curl not found";  exit 3; }
command -v jq >/dev/null || {  echo >&2 "error: jq not found";  exit 3; }
readonly DIR=$(dirname "${BASH_SOURCE[0]}")

declare AUTH0_SCOPE='openid profile email'
declare AUTH0_CONNECTION='Username-Password-Authentication'

PUBLIC_KEY_PEM="${DIR}/private.pem"

function usage() {
    cat <<END >&2
USAGE: $0 [-e env] [-t tenant] [-d domain] [-c client_id] [-x client_secret] [-u username] [-p passsword] [-a audience] [-r connection] [-s scope] [-g FCM_TOKEN] [-f KEY_PEM] [-m|-h|-v]
        -e file        # .env file location (default cwd)
        -t tenant      # Auth0 tenant@region
        -u username    # Username or email
        -p password    # Password
        -d domain      # Auth0 domain
        -c client_id   # Auth0 client ID
        -x secret      # Auth0 client secret
        -a audience    # Audience
        -r realm       # Connection (default is "${AUTH0_CONNECTION}")
        -s scopes      # comma separated list of scopes (default is "${AUTH0_SCOPE}")
        -m             # Management API audience
        -g FCM_TOKEN   # Firebase Cloud Messaging token from Android/iOS app
        -h|?           # usage
        -v             # verbose

eg,
     $0 -t amin01@au -c XXXX -u user -p pass
END
    exit $1
}

declare AUTH0_DOMAIN=''
declare AUTH0_CLIENT_ID=''
declare AUTH0_CLIENT_SECRET=''
declare AUTH0_AUDIENCE=''
declare FCM_TOKEN=''

declare username=''
declare password=''

declare opt_mgmnt=''
declare opt_verbose=0

# Load .env file if it exists
if [[ -f "${DIR}/.env" ]]; then
    set -a
    source "${DIR}/.env"
    set +a
fi

while getopts "e:t:u:p:d:c:x:a:r:s:g:f:mhv?" opt; do
    case ${opt} in
    e) source ${OPTARG} ;;
    t) AUTH0_DOMAIN=$(echo ${OPTARG}.auth0.com | tr '@' '.') ;;
    u) username=${OPTARG} ;;
    p) password=${OPTARG} ;;
    d) AUTH0_DOMAIN=${OPTARG} ;;
    c) AUTH0_CLIENT_ID=${OPTARG} ;;
    x) AUTH0_CLIENT_SECRET=${OPTARG} ;;
    a) AUTH0_AUDIENCE=${OPTARG} ;;
    r) AUTH0_CONNECTION=${OPTARG} ;;
    s) AUTH0_SCOPE=$(echo ${OPTARG} | tr ',' ' ') ;;
    m) opt_mgmnt=1 ;;
    g) FCM_TOKEN="$OPTARG" ;;
    f) PUBLIC_KEY_PEM="$OPTARG" ;;
    v) opt_verbose=1 ;; #set -x;;
    h | ?) usage 0 ;;
    *) usage 1 ;;
    esac
done

[[ -z "${AUTH0_DOMAIN}" ]] && {  echo >&2 "ERROR: AUTH0_DOMAIN undefined";  usage 1;  }
[[ -z "${AUTH0_CLIENT_ID}" ]] && { echo >&2 "ERROR: AUTH0_CLIENT_ID undefined";  usage 1; }

[[ -z "${username}" ]] && { echo >&2 "ERROR: username undefined";  usage 1; }
[[ -z "${FCM_TOKEN}" ]] && { echo >&2 "ERROR: FCM_TOKEN undefined";  usage 1; }

[[ -z "${AUTH0_AUDIENCE}" ]] && AUTH0_AUDIENCE="https://${AUTH0_DOMAIN}/userinfo"
[[ -n "${opt_mgmnt}" ]] && AUTH0_AUDIENCE="https://${AUTH0_DOMAIN}/api/v2/"

# Check if public key file exists
if [[ ! -f "$PUBLIC_KEY_PEM" ]]; then
    echo "Error: Public key file not found: $PUBLIC_KEY_PEM" >&2
    exit 1
fi

declare secret=''
[[ -n "${AUTH0_CLIENT_SECRET}" ]] && secret="\"client_secret\": \"${AUTH0_CLIENT_SECRET}\","

declare BODY=$(cat <<EOL
{
            "grant_type": "http://auth0.com/oauth/grant-type/password-realm",
            "realm" : "${AUTH0_CONNECTION}",
            "client_id": "${AUTH0_CLIENT_ID}",
            ${secret}
            "scope": "${AUTH0_SCOPE}",
            "audience": "${AUTH0_AUDIENCE}",
            "username": "${username}",
            "password": "${password}"
}
EOL
)

declare mfa_token=$(curl -s --header 'content-type: application/json' -d "${BODY}" "https://${AUTH0_DOMAIN}/oauth/token" | jq -r '.mfa_token // empty')

[[ -z "${mfa_token}" ]] && { echo >&2 "ERROR: unable to obtain mfa_token";  usage 2; }

echo "mfa_token=\"${mfa_token}\""

readonly BODY=$(cat <<EOL
{
    "authenticator_types": ["oob"],
    "oob_channels" : ["auth0"]
}
EOL
)

readonly response_json=$(curl -s -H "Authorization: Bearer ${mfa_token}" --header 'content-type: application/json' -d "${BODY}" "https://${AUTH0_DOMAIN}/mfa/associate")

barcode_uri=$(echo "${response_json}" | jq -r '.barcode_uri // empty')

[[ -z "${barcode_uri}" ]] && { echo >&2 "ERROR: unable to obtain barcode_uri";  usage 2; }

enrollment=$(echo "${barcode_uri}" | egrep -E "enrollment_tx_id=(\w+)" -o)
echo "enrollment: ${enrollment}"

readonly enrollment_tx_id=$(echo "${enrollment}" | sed -n 's/enrollment_tx_id=\(.*\)/\1/p')
echo "enrollment_tx_id: ${enrollment_tx_id}"

readonly DEVICE_ID="auto01"

./enroll-device.sh -d "${AUTH0_DOMAIN}"  -t "${enrollment_tx_id}" -i "${DEVICE_ID}" -n "${DEVICE_ID}" -g "${FCM_TOKEN}" -f "${PUBLIC_KEY_PEM}" -a "${AUTH0_CLIENT_ID}"
