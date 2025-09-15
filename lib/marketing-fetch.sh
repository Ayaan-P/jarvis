#!/bin/bash
# Unified Marketing API Dispatcher
# Usage: ./marketing-fetch.sh <platform> <action> [params]

set -e

PLATFORM="$1"
ACTION="$2"
PARAMS="$3"

if [[ -z "$PLATFORM" || -z "$ACTION" ]]; then
    echo "Usage: $0 <platform> <action> [params]"
    echo "Platforms: instagram, stripe, ga4, google-ads, openai, google-trends, linkedin"
    echo "Example: $0 instagram me/media 'fields=id,caption,like_count'"
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

# Utility functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Exponential backoff retry function
retry_with_backoff() {
    local max_attempts=5
    local delay=1
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_info "Attempt $attempt failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    
    log_error "All $max_attempts attempts failed"
    return 1
}

# API call wrapper with error handling
api_call() {
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" "$@")
    http_code=${response: -3}
    response=${response%???}
    
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        echo "$response"
        return 0
    elif [[ $http_code -eq 429 ]]; then
        log_error "Rate limit exceeded (HTTP $http_code)"
        return 1
    else
        log_error "API call failed with HTTP $http_code: $response"
        return 1
    fi
}

# Platform-specific implementations
case "$PLATFORM" in
    "instagram")
        if [[ -z "$INSTAGRAM_ACCESS_TOKEN" ]]; then
            log_error "INSTAGRAM_ACCESS_TOKEN not found in environment"
            exit 1
        fi
        
        log_info "Fetching Instagram data: $ACTION"
        retry_with_backoff api_call \
            -H "Authorization: Bearer $INSTAGRAM_ACCESS_TOKEN" \
            "https://graph.instagram.com/$ACTION$([ -n "$PARAMS" ] && echo "?$PARAMS")"
        ;;
        
    "stripe")
        if [[ -z "$STRIPE_API_KEY" ]]; then
            log_error "STRIPE_API_KEY not found in environment"
            exit 1
        fi
        
        log_info "Fetching Stripe data: $ACTION"
        retry_with_backoff api_call \
            -H "Authorization: Bearer $STRIPE_API_KEY" \
            "https://api.stripe.com/v1/$ACTION$([ -n "$PARAMS" ] && echo "?$PARAMS")"
        ;;
        
    "ga4")
        if [[ -z "$GA4_SERVICE_ACCOUNT_JSON" ]]; then
            log_error "GA4_SERVICE_ACCOUNT_JSON not found in environment"
            exit 1
        fi
        
        log_info "GA4 integration requires Python client library - calling ga4-fetch.sh"
        exec "$(dirname "$0")/ga4-fetch.sh" "$ACTION" "$PARAMS"
        ;;
        
    "google-ads")
        if [[ -z "$GOOGLE_ADS_DEVELOPER_TOKEN" ]]; then
            log_error "GOOGLE_ADS_DEVELOPER_TOKEN not found in environment"
            exit 1
        fi
        
        log_info "Google Ads integration requires OAuth - calling google-ads-fetch.sh"
        exec "$(dirname "$0")/google-ads-fetch.sh" "$ACTION" "$PARAMS"
        ;;
        
    "openai")
        if [[ -z "$OPENAI_API_KEY" ]]; then
            log_error "OPENAI_API_KEY not found in environment"
            exit 1
        fi
        
        log_info "Generating content with OpenAI: $ACTION"
        retry_with_backoff api_call \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$PARAMS" \
            "https://api.openai.com/v1/$ACTION"
        ;;
        
    "google-trends")
        if [[ -z "$GOOGLE_TRENDS_API_KEY" ]]; then
            log_error "Google Trends API not yet available (Alpha access required)"
            exit 1
        fi
        
        log_info "Fetching Google Trends data: $ACTION"
        retry_with_backoff api_call \
            -H "Authorization: Bearer $GOOGLE_TRENDS_API_KEY" \
            "https://api.googletrends.com/v1/$ACTION$([ -n "$PARAMS" ] && echo "?$PARAMS")"
        ;;
        
    "dytto-blog")
        if [[ -z "$VITE_SUPABASE_URL" || -z "$SUPABASE_SERVICE_ROLE_KEY" ]]; then
            log_error "Dytto blog credentials not found in environment"
            exit 1
        fi
        
        log_info "Dytto blog action: $ACTION"
        exec "$(dirname "$0")/dytto-blog-fetch.sh" "$ACTION" "$PARAMS"
        ;;
        
    "linkedin")
        if [[ -z "$LINKEDIN_CLIENT_ID" || -z "$LINKEDIN_CLIENT_SECRET" ]]; then
            log_error "LinkedIn credentials not found in environment"
            exit 1
        fi
        
        log_info "LinkedIn action: $ACTION"
        exec "$(dirname "$0")/linkedin-fetch.sh" "$ACTION" "$PARAMS"
        ;;
        
    *)
        log_error "Unknown platform: $PLATFORM"
        echo "Supported platforms: instagram, stripe, ga4, google-ads, openai, google-trends, dytto-blog, linkedin"
        exit 1
        ;;
esac