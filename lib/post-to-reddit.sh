#!/bin/bash
# Reddit posting script for CMO automation
# Usage: ./post-to-reddit.sh "subreddit" "title" "content"

set -e

SUBREDDIT="$1"
TITLE="$2"
CONTENT="$3"

if [[ -z "$SUBREDDIT" || -z "$TITLE" || -z "$CONTENT" ]]; then
    echo "Usage: $0 <subreddit> <title> <content>"
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

if [[ -z "$REDDIT_CLIENT_ID" ]]; then
    echo "Error: Reddit credentials not found"
    exit 1
fi

# Get Reddit OAuth token
TOKEN=$(curl -s -X POST \
    -d "grant_type=password&username=$REDDIT_USERNAME&password=$REDDIT_PASSWORD" \
    --user "$REDDIT_CLIENT_ID:$REDDIT_CLIENT_SECRET" \
    -H "User-Agent: ClaudeAgenticFiles:v1.0 (by u/$REDDIT_USERNAME)" \
    https://www.reddit.com/api/v1/access_token | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    echo "Error: Reddit authentication failed"
    exit 1
fi

# Post to Reddit
RESPONSE=$(curl -s -X POST \
    -H "User-Agent: ClaudeAgenticFiles:v1.0 (by u/$REDDIT_USERNAME)" \
    -H "Authorization: bearer $TOKEN" \
    -d "sr=$SUBREDDIT&kind=self&title=$TITLE&text=$CONTENT&api_type=json" \
    https://oauth.reddit.com/api/submit)

# Check for errors
ERRORS=$(echo "$RESPONSE" | jq -r '.json.errors[]? // empty')
if [[ -n "$ERRORS" ]]; then
    echo "Error posting to Reddit: $ERRORS"
    exit 1
fi

# Extract and return post URL
POST_URL=$(echo "$RESPONSE" | jq -r '.json.data.url // empty')
if [[ -n "$POST_URL" ]]; then
    echo "✅ Posted to r/$SUBREDDIT: https://reddit.com$POST_URL"
else
    echo "Error: Could not extract post URL"
    exit 1
fi