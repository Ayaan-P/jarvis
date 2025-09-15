#!/bin/bash
# News Intelligence Integration
# Usage: ./news-intelligence-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  setup-check           - Verify news API setup"
    echo "  industry-news         - Get industry-relevant news"
    echo "  breaking-news         - High-impact business news"
    echo "  competitor-mentions   - News about competitors"
    echo "  sentiment-analysis    - News sentiment for industry"
    echo "  news-digest          - Daily news summary"
    echo ""
    echo "New CMO Intelligence Actions:"
    echo "  newsapi-monitor       - Monitor with NewsAPI.org (requires API key)"
    echo "  reddit-monitor        - Monitor Reddit discussions (free)"
    echo "  hackernews-monitor    - Monitor HackerNews trends (free)"
    echo "  competitor-tracking   - Multi-source competitor tracking"
    echo "  generate-report       - Generate comprehensive intelligence report"
    echo ""
    echo "Examples:"
    echo "  $0 setup-check"
    echo "  $0 industry-news 'keywords=SaaS,productivity&hours=24'"
    echo "  $0 competitor-mentions 'competitors=Notion,Airtable&days=7'"
    echo "  $0 breaking-news 'category=technology&impact=high'"
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

# Enhanced logging and source tracking
LOG_DIR="$HOME/.claude/marketing_intelligence/logs"
SOURCES_DIR="$HOME/.claude/marketing_intelligence/sources"
REPORTS_DIR="$HOME/.claude/marketing_intelligence/reports"
MEMORY_DIR="$HOME/.claude/marketing_intelligence/memory"

# Ensure directories exist
mkdir -p "$LOG_DIR" "$SOURCES_DIR" "$REPORTS_DIR" "$MEMORY_DIR"

# Execution tracking
EXECUTION_ID="cmo_$(date +%s)_$$"
EXECUTION_LOG="$LOG_DIR/execution_${EXECUTION_ID}.log"

# Initialize execution log
init_execution_log() {
    cat > "$EXECUTION_LOG" << EOF
{
  "execution_id": "$EXECUTION_ID",
  "start_time": "$(date -Iseconds)",
  "action": "$ACTION",
  "params": "$PARAMS",
  "sources_accessed": [],
  "api_calls": [],
  "data_collected": {},
  "status": "running"
}
EOF
    log_info "Execution started: $EXECUTION_ID"
}

# Enhanced logging functions
log_info() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $message" >&2
    
    # Add to execution log
    if [[ -f "$EXECUTION_LOG" ]]; then
        local temp_log=$(mktemp)
        jq --arg msg "$message" --arg ts "$(date -Iseconds)" \
           '.logs += [{"level": "INFO", "message": $msg, "timestamp": $ts}]' \
           "$EXECUTION_LOG" > "$temp_log" && mv "$temp_log" "$EXECUTION_LOG"
    fi
}

log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >&2
    
    # Add to execution log
    if [[ -f "$EXECUTION_LOG" ]]; then
        local temp_log=$(mktemp)
        jq --arg msg "$message" --arg ts "$(date -Iseconds)" \
           '.logs += [{"level": "ERROR", "message": $msg, "timestamp": $ts}]' \
           "$EXECUTION_LOG" > "$temp_log" && mv "$temp_log" "$EXECUTION_LOG"
    fi
}

# Source tracking function
track_source_access() {
    local source_name="$1"
    local source_url="$2"
    local query="$3"
    local response_size="$4"
    
    log_info "Accessing source: $source_name"
    
    if [[ -f "$EXECUTION_LOG" ]]; then
        local temp_log=$(mktemp)
        jq --arg source "$source_name" \
           --arg url "$source_url" \
           --arg query "$query" \
           --arg size "$response_size" \
           --arg ts "$(date -Iseconds)" \
           '.sources_accessed += [{
               "source": $source,
               "url": $url,
               "query": $query,
               "response_size": $size,
               "timestamp": $ts
           }]' \
           "$EXECUTION_LOG" > "$temp_log" && mv "$temp_log" "$EXECUTION_LOG"
    fi
}

# API call tracking
track_api_call() {
    local api_name="$1"
    local endpoint="$2"
    local status_code="$3"
    local quota_used="$4"
    
    if [[ -f "$EXECUTION_LOG" ]]; then
        local temp_log=$(mktemp)
        jq --arg api "$api_name" \
           --arg endpoint "$endpoint" \
           --arg status "$status_code" \
           --arg quota "$quota_used" \
           --arg ts "$(date -Iseconds)" \
           '.api_calls += [{
               "api": $api,
               "endpoint": $endpoint,
               "status_code": $status,
               "quota_used": $quota,
               "timestamp": $ts
           }]' \
           "$EXECUTION_LOG" > "$temp_log" && mv "$temp_log" "$EXECUTION_LOG"
    fi
}

# Save raw data with source attribution
save_raw_data() {
    local source_name="$1"
    local data="$2"
    local category="$3"
    
    local data_file="$SOURCES_DIR/${source_name}_${category}_$(date +%Y%m%d_%H%M%S).json"
    
    jq -n --arg source "$source_name" \
          --arg category "$category" \
          --arg ts "$(date -Iseconds)" \
          --arg exec_id "$EXECUTION_ID" \
          --argjson data "$data" \
          '{
              "source": $source,
              "category": $category,
              "execution_id": $exec_id,
              "timestamp": $ts,
              "data": $data
          }' > "$data_file"
    
    log_info "Saved raw data: $data_file"
    return 0
}

# Complete execution log
complete_execution_log() {
    local status="$1"
    local summary="$2"
    
    if [[ -f "$EXECUTION_LOG" ]]; then
        local temp_log=$(mktemp)
        jq --arg status "$status" \
           --arg summary "$summary" \
           --arg end_time "$(date -Iseconds)" \
           '.status = $status | .end_time = $end_time | .summary = $summary' \
           "$EXECUTION_LOG" > "$temp_log" && mv "$temp_log" "$EXECUTION_LOG"
        
        log_info "Execution completed: $status"
        
        # Copy to reports if successful
        if [[ "$status" == "success" ]]; then
            cp "$EXECUTION_LOG" "$REPORTS_DIR/execution_$(date +%Y%m%d_%H%M%S).json"
        fi
    fi
}

# Check for required environment variables
check_setup() {
    local setup_ok=true
    
    if [[ -z "$NEWS_API_KEY" ]]; then
        log_error "NEWS_API_KEY not found in environment"
        echo "Please add your NewsAPI key to .env file:"
        echo "NEWS_API_KEY=your_newsapi_key_here"
        echo ""
        echo "Get your free API key at: https://newsapi.org/"
        echo "Free tier: 1000 requests/day"
        setup_ok=false
    fi
    
    if [[ "$setup_ok" == "false" ]]; then
        echo ""
        echo "News Intelligence Setup Guide:"
        echo "1. Go to https://newsapi.org/"
        echo "2. Sign up for free account"
        echo "3. Get your API key from dashboard"
        echo "4. Add NEWS_API_KEY=your_key to .env file"
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

# Calculate relevance score for news articles
calculate_relevance() {
    local title="$1"
    local description="$2"
    local keywords="$3"
    
    local score=0
    
    # Convert keywords to array
    IFS=',' read -ra KEYWORD_ARRAY <<< "$keywords"
    
    for keyword in "${KEYWORD_ARRAY[@]}"; do
        keyword=$(echo "$keyword" | xargs) # trim whitespace
        
        # Check title (higher weight)
        if echo "$title" | grep -qi "$keyword"; then
            score=$((score + 3))
        fi
        
        # Check description (lower weight)
        if echo "$description" | grep -qi "$keyword"; then
            score=$((score + 1))
        fi
    done
    
    echo $score
}

# NewsAPI call wrapper
newsapi_call() {
    local endpoint="$1"
    local params="$2"
    
    local url="https://newsapi.org/v2/$endpoint"
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "X-API-Key: $NEWS_API_KEY" \
        -G "$url" \
        --data-urlencode "$params")
    
    local http_code=${response: -3}
    response=${response%???}
    
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        echo "$response"
        return 0
    else
        log_error "NewsAPI call failed with HTTP $http_code"
        if command -v jq >/dev/null 2>&1; then
            echo "$response" | jq '.' >&2 || echo "$response" >&2
        else
            echo "$response" >&2
        fi
        return 1
    fi
}

# Google News RSS fallback
google_news_rss() {
    local query="$1"
    local url="https://news.google.com/rss/search?q=${query}&hl=en-US&gl=US&ceid=US:en"
    
    curl -s "$url" | grep -E '<title>|<pubDate>|<description>' | \
    sed 's/<!\[CDATA\[//g' | sed 's/\]\]>//g' | \
    sed 's/<[^>]*>//g' | \
    awk 'NR%3==1{title=$0} NR%3==2{date=$0} NR%3==0{desc=$0; print title "|" date "|" desc}'
}

# Reddit news fallback
reddit_news() {
    local subreddit="$1"
    local limit="${2:-10}"
    
    curl -s -H "User-Agent: NewsIntelligence/1.0" \
        "https://www.reddit.com/r/$subreddit/hot.json?limit=$limit" | \
    jq -r '.data.children[] | select(.data.is_self == false) | 
           .data.title + "|" + (.data.created_utc | todate) + "|" + .data.url + "|" + (.data.score | tostring)'
}

# New CMO Intelligence Functions

# NewsAPI.org monitoring (free tier)
newsapi_monitor() {
    local query="$1"
    local api_key="$2"
    local category="${3:-general}"
    
    if [[ -z "$api_key" ]]; then
        log_error "NewsAPI.org API key required for monitoring"
        echo "Get free API key at: https://newsapi.org/ (1000 requests/day)"
        return 1
    fi
    
    log_info "Monitoring NewsAPI.org for: $query"
    
    local url="https://newsapi.org/v2/everything?q=$query&pageSize=20&sortBy=publishedAt&apiKey=$api_key"
    track_source_access "NewsAPI.org" "$url" "$query" "pending"
    
    local response
    response=$(curl -s -w "%{http_code}" "$url" -H "User-Agent: DyttoBot/1.0")
    
    local http_code=${response: -3}
    response=${response%???}
    
    # Track API call
    track_api_call "NewsAPI.org" "/v2/everything" "$http_code" "1"
    
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        # Save raw data
        save_raw_data "newsapi" "$response" "$category"
        
        # Update source access with response size
        local response_size=$(echo "$response" | wc -c)
        track_source_access "NewsAPI.org" "$url" "$query" "$response_size"
        
        echo "$response" | jq -r '
            if .articles then
                .articles[] | 
                "[\(.publishedAt // "unknown")] \(.title // "No title") - \(.url // "No URL")"
            else
                "Error: " + (.message // "Unknown error")
            end
        '
        
        # Return count for reporting
        local count=$(echo "$response" | jq -r '.articles | length // 0')
        echo "{\"source\": \"newsapi\", \"category\": \"$category\", \"count\": $count, \"timestamp\": \"$(date -Iseconds)\"}" >&2
    else
        log_error "Failed to fetch NewsAPI data (HTTP $http_code)"
        echo "$response" >&2
        return 1
    fi
}

# Reddit monitoring (always free)
reddit_monitor() {
    local query="$1"
    local subreddits="${2:-artificial,MachineLearning,ChatGPT}"
    local category="${3:-general}"
    
    log_info "Monitoring Reddit for: $query"
    
    local total_results=0
    
    # Split subreddits and search each one
    IFS=',' read -ra SUBREDDIT_ARRAY <<< "$subreddits"
    for subreddit in "${SUBREDDIT_ARRAY[@]}"; do
        local encoded_query=$(echo "$query" | sed 's/ /+/g')
        local url="https://www.reddit.com/r/$subreddit/search.json"
        local params="q=$encoded_query&limit=10&sort=new&restrict_sr=on"
        
        local response
        response=$(curl -s "$url?$params" \
            -H "User-Agent: DyttoBot/1.0 (CMO Intelligence)")
        
        if [[ $? -eq 0 ]]; then
            echo "$response" | jq -r '
                .data.children[]? | 
                .data | 
                select(.title != null) |
                "[\(.created_utc | strftime("%Y-%m-%d %H:%M"))] r/'$subreddit' - \(.title) (\(.score) points) - https://reddit.com\(.permalink)"
            ' 2>/dev/null
            
            local subreddit_count=$(echo "$response" | jq -r '.data.children | length // 0' 2>/dev/null || echo 0)
            total_results=$((total_results + subreddit_count))
        fi
        
        # Be respectful to Reddit API
        sleep 1
    done
    
    echo "{\"source\": \"reddit\", \"category\": \"$category\", \"count\": $total_results, \"timestamp\": \"$(date -Iseconds)\"}" >&2
}

# HackerNews monitoring (always free)
hackernews_monitor() {
    local keywords="${1:-AI,artificial intelligence}"
    local category="${2:-tech}"
    
    log_info "Monitoring HackerNews for: $keywords"
    
    # Get top stories
    local top_stories
    top_stories=$(curl -s "https://hacker-news.firebaseio.com/v0/topstories.json")
    
    if [[ $? -eq 0 ]]; then
        local count=0
        local story_ids=$(echo "$top_stories" | jq -r '.[:50] | .[]')
        
        for story_id in $story_ids; do
            if [[ $count -ge 20 ]]; then
                break
            fi
            
            local story_data
            story_data=$(curl -s "https://hacker-news.firebaseio.com/v0/item/$story_id.json")
            
            if [[ $? -eq 0 ]]; then
                local title=$(echo "$story_data" | jq -r '.title // ""')
                local url=$(echo "$story_data" | jq -r '.url // ""')
                local score=$(echo "$story_data" | jq -r '.score // 0')
                
                # Check if title matches any keywords (case insensitive)
                IFS=',' read -ra KEYWORD_ARRAY <<< "$keywords"
                for keyword in "${KEYWORD_ARRAY[@]}"; do
                    if echo "$title" | grep -qi "$keyword"; then
                        echo "[$score points] $title - $url"
                        count=$((count + 1))
                        break
                    fi
                done
            fi
            
            sleep 0.1  # Small delay to be respectful
        done
        
        echo "{\"source\": \"hackernews\", \"category\": \"$category\", \"count\": $count, \"timestamp\": \"$(date -Iseconds)\"}" >&2
    else
        log_error "Failed to fetch HackerNews data"
        return 1
    fi
}

# Multi-source competitor tracking
competitor_tracking() {
    local competitors="$1"
    local sources="${2:-all_free}"
    local api_key="$3"
    
    log_info "Tracking competitors: $competitors"
    
    echo "=== COMPETITOR INTELLIGENCE REPORT ===" 
    echo "Generated: $(date)"
    echo ""
    
    IFS=',' read -ra COMPETITOR_ARRAY <<< "$competitors"
    for competitor in "${COMPETITOR_ARRAY[@]}"; do
        echo "=== $competitor ===" 
        
        case "$sources" in
            "all_free"|"reddit")
                echo "--- Reddit Mentions ---"
                reddit_monitor "$competitor" "artificial,MachineLearning,ChatGPT,OpenAI,singularity" "competitor" 2>/dev/null
                echo ""
                ;;
        esac
        
        case "$sources" in
            "all_free"|"newsapi")
                if [[ -n "$api_key" ]]; then
                    echo "--- News Mentions ---"
                    newsapi_monitor "$competitor" "$api_key" "competitor" 2>/dev/null
                    echo ""
                fi
                ;;
        esac
        
        case "$sources" in
            "all_free"|"hackernews")
                echo "--- HackerNews Mentions ---"
                hackernews_monitor "$competitor" "competitor" 2>/dev/null
                echo ""
                ;;
        esac
    done
}

# Generate comprehensive intelligence report
generate_intelligence_report() {
    local date_stamp=$(date +%Y-%m-%d)
    
    echo "# Marketing Intelligence Report - $date_stamp"
    echo ""
    echo "## Executive Summary"
    echo "This report aggregates intelligence from multiple sources including news APIs, Reddit discussions, and HackerNews trends."
    echo ""
    echo "## News Intelligence"
    echo "### Recent AI/Context News"
    if [[ -n "$NEWS_API_KEY" ]]; then
        newsapi_monitor "artificial intelligence context OR context-aware AI" "$NEWS_API_KEY" "ai_news" 2>/dev/null | head -10
    else
        echo "NewsAPI key not configured - install free key for news monitoring"
    fi
    echo ""
    
    echo "## Community Intelligence (Reddit)"
    echo "### AI Community Discussions"
    reddit_monitor "context-aware AI artificial intelligence" "artificial,MachineLearning,ChatGPT" "community" 2>/dev/null | head -10
    echo ""
    
    echo "## Tech Industry Pulse (HackerNews)"
    echo "### Trending AI Topics"
    hackernews_monitor "AI,artificial,context,intelligence,machine learning" "tech_trends" 2>/dev/null | head -10
    echo ""
    
    echo "## Competitive Intelligence"
    echo "### Competitor Activity"
    competitor_tracking "openai,anthropic,claude,chatgpt" "all_free" "$NEWS_API_KEY" 2>/dev/null | head -20
    echo ""
    
    echo "## Action Items"
    echo "- [ ] Review news coverage for response opportunities"
    echo "- [ ] Monitor competitor announcements for strategic implications"
    echo "- [ ] Engage with relevant Reddit discussions"
    echo "- [ ] Create content based on trending topics"
    echo ""
    echo "---"
    echo "*Generated by Dytto CMO News Intelligence System*"
}

# Parse parameters
parse_params

# Initialize execution tracking
init_execution_log

# Action implementations
case "$ACTION" in
    "setup-check")
        log_info "Checking News Intelligence setup"
        
        if check_setup; then
            log_info "✅ News Intelligence setup is complete"
            
            # Test API connectivity
            if newsapi_call "top-headlines" "country=us&pageSize=1"; then
                echo '{"status": "ready", "message": "News Intelligence integration is properly configured"}'
            else
                echo '{"status": "error", "message": "API credentials configured but connection failed"}'
                exit 1
            fi
        else
            echo '{"status": "incomplete", "message": "News Intelligence setup requires configuration"}'
            exit 1
        fi
        ;;
        
    "industry-news")
        if ! check_setup; then
            exit 1
        fi
        
        keywords="${PARAM_keywords:-technology,software}"
        hours="${PARAM_hours:-24}"
        page_size="${PARAM_pageSize:-20}"
        
        log_info "Fetching industry news for keywords: $keywords"
        
        # Calculate date from hours ago
        from_date=$(date -d "$hours hours ago" +%Y-%m-%dT%H:%M:%S)
        
        # Search for news with keywords
        params="q=$keywords&from=$from_date&sortBy=relevancy&pageSize=$page_size&language=en"
        
        response=$(newsapi_call "everything" "$params")
        
        if [[ $? -eq 0 ]]; then
            # Filter and score articles for relevance
            echo "$response" | jq --arg keywords "$keywords" '
                .articles[] | 
                select(.title != null and .description != null) |
                {
                    title: .title,
                    description: .description,
                    url: .url,
                    source: .source.name,
                    publishedAt: .publishedAt,
                    relevance_score: (
                        (.title | ascii_downcase | test($keywords | split(",") | map(ascii_downcase) | join("|"))) * 3 +
                        (.description | ascii_downcase | test($keywords | split(",") | map(ascii_downcase) | join("|"))) * 1
                    )
                } | select(.relevance_score > 0)
            ' | jq -s 'sort_by(-.relevance_score) | limit(10; .[])'
        else
            log_info "Falling back to Google News RSS"
            google_news_rss "$keywords" | head -10 | while IFS='|' read -r title date desc; do
                jq -n --arg title "$title" --arg date "$date" --arg desc "$desc" \
                   '{title: $title, publishedAt: $date, description: $desc, source: "Google News", url: "", relevance_score: 1}'
            done
        fi
        ;;
        
    "breaking-news")
        if ! check_setup; then
            exit 1
        fi
        
        category="${PARAM_category:-technology}"
        impact="${PARAM_impact:-medium}"
        page_size="${PARAM_pageSize:-10}"
        
        log_info "Fetching breaking news for category: $category"
        
        params="category=$category&pageSize=$page_size&country=us"
        
        response=$(newsapi_call "top-headlines" "$params")
        
        if [[ $? -eq 0 ]]; then
            # Filter for high-impact news
            echo "$response" | jq --arg impact "$impact" '
                .articles[] | 
                select(.title != null and .description != null) |
                {
                    title: .title,
                    description: .description,
                    url: .url,
                    source: .source.name,
                    publishedAt: .publishedAt,
                    impact_score: (
                        if (.title | test("breaking|urgent|major|crisis|surge|crash|boom"; "i")) then 3
                        elif (.title | test("significant|important|notable|key"; "i")) then 2
                        else 1 end
                    )
                } | select(
                    if $impact == "high" then .impact_score >= 3
                    elif $impact == "medium" then .impact_score >= 2
                    else .impact_score >= 1 end
                )
            ' | jq -s 'sort_by(-.impact_score) | .[]'
        else
            log_info "Falling back to Google News RSS"
            google_news_rss "breaking+$category" | head -5 | while IFS='|' read -r title date desc; do
                jq -n --arg title "$title" --arg date "$date" --arg desc "$desc" \
                   '{title: $title, publishedAt: $date, description: $desc, source: "Google News", url: "", impact_score: 2}'
            done
        fi
        ;;
        
    "competitor-mentions")
        if ! check_setup; then
            exit 1
        fi
        
        competitors="${PARAM_competitors:-}"
        days="${PARAM_days:-7}"
        
        if [[ -z "$competitors" ]]; then
            log_error "competitors parameter required for competitor-mentions"
            echo "Usage: $0 competitor-mentions 'competitors=Notion,Airtable,Slack&days=7'"
            exit 1
        fi
        
        log_info "Monitoring competitor mentions: $competitors"
        
        # Calculate date from days ago
        from_date=$(date -d "$days days ago" +%Y-%m-%d)
        
        # Search for competitor mentions
        params="q=$competitors&from=$from_date&sortBy=publishedAt&pageSize=20&language=en"
        
        response=$(newsapi_call "everything" "$params")
        
        if [[ $? -eq 0 ]]; then
            echo "$response" | jq --arg competitors "$competitors" '
                .articles[] |
                select(.title != null and .description != null) |
                {
                    title: .title,
                    description: .description,
                    url: .url,
                    source: .source.name,
                    publishedAt: .publishedAt,
                    mentioned_competitor: (
                        $competitors | split(",") | map(select(. as $comp | 
                        (input.title + " " + input.description) | test($comp; "i"))) | join(", ")
                    )
                } | select(.mentioned_competitor != "")
            ' | jq -s 'sort_by(.publishedAt) | reverse | .[]'
        else
            log_info "Falling back to Reddit search"
            IFS=',' read -ra COMP_ARRAY <<< "$competitors"
            for comp in "${COMP_ARRAY[@]}"; do
                reddit_news "technology" 5 | grep -i "$comp" | head -3 | while IFS='|' read -r title date url score; do
                    jq -n --arg title "$title" --arg date "$date" --arg url "$url" --arg comp "$comp" \
                       '{title: $title, publishedAt: $date, url: $url, source: "Reddit", mentioned_competitor: $comp}'
                done
            done
        fi
        ;;
        
    "sentiment-analysis")
        if ! check_setup; then
            exit 1
        fi
        
        keywords="${PARAM_keywords:-technology,startup}"
        hours="${PARAM_hours:-24}"
        
        log_info "Analyzing news sentiment for: $keywords"
        
        # Get recent news
        from_date=$(date -d "$hours hours ago" +%Y-%m-%dT%H:%M:%S)
        params="q=$keywords&from=$from_date&sortBy=publishedAt&pageSize=50&language=en"
        
        response=$(newsapi_call "everything" "$params")
        
        if [[ $? -eq 0 ]]; then
            # Simple sentiment analysis based on keywords
            echo "$response" | jq '
                .articles[] |
                select(.title != null and .description != null) |
                {
                    title: .title,
                    description: .description,
                    publishedAt: .publishedAt,
                    sentiment: (
                        (.title + " " + .description) as $text |
                        if ($text | test("success|growth|profit|gain|boom|surge|positive|good|great|excellent|breakthrough|innovation"; "i")) then "positive"
                        elif ($text | test("crisis|crash|loss|decline|fall|negative|bad|terrible|problem|issue|concern|worry"; "i")) then "negative"
                        else "neutral" end
                    )
                }
            ' | jq -s '
                group_by(.sentiment) | 
                map({
                    sentiment: .[0].sentiment,
                    count: length,
                    percentage: (length * 100 / (map(length) | add)),
                    sample_headlines: map(.title) | .[0:3]
                })
            '
        else
            # Fallback simple analysis
            echo '[{"sentiment": "neutral", "count": 0, "percentage": 100, "sample_headlines": ["No data available"]}]'
        fi
        ;;
        
    "news-digest")
        if ! check_setup; then
            exit 1
        fi
        
        category="${PARAM_category:-technology}"
        hours="${PARAM_hours:-24}"
        
        log_info "Creating news digest for last $hours hours"
        
        # Get top headlines
        headlines=$(newsapi_call "top-headlines" "category=$category&pageSize=5&country=us")
        
        # Get industry-specific news
        from_date=$(date -d "$hours hours ago" +%Y-%m-%dT%H:%M:%S)
        industry_news=$(newsapi_call "everything" "q=startup OR SaaS OR technology&from=$from_date&sortBy=popularity&pageSize=5")
        
        if [[ $? -eq 0 ]]; then
            jq -n --argjson headlines "$headlines" --argjson industry "$industry_news" '
            {
                digest_date: now | strftime("%Y-%m-%d %H:%M:%S"),
                top_headlines: ($headlines.articles // [] | map({
                    title: .title,
                    source: .source.name,
                    url: .url
                }) | .[0:5]),
                industry_focus: ($industry.articles // [] | map({
                    title: .title,
                    source: .source.name,
                    url: .url
                }) | .[0:5]),
                summary: "Daily digest covering technology and startup news"
            }'
        else
            jq -n '
            {
                digest_date: now | strftime("%Y-%m-%d %H:%M:%S"),
                top_headlines: [],
                industry_focus: [],
                summary: "News API unavailable - check API key and limits"
            }'
        fi
        ;;

    # New CMO Intelligence Actions
    "newsapi-monitor")
        query="${PARAM_query:-artificial intelligence}"
        api_key="${PARAM_api_key:-$NEWS_API_KEY}"
        category="${PARAM_category:-brand_monitoring}"
        
        newsapi_monitor "$query" "$api_key" "$category"
        ;;
        
    "reddit-monitor")
        query="${PARAM_query:-AI context-aware artificial intelligence}"
        subreddits="${PARAM_subreddits:-artificial,MachineLearning,ChatGPT,OpenAI,singularity}"
        category="${PARAM_category:-community_intelligence}"
        
        reddit_monitor "$query" "$subreddits" "$category"
        ;;
        
    "hackernews-monitor")
        keywords="${PARAM_keywords:-AI,artificial,context,intelligence,machine learning}"
        category="${PARAM_category:-tech_industry}"
        
        hackernews_monitor "$keywords" "$category"
        ;;
        
    "competitor-tracking")
        competitors="${PARAM_competitors:-openai,anthropic,claude,chatgpt,gemini}"
        sources="${PARAM_sources:-all_free}"
        api_key="${PARAM_api_key:-$NEWS_API_KEY}"
        
        competitor_tracking "$competitors" "$sources" "$api_key"
        ;;
        
    "generate-report")
        generate_intelligence_report
        complete_execution_log "success" "Intelligence report generated successfully"
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: setup-check, industry-news, breaking-news, competitor-mentions, sentiment-analysis, news-digest"
        echo "CMO Intelligence: newsapi-monitor, reddit-monitor, hackernews-monitor, competitor-tracking, generate-report"
        complete_execution_log "error" "Unknown action: $ACTION"
        exit 1
        ;;
esac

# Complete execution log for successful actions
if [[ $? -eq 0 ]]; then
    complete_execution_log "success" "Action '$ACTION' completed successfully"
else
    complete_execution_log "error" "Action '$ACTION' failed with exit code $?"
fi