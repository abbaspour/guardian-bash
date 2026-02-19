#!/usr/bin/env bash

##########################################################################################
# Author: Amin Abbaspour
# Date: 2026-01-21
# License: MIT (https://github.com/abbaspour/guardian-bash/blob/master/LICENSE)
##########################################################################################

# Guardian SNS Message Listener
# Polls AWS SQS queue for Guardian push notification messages from SNS
# Displays incoming messages in a readable format

set -euo pipefail

readonly DIR=$(dirname "${BASH_SOURCE[0]}")

# Default values
QUEUE_URL=""
REGION=""
WAIT_TIME=20
MAX_MESSAGES=10
DELETE_AFTER_READ=false
PRETTY_PRINT=true
AWS_PROFILE=amin

function usage() {
  cat <<END >&2
USAGE: $0 [-q queue-url] [-r region] [-w wait-time] [-m max-messages] [-d] [-p] [-h]
        -q queue-url    # SQS queue URL (required, or set SQS_QUEUE_URL env var)
        -r region       # AWS region (default: from AWS config or us-east-1)
        -w wait-time    # Long polling wait time in seconds (default: 20, max: 20)
        -m max-messages # Maximum messages to retrieve per request (default: 10, max: 10)
        -d              # Delete messages after reading (default: keep messages)
        -p              # Pretty print JSON (default: true, use -P to disable)
        -P              # Disable pretty printing
        -h|?            # Show this help message

Environment Variables:
        SQS_QUEUE_URL   # SQS queue URL (alternative to -q)
        AWS_REGION      # AWS region (alternative to -r)

Examples:
        # Listen with queue URL from terraform output
        $0 -q \$(cd tf && terraform output -raw sqs_queue_url)

        # Listen and delete messages after reading
        $0 -q https://sqs.ap-southeast-2.amazonaws.com/123456789/guardian-listener -d

        # Listen with custom wait time
        $0 -q \$SQS_QUEUE_URL -w 10 -m 5

END
  exit $1
}

# Load .env file if it exists
if [[ -f "${DIR}/.env" ]]; then
  # shellcheck source=/dev/null
  source "${DIR}/.env"
fi

while getopts "q:r:w:m:dPph?" opt; do
  case ${opt} in
  q) QUEUE_URL=${OPTARG} ;;
  r) REGION=${OPTARG} ;;
  w) WAIT_TIME=${OPTARG} ;;
  m) MAX_MESSAGES=${OPTARG} ;;
  d) DELETE_AFTER_READ=true ;;
  p) PRETTY_PRINT=true ;;
  P) PRETTY_PRINT=false ;;
  h | ?) usage 0 ;;
  *) usage 1 ;;
  esac
done

# Check for queue URL from environment if not provided
[[ -z "${QUEUE_URL}" ]] && QUEUE_URL="${SQS_QUEUE_URL:-}"
[[ -z "${QUEUE_URL}" ]] && {
  echo >&2 "ERROR: Queue URL not provided. Use -q flag or set SQS_QUEUE_URL environment variable"
  usage 1
}

# Check for region from environment if not provided
[[ -z "${REGION}" ]] && REGION="${AWS_REGION:-us-east-1}"

# Validate wait time (max 20 seconds for SQS long polling)
if [[ ${WAIT_TIME} -gt 20 ]]; then
  echo >&2 "WARNING: Wait time cannot exceed 20 seconds. Setting to 20."
  WAIT_TIME=20
fi

# Validate max messages (max 10 for SQS)
if [[ ${MAX_MESSAGES} -gt 10 ]]; then
  echo >&2 "WARNING: Max messages cannot exceed 10. Setting to 10."
  MAX_MESSAGES=10
fi

# Check for required commands
command -v aws >/dev/null || {
  echo >&2 "ERROR: aws CLI not found. Please install AWS CLI."
  exit 3
}

command -v jq >/dev/null || {
  echo >&2 "ERROR: jq not found. Please install jq for JSON processing."
  exit 3
}

echo "=== Guardian SNS Message Listener ==="
echo "Queue URL: ${QUEUE_URL}"
echo "Region: ${REGION}"
echo "Wait Time: ${WAIT_TIME}s"
echo "Max Messages: ${MAX_MESSAGES}"
echo "Delete After Read: ${DELETE_AFTER_READ}"
echo "=================================="
echo ""
echo "Listening for messages... (Ctrl+C to stop)"
echo ""

MESSAGE_COUNT=0

# Function to display a message
display_message() {
  local message_body=$1
  local receipt_handle=$2
  local message_id=$3

  MESSAGE_COUNT=$((MESSAGE_COUNT + 1))

  echo "----------------------------------------"
  echo "Message #${MESSAGE_COUNT} (ID: ${message_id})"
  echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "----------------------------------------"

  # Check if message body contains SNS envelope
  if echo "${message_body}" | jq -e '.Type' >/dev/null 2>&1; then
    local message_type=$(echo "${message_body}" | jq -r '.Type')

    echo "SNS Message Type: ${message_type}"

    if [[ "${message_type}" == "Notification" ]]; then
      local sns_message=$(echo "${message_body}" | jq -r '.Message')
      local sns_subject=$(echo "${message_body}" | jq -r '.Subject // "N/A"')
      local sns_timestamp=$(echo "${message_body}" | jq -r '.Timestamp')
      local sns_topic_arn=$(echo "${message_body}" | jq -r '.TopicArn')

      echo "SNS Subject: ${sns_subject}"
      echo "SNS Timestamp: ${sns_timestamp}"
      echo "SNS Topic: ${sns_topic_arn}"
      echo ""
      echo "Message Content:"

      # Try to parse inner message as JSON
      if echo "${sns_message}" | jq -e '.' >/dev/null 2>&1; then
        if [[ "${PRETTY_PRINT}" == "true" ]]; then
          echo "${sns_message}" | jq '.'
        else
          echo "${sns_message}"
        fi
      else
        # Not JSON, display as plain text
        echo "${sns_message}"
      fi
    elif [[ "${message_type}" == "SubscriptionConfirmation" ]]; then
      echo "⚠️  SNS Subscription Confirmation Required"
      local subscribe_url=$(echo "${message_body}" | jq -r '.SubscribeURL')
      echo "Subscribe URL: ${subscribe_url}"
      echo ""
      echo "To confirm subscription, visit the URL above or run:"
      echo "curl -X GET '${subscribe_url}'"
    fi
  else
    # Not an SNS envelope, display raw message
    echo "Raw Message:"
    if [[ "${PRETTY_PRINT}" == "true" ]] && echo "${message_body}" | jq -e '.' >/dev/null 2>&1; then
      echo "${message_body}" | jq '.'
    else
      echo "${message_body}"
    fi
  fi

  echo ""

  # Delete message if requested
  if [[ "${DELETE_AFTER_READ}" == "true" ]]; then
    echo "Deleting message..."
    aws sqs delete-message \
      --profile "${AWS_PROFILE}" \
      --region "${REGION}" \
      --queue-url "${QUEUE_URL}" \
      --receipt-handle "${receipt_handle}" 2>/dev/null || {
      echo >&2 "WARNING: Failed to delete message"
    }
    echo "✓ Message deleted"
    echo ""
  fi
}

# Main polling loop
while true; do
  # Receive messages from SQS
  RESPONSE=$(aws sqs receive-message \
    --profile "${AWS_PROFILE}" \
    --region "${REGION}" \
    --queue-url "${QUEUE_URL}" \
    --max-number-of-messages "${MAX_MESSAGES}" \
    --wait-time-seconds "${WAIT_TIME}" \
    --output json 2>/dev/null) || {
    echo >&2 "ERROR: Failed to receive messages from SQS"
    sleep 5
    continue
  }

  # Check if any messages were received
  MESSAGE_ARRAY=$(echo "${RESPONSE}" | jq -r '.Messages // []')
  NUM_MESSAGES=$(echo "${MESSAGE_ARRAY}" | jq 'length')

  if [[ "${NUM_MESSAGES}" -gt 0 ]]; then
    # Process each message
    for i in $(seq 0 $((NUM_MESSAGES - 1))); do
      MESSAGE_BODY=$(echo "${MESSAGE_ARRAY}" | jq -r ".[$i].Body")
      RECEIPT_HANDLE=$(echo "${MESSAGE_ARRAY}" | jq -r ".[$i].ReceiptHandle")
      MESSAGE_ID=$(echo "${MESSAGE_ARRAY}" | jq -r ".[$i].MessageId")

      display_message "${MESSAGE_BODY}" "${RECEIPT_HANDLE}" "${MESSAGE_ID}"
    done
  else
    # No messages received in this poll (long polling timeout)
    echo -n "."
  fi
done
