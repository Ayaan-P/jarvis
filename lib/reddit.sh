#!/bin/bash
# Reddit marketing automation utilities
# Generic tool for any business to leverage Reddit marketing

source "${BASH_SOURCE%/*}/utils.sh"

# Reddit API authentication
reddit_authenticate() {
    if [[ -z "$REDDIT_CLIENT_ID" || -z "$REDDIT_CLIENT_SECRET" || -z "$REDDIT_USERNAME" || -z "$REDDIT_PASSWORD" ]]; then
        log_error "Reddit API credentials not configured in .env"
        return 1
    fi
    
    local token=$(curl -s -X POST \
        -d "grant_type=password&username=$REDDIT_USERNAME&password=$REDDIT_PASSWORD" \
        --user "$REDDIT_CLIENT_ID:$REDDIT_CLIENT_SECRET" \
        -H "User-Agent: ClaudeAgenticFiles:v1.0 (by u/$REDDIT_USERNAME)" \
        https://www.reddit.com/api/v1/access_token | jq -r '.access_token')
    
    if [[ "$token" != "null" && -n "$token" ]]; then
        echo "$token"
        return 0
    else
        log_error "Reddit authentication failed"
        return 1
    fi
}

# Post content to Reddit subreddit
reddit_post() {
    local subreddit="$1"
    local title="$2"  
    local content="$3"
    
    local token=$(reddit_authenticate)
    [[ $? -ne 0 ]] && return 1
    
    local response=$(curl -s -X POST \
        -H "User-Agent: ClaudeAgenticFiles:v1.0 (by u/$REDDIT_USERNAME)" \
        -H "Authorization: bearer $token" \
        -d "sr=$subreddit&kind=self&title=$title&text=$content&api_type=json" \
        https://oauth.reddit.com/api/submit)
    
    local errors=$(echo "$response" | jq -r '.json.errors[]?')
    if [[ -n "$errors" ]]; then
        log_error "Reddit post failed: $errors"
        return 1
    fi
    
    local post_url=$(echo "$response" | jq -r '.json.data.url')
    if [[ "$post_url" != "null" ]]; then
        echo "https://reddit.com$post_url"
        log_info "Posted to r/$subreddit: https://reddit.com$post_url"
        return 0
    else
        log_error "Failed to extract post URL from Reddit response"
        return 1
    fi
}

# Find relevant subreddits based on business type and keywords
reddit_find_subreddits() {
    local business_type="$1"
    local keywords="$2"
    
    case "$business_type" in
        "saas"|"software")
            echo "SideProject startups webdev programming entrepreneur"
            ;;
        "mobile_app")
            echo "SideProject startups androiddev iOSProgramming reactnative flutter"
            ;;
        "ai"|"artificial_intelligence")
            echo "artificial MachineLearning deeplearning programming SideProject"
            ;;
        "productivity")
            echo "productivity GetMotivated lifehacks organization SideProject"
            ;;
        "ecommerce")
            echo "entrepreneur smallbusiness ecommerce dropship SideProject"
            ;;
        *)
            echo "SideProject startups entrepreneur"
            ;;
    esac
}

# Generate Reddit-optimized content based on business context
reddit_optimize_content() {
    local subreddit="$1"
    local original_title="$2"
    local original_content="$3"
    local business_context="$4"
    
    # Content optimization would be handled by Claude
    # This provides the framework for context-aware optimization
    
    case "$subreddit" in
        "artificial"|"MachineLearning")
            # Technical focus for AI communities
            echo "TITLE_PREFIX: Technical Discussion -"
            echo "CONTENT_STYLE: technical_showcase"
            ;;
        "productivity"|"lifehacks")  
            # Problem-solution focus for productivity communities
            echo "TITLE_PREFIX: Solved My Productivity Problem -"
            echo "CONTENT_STYLE: problem_solution"
            ;;
        "SideProject"|"startups")
            # Building story for maker communities
            echo "TITLE_PREFIX: Built and Launched -"
            echo "CONTENT_STYLE: build_story"
            ;;
        *)
            echo "TITLE_PREFIX:"
            echo "CONTENT_STYLE: general"
            ;;
    esac
}

# Track Reddit post performance (placeholder for future implementation)
reddit_track_performance() {
    local post_url="$1"
    
    # Would implement post analytics tracking
    log_info "Tracking performance for: $post_url"
    
    # Future: scrape upvotes, comments, engagement
    # Store in memory system for CMO analysis
}

# Main Reddit marketing function
reddit_market() {
    local action="$1"
    shift
    
    case "$action" in
        "post")
            reddit_post "$@"
            ;;
        "find_subreddits")
            reddit_find_subreddits "$@"
            ;;
        "optimize_content")
            reddit_optimize_content "$@"
            ;;
        "track")
            reddit_track_performance "$@"
            ;;
        *)
            log_error "Unknown Reddit marketing action: $action"
            echo "Usage: reddit_market [post|find_subreddits|optimize_content|track] [args...]"
            return 1
            ;;
    esac
}