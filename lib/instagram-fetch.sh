#!/bin/bash
# Instagram Business API Integration
# Usage: ./instagram-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  account-info          - Get basic account information"
    echo "  media-recent          - Get recent media posts"
    echo "  media-insights        - Get insights for media"
    echo "  account-insights      - Get account-level insights"
    echo "  audience-insights     - Get audience demographics"
    echo ""
    echo "Examples:"
    echo "  $0 account-info"
    echo "  $0 media-recent 'limit=10'"
    echo "  $0 media-insights 'media_id=12345'"
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

if [[ -z "$INSTAGRAM_ACCESS_TOKEN" ]]; then
    echo "Error: INSTAGRAM_ACCESS_TOKEN not found in environment"
    echo "Please add your Instagram Business API access token to .env file:"
    echo "INSTAGRAM_ACCESS_TOKEN=your_token_here"
    exit 1
fi

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
instagram_api_call() {
    local endpoint="$1"
    local query_params="$2"
    local url="https://graph.instagram.com/${endpoint}"
    
    if [[ -n "$query_params" ]]; then
        url="${url}?${query_params}"
    fi
    
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $INSTAGRAM_ACCESS_TOKEN" \
        "$url")
    
    http_code=${response: -3}
    response=${response%???}
    
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        echo "$response" | jq '.'
        return 0
    elif [[ $http_code -eq 429 ]]; then
        log_error "Rate limit exceeded (HTTP $http_code)"
        return 1
    else
        log_error "API call failed with HTTP $http_code"
        if command -v jq >/dev/null 2>&1; then
            echo "$response" | jq '.' >&2 || echo "$response" >&2
        else
            echo "$response" >&2
        fi
        return 1
    fi
}

# Action implementations
case "$ACTION" in
    "account-info")
        log_info "Fetching Instagram account information"
        retry_with_backoff instagram_api_call "me" "fields=id,username,account_type,media_count,followers_count"
        ;;
        
    "media-recent")
        log_info "Fetching recent Instagram media"
        local limit="${PARAMS:-limit=25}"
        retry_with_backoff instagram_api_call "me/media" "fields=id,caption,media_type,media_url,permalink,timestamp,like_count,comments_count&${limit}"
        ;;
        
    "media-insights")
        if [[ -z "$PARAMS" || ! "$PARAMS" =~ media_id= ]]; then
            log_error "media_id parameter required for media-insights"
            echo "Usage: $0 media-insights 'media_id=12345'"
            exit 1
        fi
        
        local media_id
        media_id=$(echo "$PARAMS" | sed -n 's/.*media_id=\([^&]*\).*/\1/p')
        
        log_info "Fetching insights for media ID: $media_id"
        retry_with_backoff instagram_api_call "${media_id}/insights" "metric=impressions,reach,engagement,saved,video_views"
        ;;
        
    "account-insights")
        log_info "Fetching Instagram account insights"
        local period="${PARAMS:-period=day}"
        local since_date=$(date -d '30 days ago' '+%Y-%m-%d')
        local until_date=$(date '+%Y-%m-%d')
        
        retry_with_backoff instagram_api_call "me/insights" "metric=impressions,reach,profile_views,website_clicks&${period}&since=${since_date}&until=${until_date}"
        ;;
        
    "audience-insights")
        log_info "Fetching Instagram audience insights"
        local period="${PARAMS:-period=lifetime}"
        
        retry_with_backoff instagram_api_call "me/insights" "metric=audience_gender_age,audience_locale,audience_country,audience_city&${period}"
        ;;
        
    "hashtag-search")
        if [[ -z "$PARAMS" || ! "$PARAMS" =~ hashtag= ]]; then
            log_error "hashtag parameter required for hashtag-search"
            echo "Usage: $0 hashtag-search 'hashtag=marketing'"
            exit 1
        fi
        
        local hashtag
        hashtag=$(echo "$PARAMS" | sed -n 's/.*hashtag=\([^&]*\).*/\1/p')
        
        log_info "Searching for hashtag: #$hashtag"
        retry_with_backoff instagram_api_call "ig_hashtag_search" "user_id=me&q=${hashtag}"
        ;;
        
    "engagement-rate")
        log_info "Calculating engagement rate from recent posts"
        
        # Get recent media with engagement data
        local media_response
        media_response=$(retry_with_backoff instagram_api_call "me/media" "fields=id,like_count,comments_count&limit=10")
        
        if [[ $? -eq 0 ]]; then
            # Calculate average engagement
            echo "$media_response" | jq -r '
                .data as $posts | 
                ($posts | map(.like_count + .comments_count) | add / length) as $avg_engagement |
                {
                    "average_engagement_per_post": $avg_engagement,
                    "total_posts_analyzed": ($posts | length),
                    "engagement_data": $posts
                }'
        fi
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: account-info, media-recent, media-insights, account-insights, audience-insights, hashtag-search, engagement-rate"
        exit 1
        ;;
esac