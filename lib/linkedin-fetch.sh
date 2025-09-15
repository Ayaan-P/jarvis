#!/bin/bash
# LinkedIn Marketing Integration
# Usage: ./linkedin-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  setup-check           - Verify LinkedIn API setup"
    echo "  auth-url             - Generate OAuth authorization URL"
    echo "  exchange-token       - Exchange authorization code for access token"
    echo "  refresh-token        - Refresh expired access token"
    echo "  profile-info         - Get current user/organization profile"
    echo "  company-pages        - Get managed company pages"
    echo "  create-post          - Create organic post on company page"
    echo "  create-post-from-file - Create post from file content"
    echo "  post-analytics       - Get post performance analytics"
    echo "  page-analytics       - Get company page analytics"
    echo "  follower-stats       - Get follower demographics and growth"
    echo "  engagement-metrics   - Get detailed engagement analysis"
    echo ""
    echo "Examples:"
    echo "  $0 setup-check"
    echo "  $0 auth-url 'redirect_uri=http://localhost:8080/callback'"
    echo "  $0 create-post 'company_id=12345&text=Hello LinkedIn!&visibility=PUBLIC'"
    echo "  $0 post-analytics 'post_id=urn:li:share:123456789'"
    exit 1
fi

# Environment variable loading
ENV_PATHS=(
    "/home/ayaan/Projects/Claude-Agentic-Files.env"
    "./.env"
    "../Claude-Agentic-Files/.env"
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

# Check for required environment variables
check_setup() {
    local setup_ok=true
    
    if [[ -z "$LINKEDIN_CLIENT_ID" ]]; then
        log_error "LINKEDIN_CLIENT_ID not found in environment"
        echo "Please add your LinkedIn Client ID to .env file:"
        echo "LINKEDIN_CLIENT_ID=your_client_id_here"
        setup_ok=false
    fi
    
    if [[ -z "$LINKEDIN_CLIENT_SECRET" ]]; then
        log_error "LINKEDIN_CLIENT_SECRET not found in environment"
        echo "Please add your LinkedIn Client Secret to .env file:"
        echo "LINKEDIN_CLIENT_SECRET=your_client_secret_here"
        setup_ok=false
    fi
    
    if [[ "$setup_ok" == "false" ]]; then
        echo ""
        echo "LinkedIn API Setup Guide:"
        echo "1. Go to https://developer.linkedin.com/"
        echo "2. Create new application"
        echo "3. Get Client ID and Client Secret"
        echo "4. Add redirect URI: http://localhost:8080/callback"
        echo "5. Request permissions: w_member_social, r_organization_social, rw_organization_admin"
        echo "6. Add credentials to .env file"
        return 1
    fi
    
    return 0
}

# Parse URL parameters into variables
parse_params() {
    if [[ -n "$PARAMS" ]]; then
        IFS='&' read -ra PARAM_ARRAY <<< "$PARAMS"
        for param in "${PARAM_ARRAY[@]}"; do
            if [[ $param =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                # URL decode value
                value=$(printf '%b' "${value//%/\\\\x}" | sed 's/+/ /g')
                declare -g "PARAM_$key"="$value"
            fi
        done
    fi
}

# LinkedIn API call wrapper
linkedin_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local api_version="${4:-202412}"
    
    local url="https://api.linkedin.com/v2/$endpoint"
    
    local curl_cmd=(
        curl -s -w "%{http_code}"
        -X "$method"
        -H "Authorization: Bearer $LINKEDIN_ACCESS_TOKEN"
        -H "Content-Type: application/json"
        -H "X-Restli-Protocol-Version: 2.0.0"
        -H "LinkedIn-Version: $api_version"
    )
    
    if [[ -n "$data" ]]; then
        curl_cmd+=(-d "$data")
    fi
    
    curl_cmd+=("$url")
    
    local response
    response=$("${curl_cmd[@]}")
    
    local http_code=${response: -3}
    response=${response%???}
    
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        echo "$response"
        return 0
    else
        log_error "LinkedIn API call failed with HTTP $http_code"
        if command -v jq >/dev/null 2>&1; then
            echo "$response" | jq '.' >&2 || echo "$response" >&2
        else
            echo "$response" >&2
        fi
        return 1
    fi
}

# Generate OAuth authorization URL
generate_auth_url() {
    local redirect_uri="$1"
    local scope="${2:-w_member_social,r_organization_social,rw_organization_admin}"
    local state="${3:-$(date +%s)}"
    
    local auth_url="https://www.linkedin.com/oauth/v2/authorization"
    auth_url="${auth_url}?response_type=code"
    auth_url="${auth_url}&client_id=${LINKEDIN_CLIENT_ID}"
    auth_url="${auth_url}&redirect_uri=${redirect_uri}"
    auth_url="${auth_url}&scope=${scope}"
    auth_url="${auth_url}&state=${state}"
    
    echo "$auth_url"
}

# Exchange authorization code for access token
exchange_auth_code() {
    local auth_code="$1"
    local redirect_uri="$2"
    
    local response
    response=$(curl -s -X POST "https://www.linkedin.com/oauth/v2/accessToken" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=authorization_code" \
        -d "code=$auth_code" \
        -d "redirect_uri=$redirect_uri" \
        -d "client_id=$LINKEDIN_CLIENT_ID" \
        -d "client_secret=$LINKEDIN_CLIENT_SECRET")
    
    echo "$response"
}

# Refresh access token
refresh_access_token() {
    local refresh_token="$1"
    
    local response
    response=$(curl -s -X POST "https://www.linkedin.com/oauth/v2/accessToken" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$refresh_token" \
        -d "client_id=$LINKEDIN_CLIENT_ID" \
        -d "client_secret=$LINKEDIN_CLIENT_SECRET")
    
    echo "$response"
}

# Create LinkedIn post with rich media support
create_linkedin_post() {
    local company_id="$1"
    local text="$2"
    local visibility="${3:-PUBLIC}"
    local media_url="${4:-}"
    local media_type="${5:-}"
    
    # Build post payload
    local author="urn:li:organization:$company_id"
    if [[ -z "$company_id" ]]; then
        # Use person URN if no company specified
        author="urn:li:person:$(get_profile_id)"
    fi
    
    local post_data
    if [[ -n "$media_url" ]]; then
        # Post with media
        case "$media_type" in
            "image")
                post_data=$(jq -n \
                    --arg author "$author" \
                    --arg text "$text" \
                    --arg visibility "$visibility" \
                    --arg media_url "$media_url" \
                    '{
                        author: $author,
                        lifecycleState: "PUBLISHED",
                        specificContent: {
                            "com.linkedin.ugc.ShareContent": {
                                shareCommentary: {
                                    text: $text
                                },
                                shareMediaCategory: "IMAGE",
                                media: [{
                                    status: "READY",
                                    description: {
                                        text: "Shared via LinkedIn API"
                                    },
                                    media: $media_url,
                                    title: {
                                        text: "Image Post"
                                    }
                                }]
                            }
                        },
                        visibility: {
                            "com.linkedin.ugc.MemberNetworkVisibility": $visibility
                        }
                    }')
                ;;
            "article")
                post_data=$(jq -n \
                    --arg author "$author" \
                    --arg text "$text" \
                    --arg visibility "$visibility" \
                    --arg media_url "$media_url" \
                    '{
                        author: $author,
                        lifecycleState: "PUBLISHED",
                        specificContent: {
                            "com.linkedin.ugc.ShareContent": {
                                shareCommentary: {
                                    text: $text
                                },
                                shareMediaCategory: "ARTICLE",
                                media: [{
                                    status: "READY",
                                    originalUrl: $media_url
                                }]
                            }
                        },
                        visibility: {
                            "com.linkedin.ugc.MemberNetworkVisibility": $visibility
                        }
                    }')
                ;;
            *)
                log_error "Unsupported media type: $media_type"
                return 1
                ;;
        esac
    else
        # Text-only post
        post_data=$(jq -n \
            --arg author "$author" \
            --arg text "$text" \
            --arg visibility "$visibility" \
            '{
                author: $author,
                lifecycleState: "PUBLISHED",
                specificContent: {
                    "com.linkedin.ugc.ShareContent": {
                        shareCommentary: {
                            text: $text
                        },
                        shareMediaCategory: "NONE"
                    }
                },
                visibility: {
                    "com.linkedin.ugc.MemberNetworkVisibility": $visibility
                }
            }')
    fi
    
    linkedin_api_call "POST" "ugcPosts" "$post_data"
}

# Get profile ID helper
get_profile_id() {
    if [[ -n "$LINKEDIN_PROFILE_ID" ]]; then
        echo "$LINKEDIN_PROFILE_ID"
    else
        local profile
        profile=$(linkedin_api_call "GET" "me")
        echo "$profile" | jq -r '.id' 2>/dev/null || echo ""
    fi
}

# Calculate engagement rate
calculate_engagement_rate() {
    local likes="$1"
    local comments="$2"
    local shares="$3"
    local impressions="$4"
    
    if [[ "$impressions" -gt 0 ]]; then
        local total_engagement=$((likes + comments + shares))
        local engagement_rate=$((total_engagement * 100 / impressions))
        echo "$engagement_rate"
    else
        echo "0"
    fi
}

# Parse parameters
parse_params

# Action implementations
case "$ACTION" in
    "setup-check")
        log_info "Checking LinkedIn API setup"
        
        if check_setup; then
            log_info "✅ LinkedIn API credentials are configured"
            
            if [[ -n "$LINKEDIN_ACCESS_TOKEN" ]]; then
                # Test API connectivity
                if linkedin_api_call "GET" "me" >/dev/null 2>&1; then
                    echo '{"status": "ready", "message": "LinkedIn integration is fully configured and authenticated"}'
                else
                    echo '{"status": "token_invalid", "message": "Access token is invalid or expired"}'
                fi
            else
                echo '{"status": "needs_auth", "message": "LinkedIn credentials configured but access token required"}'
            fi
        else
            echo '{"status": "incomplete", "message": "LinkedIn integration requires API credentials setup"}'
            exit 1
        fi
        ;;
        
    "auth-url")
        if ! check_setup; then
            exit 1
        fi
        
        redirect_uri="${PARAM_redirect_uri:-http://localhost:8080/callback}"
        scope="${PARAM_scope:-w_member_social,r_organization_social,rw_organization_admin}"
        
        log_info "Generating OAuth authorization URL"
        
        auth_url=$(generate_auth_url "$redirect_uri" "$scope")
        
        jq -n --arg auth_url "$auth_url" --arg redirect_uri "$redirect_uri" \
           '{
               auth_url: $auth_url,
               redirect_uri: $redirect_uri,
               instructions: [
                   "1. Visit the auth_url in your browser",
                   "2. Authorize the application",
                   "3. Copy the authorization code from redirect URL",
                   "4. Use exchange-token action with the code"
               ]
           }'
        ;;
        
    "exchange-token")
        if ! check_setup; then
            exit 1
        fi
        
        auth_code="${PARAM_code:-}"
        redirect_uri="${PARAM_redirect_uri:-http://localhost:8080/callback}"
        
        if [[ -z "$auth_code" ]]; then
            log_error "Authorization code required for token exchange"
            echo "Usage: $0 exchange-token 'code=your_auth_code&redirect_uri=http://localhost:8080/callback'"
            exit 1
        fi
        
        log_info "Exchanging authorization code for access token"
        
        response=$(exchange_auth_code "$auth_code" "$redirect_uri")
        
        if echo "$response" | jq -e '.access_token' >/dev/null 2>&1; then
            access_token=$(echo "$response" | jq -r '.access_token')
            expires_in=$(echo "$response" | jq -r '.expires_in')
            
            echo "Add this to your .env file:"
            echo "LINKEDIN_ACCESS_TOKEN=$access_token"
            echo ""
            echo "Token expires in $expires_in seconds"
            echo "$response"
        else
            log_error "Token exchange failed"
            echo "$response"
            exit 1
        fi
        ;;
        
    "refresh-token")
        if ! check_setup; then
            exit 1
        fi
        
        refresh_token="${PARAM_refresh_token:-$LINKEDIN_REFRESH_TOKEN}"
        
        if [[ -z "$refresh_token" ]]; then
            log_error "Refresh token required"
            echo "Usage: $0 refresh-token 'refresh_token=your_refresh_token'"
            exit 1
        fi
        
        log_info "Refreshing access token"
        
        response=$(refresh_access_token "$refresh_token")
        
        if echo "$response" | jq -e '.access_token' >/dev/null 2>&1; then
            access_token=$(echo "$response" | jq -r '.access_token')
            echo "New access token: $access_token"
            echo "$response"
        else
            log_error "Token refresh failed"
            echo "$response"
            exit 1
        fi
        ;;
        
    "profile-info")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        log_info "Fetching profile information"
        
        # LinkedIn v2 API uses different endpoint
        profile=$(curl -s -H "Authorization: Bearer $LINKEDIN_ACCESS_TOKEN" \
                      -H "X-Restli-Protocol-Version: 2.0.0" \
                      "https://api.linkedin.com/v2/people/~")
        
        if [[ $? -eq 0 ]]; then
            echo "$profile" | jq '{
                id: .id,
                firstName: .localizedFirstName,
                lastName: .localizedLastName,
                profilePicture: (.profilePicture."displayImage~".elements[0].identifiers[0].identifier // "N/A")
            }'
        fi
        ;;
        
    "company-pages")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        log_info "Fetching managed company pages"
        
        # Get organizations the user administers
        orgs=$(linkedin_api_call "GET" "organizationAcls?q=roleAssignee")
        
        if [[ $? -eq 0 ]]; then
            echo "$orgs" | jq '.elements[] | {
                organization: .organization,
                role: .role,
                state: .state
            }'
        fi
        ;;
        
    "create-post")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        text="${PARAM_text:-}"
        company_id="${PARAM_company_id:-}"
        visibility="${PARAM_visibility:-PUBLIC}"
        media_url="${PARAM_media_url:-}"
        media_type="${PARAM_media_type:-}"
        
        if [[ -z "$text" ]]; then
            log_error "text parameter required for create-post"
            echo "Usage: $0 create-post 'text=Your post content&company_id=12345&visibility=PUBLIC'"
            exit 1
        fi
        
        log_info "Creating LinkedIn post"
        
        create_linkedin_post "$company_id" "$text" "$visibility" "$media_url" "$media_type"
        ;;
        
    "create-post-from-file")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        file_path="${PARAM_file:-}"
        company_id="${PARAM_company_id:-}"
        visibility="${PARAM_visibility:-PUBLIC}"
        media_url="${PARAM_media_url:-}"
        media_type="${PARAM_media_type:-}"
        
        if [[ -z "$file_path" || ! -f "$file_path" ]]; then
            log_error "Valid file path required for create-post-from-file"
            echo "Usage: $0 create-post-from-file 'file=/path/to/content.md&company_id=12345'"
            exit 1
        fi
        
        log_info "Creating LinkedIn post from file: $file_path"
        
        # Read content from file
        text=$(cat "$file_path")
        
        create_linkedin_post "$company_id" "$text" "$visibility" "$media_url" "$media_type"
        ;;
        
    "post-analytics")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        post_id="${PARAM_post_id:-}"
        
        if [[ -z "$post_id" ]]; then
            log_error "post_id parameter required for post-analytics"
            echo "Usage: $0 post-analytics 'post_id=urn:li:share:123456789'"
            exit 1
        fi
        
        log_info "Fetching post analytics for: $post_id"
        
        # Get post metrics
        metrics=$(linkedin_api_call "GET" "socialMetadata/$post_id")
        
        if [[ $? -eq 0 ]]; then
            echo "$metrics" | jq '{
                totalShares: .totalShares,
                clickCount: .clickCount,
                likeCount: .likeCount,
                commentCount: .commentCount,
                shareCount: .shareCount,
                impressionCount: .impressionCount,
                engagement_rate: ((.likeCount + .commentCount + .shareCount) * 100 / (.impressionCount // 1))
            }'
        fi
        ;;
        
    "page-analytics")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        organization_id="${PARAM_organization_id:-}"
        timeframe="${PARAM_timeframe:-30d}"
        
        if [[ -z "$organization_id" ]]; then
            log_error "organization_id parameter required for page-analytics"
            echo "Usage: $0 page-analytics 'organization_id=12345&timeframe=30d'"
            exit 1
        fi
        
        log_info "Fetching page analytics for organization: $organization_id"
        
        # Calculate date range
        case "$timeframe" in
            "7d")
                start_date=$(date -d '7 days ago' +%Y-%m-%d)
                ;;
            "30d")
                start_date=$(date -d '30 days ago' +%Y-%m-%d)
                ;;
            "90d")
                start_date=$(date -d '90 days ago' +%Y-%m-%d)
                ;;
            *)
                start_date=$(date -d '30 days ago' +%Y-%m-%d)
                ;;
        esac
        
        end_date=$(date +%Y-%m-%d)
        
        # Get organization analytics
        analytics=$(linkedin_api_call "GET" "organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=urn:li:organization:$organization_id&timeIntervals.timeGranularityType=DAY&timeIntervals.timeRange.start=$start_date&timeIntervals.timeRange.end=$end_date")
        
        if [[ $? -eq 0 ]]; then
            echo "$analytics" | jq '{
                timeframe: "'$timeframe'",
                organization_id: "'$organization_id'",
                analytics: .elements[0] // {},
                summary: {
                    total_impressions: ([.elements[]?.totalShareStatistics.impressionCount // 0] | add),
                    total_clicks: ([.elements[]?.totalShareStatistics.clickCount // 0] | add),
                    total_likes: ([.elements[]?.totalShareStatistics.likeCount // 0] | add),
                    total_shares: ([.elements[]?.totalShareStatistics.shareCount // 0] | add),
                    total_comments: ([.elements[]?.totalShareStatistics.commentCount // 0] | add)
                }
            }'
        fi
        ;;
        
    "follower-stats")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        organization_id="${PARAM_organization_id:-}"
        
        if [[ -z "$organization_id" ]]; then
            log_error "organization_id parameter required for follower-stats"
            echo "Usage: $0 follower-stats 'organization_id=12345'"
            exit 1
        fi
        
        log_info "Fetching follower statistics for organization: $organization_id"
        
        # Get follower statistics
        followers=$(linkedin_api_call "GET" "organizationalEntityFollowerStatistics?q=organizationalEntity&organizationalEntity=urn:li:organization:$organization_id")
        
        if [[ $? -eq 0 ]]; then
            echo "$followers" | jq '{
                organization_id: "'$organization_id'",
                follower_count: .elements[0].followerCountsByAssociationType[0].followerCounts.organicFollowerCount,
                demographics: .elements[0].followerCountsByAssociationType[0].followerCounts,
                growth_metrics: {
                    organic_followers: .elements[0].followerCountsByAssociationType[0].followerCounts.organicFollowerCount,
                    paid_followers: .elements[0].followerCountsByAssociationType[0].followerCounts.paidFollowerCount
                }
            }'
        fi
        ;;
        
    "engagement-metrics")
        if [[ -z "$LINKEDIN_ACCESS_TOKEN" ]]; then
            log_error "LINKEDIN_ACCESS_TOKEN required for API calls"
            exit 1
        fi
        
        organization_id="${PARAM_organization_id:-}"
        timeframe="${PARAM_timeframe:-30d}"
        
        if [[ -z "$organization_id" ]]; then
            log_error "organization_id parameter required for engagement-metrics"
            echo "Usage: $0 engagement-metrics 'organization_id=12345&timeframe=30d'"
            exit 1
        fi
        
        log_info "Calculating detailed engagement metrics"
        
        # Get both share statistics and follower data
        share_stats=$(bash "$0" page-analytics "organization_id=$organization_id&timeframe=$timeframe")
        follower_stats=$(bash "$0" follower-stats "organization_id=$organization_id")
        
        # Combine and calculate advanced metrics
        jq -n --argjson shares "$share_stats" --argjson followers "$follower_stats" \
           --arg timeframe "$timeframe" \
        '{
            timeframe: $timeframe,
            organization_id: "'$organization_id'",
            engagement_analysis: {
                total_impressions: $shares.summary.total_impressions,
                total_engagements: ($shares.summary.total_likes + $shares.summary.total_comments + $shares.summary.total_shares),
                engagement_rate: (($shares.summary.total_likes + $shares.summary.total_comments + $shares.summary.total_shares) * 100 / ($shares.summary.total_impressions // 1)),
                click_through_rate: ($shares.summary.total_clicks * 100 / ($shares.summary.total_impressions // 1)),
                follower_count: $followers.follower_count,
                reach_to_follower_ratio: ($shares.summary.total_impressions / ($followers.follower_count // 1))
            },
            performance_breakdown: {
                likes: $shares.summary.total_likes,
                comments: $shares.summary.total_comments,
                shares: $shares.summary.total_shares,
                clicks: $shares.summary.total_clicks,
                impressions: $shares.summary.total_impressions
            },
            insights: [
                if ($shares.summary.total_impressions // 1) > ($followers.follower_count // 1) then "Content reaching beyond follower base - good viral potential" else "Content primarily reaching existing followers" end,
                if (($shares.summary.total_likes + $shares.summary.total_comments + $shares.summary.total_shares) * 100 / ($shares.summary.total_impressions // 1)) > 3 then "High engagement rate - content resonating well" else "Engagement rate needs improvement" end,
                if ($shares.summary.total_comments // 1) > ($shares.summary.total_likes // 10) then "Strong conversation starter - good discussion content" else "Consider more discussion-prompting content" end
            ]
        }'
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: setup-check, auth-url, exchange-token, refresh-token, profile-info, company-pages, create-post, create-post-from-file, post-analytics, page-analytics, follower-stats, engagement-metrics"
        exit 1
        ;;
esac