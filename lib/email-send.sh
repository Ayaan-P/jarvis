#!/bin/bash
# Email sending script for ccOS agents
# Usage: ./email-send.sh "to@email.com" "subject" "html_content" "from_agent"

set -e

TO_EMAIL="$1"
SUBJECT="$2"
HTML_CONTENT="$3"
FROM_AGENT="${4:-briefing}"

if [[ -z "$TO_EMAIL" || -z "$SUBJECT" || -z "$HTML_CONTENT" ]]; then
    echo "Usage: $0 <to_email> <subject> <html_content> [from_agent]"
    exit 1
fi

# Find and load environment variables
ENV_PATHS=(
    "./.env"
    "../Claude-Agentic-Files/.env"
    "/home/ayaan/Projects/Claude-Agentic-Files.env"
    "$HOME/.env"
)

for env_path in "${ENV_PATHS[@]}"; do
    if [[ -f "$env_path" ]]; then
        source "$env_path"
        break
    fi
done

if [[ -z "$RESEND_API_KEY" ]]; then
    echo "Error: RESEND_API_KEY not found in environment"
    exit 1
fi

# Set from email based on agent
DOMAIN="dytto.app"
case "$FROM_AGENT" in
    "cmo") FROM_EMAIL="cmo@$DOMAIN" ;;
    "cfo") FROM_EMAIL="cfo@$DOMAIN" ;;
    "cpo") FROM_EMAIL="cpo@$DOMAIN" ;;
    "cto") FROM_EMAIL="cto@$DOMAIN" ;;
    "crisis") FROM_EMAIL="crisis@$DOMAIN" ;;
    *) FROM_EMAIL="briefing@$DOMAIN" ;;
esac

# Send email via Resend API
RESPONSE=$(curl -s -X POST \
    "https://api.resend.com/emails" \
    -H "Authorization: Bearer $RESEND_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"from\": \"$FROM_EMAIL\",
        \"to\": [\"$TO_EMAIL\"],
        \"subject\": \"$SUBJECT\",
        \"html\": $(echo "$HTML_CONTENT" | jq -Rs .)
    }")

# Check for errors
if echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message')
    echo "Error sending email: $ERROR_MSG"
    exit 1
fi

# Extract email ID
EMAIL_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
if [[ -n "$EMAIL_ID" ]]; then
    echo "✅ Email sent successfully from $FROM_EMAIL to $TO_EMAIL (ID: $EMAIL_ID)"
else
    echo "Error: Could not extract email ID from response"
    echo "Response: $RESPONSE"
    exit 1
fi