#!/bin/bash
# Mixpanel Analytics API Integration for ccOS Agents
# Provides comprehensive analytics data for business intelligence

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment variables
source "$(dirname "$0")/utils.sh"

# Mixpanel API Configuration
MIXPANEL_PROJECT_TOKEN="${MIXPANEL_PROJECT_TOKEN:-${VITE_MIXPANEL_TOKEN}}"
MIXPANEL_API_SECRET="${MIXPANEL_API_SECRET}"
MIXPANEL_BASE_URL="https://mixpanel.com/api/2.0"

# Function to check if Mixpanel API credentials are available
check_mixpanel_setup() {
    if [ -z "$MIXPANEL_PROJECT_TOKEN" ] || [ -z "$MIXPANEL_API_SECRET" ]; then
        echo -e "${RED}❌ Mixpanel API credentials not found${NC}"
        echo "Required environment variables:"
        echo "  MIXPANEL_PROJECT_TOKEN (or VITE_MIXPANEL_TOKEN)"
        echo "  MIXPANEL_API_SECRET"
        echo ""
        echo "Setup guide:"
        echo "1. Go to https://mixpanel.com/settings/project"
        echo "2. Copy Project Token and API Secret"
        echo "3. Add to your .env file"
        return 1
    fi
    
    echo -e "${GREEN}✅ Mixpanel API credentials found${NC}"
    return 0
}

# Function to make authenticated API calls to Mixpanel
mixpanel_api_call() {
    local endpoint="$1"
    local params="$2"
    local method="${3:-GET}"
    
    if [ -z "$endpoint" ]; then
        echo "Error: API endpoint required"
        return 1
    fi
    
    # Calculate current and previous dates for analysis
    local today=$(date +%Y-%m-%d)
    local week_ago=$(date -d '7 days ago' +%Y-%m-%d)
    local month_ago=$(date -d '30 days ago' +%Y-%m-%d)
    
    # Build URL with authentication
    local url="${MIXPANEL_BASE_URL}/${endpoint}?${params}"
    
    # Add common parameters if not specified
    if [[ ! "$params" =~ "from_date" ]]; then
        url="${url}&from_date=${week_ago}&to_date=${today}"
    fi
    
    # Make API call with authentication
    curl -s -X "$method" \
        -u "${MIXPANEL_API_SECRET}:" \
        "$url" | jq '.' 2>/dev/null || echo "API call failed"
}

# Function to get events data
get_events() {
    local days="${1:-7}"
    local event_name="$2"
    
    echo -e "${BLUE}📊 Fetching events data (last ${days} days)${NC}"
    
    local from_date=$(date -d "${days} days ago" +%Y-%m-%d)
    local to_date=$(date +%Y-%m-%d)
    
    local params="from_date=${from_date}&to_date=${to_date}"
    if [ -n "$event_name" ]; then
        params="${params}&event=[\"${event_name}\"]"
    fi
    
    mixpanel_api_call "events" "$params"
}

# Function to get funnel analysis
get_funnel() {
    local funnel_id="$1"
    local days="${2:-7}"
    
    echo -e "${BLUE}🔄 Analyzing funnel performance${NC}"
    
    if [ -z "$funnel_id" ]; then
        echo "Funnel ID required. Available funnels:"
        mixpanel_api_call "funnels/list" ""
        return 1
    fi
    
    local from_date=$(date -d "${days} days ago" +%Y-%m-%d)
    local to_date=$(date +%Y-%m-%d)
    
    mixpanel_api_call "funnels" "funnel_id=${funnel_id}&from_date=${from_date}&to_date=${to_date}"
}

# Function to get user engagement data
get_engagement() {
    local days="${1:-7}"
    
    echo -e "${BLUE}👥 Fetching user engagement data${NC}"
    
    local from_date=$(date -d "${days} days ago" +%Y-%m-%d)
    local to_date=$(date +%Y-%m-%d)
    
    mixpanel_api_call "engage" "from_date=${from_date}&to_date=${to_date}"
}

# Function to get retention analysis
get_retention() {
    local retention_type="${1:-birth}"  # birth, compounded, or survival
    local days="${2:-30}"
    
    echo -e "${BLUE}📈 Analyzing user retention${NC}"
    
    local from_date=$(date -d "${days} days ago" +%Y-%m-%d)
    local to_date=$(date +%Y-%m-%d)
    
    mixpanel_api_call "retention" "retention_type=${retention_type}&from_date=${from_date}&to_date=${to_date}"
}

# Function to get real-time insights
get_insights() {
    local metric="${1:-events}"
    
    echo -e "${BLUE}⚡ Getting real-time insights${NC}"
    
    case "$metric" in
        "events")
            get_events 1
            ;;
        "users")
            get_engagement 1
            ;;
        "conversion")
            echo "Top conversion events today:"
            get_events 1 | jq '.data | to_entries | sort_by(.value) | reverse | .[0:5]' 2>/dev/null
            ;;
        *)
            echo "Available metrics: events, users, conversion"
            ;;
    esac
}

# Function to analyze marketing performance
analyze_marketing() {
    local channel="$1"
    local days="${2:-30}"
    
    echo -e "${BLUE}📊 Marketing Performance Analysis${NC}"
    echo "==============================================="
    
    echo ""
    echo -e "${YELLOW}📈 Key Events (Last ${days} days):${NC}"
    get_events "$days" | jq '.data | to_entries | map({event: .key, count: .value}) | sort_by(.count) | reverse | .[0:10]' 2>/dev/null
    
    echo ""
    echo -e "${YELLOW}👥 User Engagement:${NC}"
    get_engagement "$days" | jq '.results | length as $total | "Total engaged users: \($total)"' 2>/dev/null
    
    echo ""
    echo -e "${YELLOW}🔄 Conversion Funnel:${NC}"
    echo "Sign Up → Page View → Waitlist Signup analysis:"
    get_events "$days" "Sign Up"
    
    if [ -n "$channel" ]; then
        echo ""
        echo -e "${YELLOW}📱 Channel-Specific Analysis: ${channel}${NC}"
        get_events "$days" | jq --arg channel "$channel" '.data | with_entries(select(.key | contains($channel)))' 2>/dev/null
    fi
}

# Function to get business intelligence summary
business_intelligence() {
    local days="${1:-7}"
    
    echo -e "${BLUE}🧠 Business Intelligence Summary${NC}"
    echo "=============================================="
    
    local today=$(date '+%Y-%m-%d')
    local period_start=$(date -d "${days} days ago" '+%Y-%m-%d')
    
    echo ""
    echo -e "${YELLOW}📊 Period: ${period_start} to ${today} (${days} days)${NC}"
    
    # Key metrics
    echo ""
    echo -e "${YELLOW}🎯 Key Metrics:${NC}"
    local events_data=$(get_events "$days")
    local total_events=$(echo "$events_data" | jq '.data | [.[]] | add' 2>/dev/null || echo "0")
    echo "• Total Events: ${total_events}"
    
    local engagement_data=$(get_engagement "$days")
    local total_users=$(echo "$engagement_data" | jq '.results | length' 2>/dev/null || echo "0")
    echo "• Active Users: ${total_users}"
    
    # Top events
    echo ""
    echo -e "${YELLOW}🔥 Top Events:${NC}"
    echo "$events_data" | jq -r '.data | to_entries | sort_by(.value) | reverse | .[0:5] | .[] | "• \(.key): \(.value)"' 2>/dev/null
    
    # Growth trends
    echo ""
    echo -e "${YELLOW}📈 Growth Insights:${NC}"
    if [ "$total_events" -gt 0 ]; then
        local daily_avg=$((total_events / days))
        echo "• Daily Average Events: ${daily_avg}"
        echo "• Events per Active User: $(echo "scale=2; $total_events / $total_users" | bc 2>/dev/null || echo "N/A")"
    fi
    
    # Conversion analysis
    echo ""
    echo -e "${YELLOW}🎯 Conversion Analysis:${NC}"
    local signup_events=$(echo "$events_data" | jq '.data["Sign Up"] // 0' 2>/dev/null)
    local pageview_events=$(echo "$events_data" | jq '.data["Page View"] // 0' 2>/dev/null)
    if [ "$pageview_events" -gt 0 ] && [ "$signup_events" -gt 0 ]; then
        local conversion_rate=$(echo "scale=2; $signup_events * 100 / $pageview_events" | bc 2>/dev/null || echo "N/A")
        echo "• Page View to Sign Up: ${conversion_rate}%"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Analysis complete${NC}"
}

# Function to track a custom event (for testing)
track_event() {
    local event_name="$1"
    local properties="$2"
    
    if [ -z "$event_name" ]; then
        echo "Error: Event name required"
        echo "Usage: track_event 'Event Name' '{\"property\": \"value\"}'"
        return 1
    fi
    
    echo -e "${BLUE}📝 Tracking event: ${event_name}${NC}"
    
    # Note: This would typically be done from the frontend
    # This is just for testing the integration
    echo "Event would be tracked with properties: ${properties:-'{}'}"
    echo "Use frontend Mixpanel integration for actual event tracking"
}

# Main function
main() {
    local command="$1"
    shift
    
    case "$command" in
        "setup-check")
            check_mixpanel_setup
            ;;
        "events")
            get_events "$@"
            ;;
        "funnel")
            get_funnel "$@"
            ;;
        "engagement")
            get_engagement "$@"
            ;;
        "retention")
            get_retention "$@"
            ;;
        "insights")
            get_insights "$@"
            ;;
        "marketing")
            analyze_marketing "$@"
            ;;
        "intelligence"|"bi")
            business_intelligence "$@"
            ;;
        "track")
            track_event "$@"
            ;;
        *)
            echo -e "${BLUE}Mixpanel Analytics API for ccOS${NC}"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  setup-check                    - Verify API credentials"
            echo "  events [days] [event_name]     - Get events data"
            echo "  funnel <funnel_id> [days]      - Analyze conversion funnels"
            echo "  engagement [days]              - Get user engagement metrics"
            echo "  retention [type] [days]        - Analyze user retention"
            echo "  insights [metric]              - Real-time insights"
            echo "  marketing [channel] [days]     - Marketing performance analysis"
            echo "  intelligence [days]            - Business intelligence summary"
            echo "  track <event> [properties]     - Track custom event (testing)"
            echo ""
            echo "Examples:"
            echo "  $0 setup-check"
            echo "  $0 events 7"
            echo "  $0 marketing instagram 30"
            echo "  $0 intelligence 14"
            echo "  $0 insights conversion"
            ;;
    esac
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi