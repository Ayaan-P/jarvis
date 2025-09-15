#!/bin/bash
# Grants.gov API automation for fundraising-cro
# Usage: ./grants-gov-fetch.sh search "keywords=nonprofit education&agency=ED&limit=10"
# Usage: ./grants-gov-fetch.sh opportunity "id=EPA-I-OA-23-01"

source "${BASH_SOURCE%/*}/utils.sh"

GRANTS_GOV_BASE_URL="https://api.grants.gov/v1/api"
USASPENDING_BASE_URL="https://api.usaspending.gov/api/v2"

# Load DATA_GOV_API_KEY from environment
if [[ -n "$DATA_GOV_API_KEY" ]]; then
    API_KEY_HEADER="X-API-Key: $DATA_GOV_API_KEY"
else
    API_KEY_HEADER=""
    log_info "No DATA_GOV_API_KEY found - using public endpoints only"
fi

# Search for grant opportunities (No API key needed - public endpoint)
grants_search() {
    local keyword="$1"
    local rows="${2:-10}"
    
    log_info "Searching Grants.gov for opportunities: $keyword"
    
    # Use the new search2 API endpoint with POST request (no authentication required)
    local response=$(curl -s -X POST \
        -H "User-Agent: FundraisingCRO:v1.0" \
        -H "Content-Type: application/json" \
        "${GRANTS_GOV_BASE_URL}/search2" \
        -d "{
            \"rows\": $rows,
            \"keyword\": \"$keyword\",
            \"oppStatuses\": \"forecasted|posted\"
        }")
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | jq '.'
        local count=$(echo "$response" | jq -r '.data.hitCount // 0')
        log_info "Found $count grant opportunities"
        return 0
    else
        log_error "Failed to search Grants.gov"
        return 1
    fi
}

# Get detailed opportunity information
grants_opportunity_details() {
    local opp_id="$1"
    
    log_info "Fetching details for opportunity: $opp_id"
    
    # Use the fetchOpportunity API endpoint
    local response=$(curl -s -X GET \
        -H "User-Agent: FundraisingCRO:v1.0" \
        -H "Content-Type: application/json" \
        "${GRANTS_GOV_BASE_URL}/opportunity/${opp_id}")
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | jq '.'
        log_info "Retrieved opportunity details for $opp_id"
        return 0
    else
        log_error "Failed to fetch opportunity details"
        return 1
    fi
}

# Find grants by organization focus area
grants_by_focus_area() {
    local focus_area="$1"
    local limit="${2:-20}"
    
    case "$focus_area" in
        "education")
            grants_search "education training workforce" "$limit"
            ;;
        "workforce_development")
            grants_search "workforce development job training" "$limit"
            ;;
        "technology")
            grants_search "technology digital IT computer" "$limit"
            ;;
        "nonprofit")
            grants_search "nonprofit organization capacity" "$limit"
            ;;
        *)
            grants_search "$focus_area" "$limit"
            ;;
    esac
}

# Search USAspending.gov for grant awards (uses DATA_GOV_API_KEY)
usaspending_grants_search() {
    local search_params="$1"
    local fiscal_year="${2:-2024}"
    
    log_info "Searching USAspending.gov for grant awards: $search_params"
    
    local headers=(-H "User-Agent: FundraisingCRO:v1.0" -H "Content-Type: application/json")
    if [[ -n "$API_KEY_HEADER" ]]; then
        headers+=(-H "$API_KEY_HEADER")
    fi
    
    # Search for grant awards using correct USAspending API format
    local response=$(curl -s -X POST "${headers[@]}" \
        "${USASPENDING_BASE_URL}/search/spending_by_award/" \
        -d "{
            \"filters\": {
                \"award_type_codes\": [\"02\", \"03\", \"04\", \"05\"],
                \"time_period\": [{\"start_date\": \"${fiscal_year}-10-01\", \"end_date\": \"$((fiscal_year+1))-09-30\"}],
                \"keywords\": [\"$search_params\"]
            },
            \"fields\": [\"Award ID\", \"Recipient Name\", \"Award Amount\", \"Start Date\", \"End Date\", \"Awarding Agency\", \"Award Description\"],
            \"limit\": 50
        }")
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | jq '.'
        local count=$(echo "$response" | jq -r '.results | length')
        log_info "Found $count grant awards in USAspending.gov"
        return 0
    else
        log_error "Failed to search USAspending.gov"
        return 1
    fi
}

# Generate grants intelligence report
grants_intelligence_report() {
    local org_focus="$1"
    local output_file="$2"
    
    log_info "Generating grants intelligence report for: $org_focus"
    
    local grants_data=$(grants_by_focus_area "$org_focus" 25)
    
    if [[ -n "$grants_data" ]]; then
        # Create structured intelligence report
        cat > "$output_file" << EOF
# Grants Intelligence Report - $(date)

## Search Criteria: $org_focus

## Grant Opportunities Found:

$grants_data

## Analysis Summary:
- Total opportunities: $(echo "$grants_data" | jq -r '.oppHits // 0')
- Generated: $(date)
- Source: Grants.gov API

EOF
        log_info "Intelligence report saved to: $output_file"
        return 0
    else
        log_error "Failed to generate grants intelligence report"
        return 1
    fi
}

# Main execution
case "${1:-help}" in
    "search")
        grants_search "$2"
        ;;
    "opportunity")
        grants_opportunity_details "$2"
        ;;
    "focus-area")
        grants_by_focus_area "$2" "$3"
        ;;
    "intelligence-report")
        grants_intelligence_report "$2" "$3"
        ;;
    "usaspending")
        usaspending_grants_search "$2" "$3"
        ;;
    "help"|*)
        echo "Usage: $0 {search|opportunity|focus-area|intelligence-report|usaspending|help}"
        echo ""
        echo "Commands:"
        echo "  search 'params'              - Search grants with custom parameters"
        echo "  opportunity 'id'             - Get detailed opportunity information"
        echo "  focus-area 'area' [limit]    - Find grants by focus area"
        echo "  intelligence-report 'area' 'file' - Generate intelligence report"
        echo "  usaspending 'keywords' [year] - Search historical grant awards"
        echo ""
        echo "Focus Areas: education, workforce_development, technology, nonprofit"
        echo "Examples:"
        echo "  $0 search 'keywords=education&agency=ED&limit=5'"
        echo "  $0 opportunity 'EPA-I-OA-23-01'"
        echo "  $0 focus-area education 10"
        echo "  $0 intelligence-report workforce_development grants_report.md"
        ;;
esac