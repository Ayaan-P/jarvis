#!/bin/bash
# Google Ads API Integration
# Usage: ./google-ads-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  campaigns             - Get campaign data"
    echo "  campaign-performance  - Get campaign performance metrics"
    echo "  keywords              - Get keyword performance"
    echo "  ad-groups            - Get ad group data"
    echo "  account-info         - Get account information"
    echo "  setup-check          - Verify Google Ads setup and credentials"
    echo ""
    echo "Examples:"
    echo "  $0 setup-check"
    echo "  $0 campaigns"
    echo "  $0 campaign-performance 'days=30'"
    echo ""
    echo "Note: Google Ads API requires OAuth2 authentication and Python client library"
    echo "This script will check for dependencies and guide setup if needed"
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

# Check for required environment variables
check_google_ads_setup() {
    local setup_ok=true
    
    if [[ -z "$GOOGLE_ADS_DEVELOPER_TOKEN" ]]; then
        log_error "GOOGLE_ADS_DEVELOPER_TOKEN not found in environment"
        echo "Please add your Google Ads Developer Token to .env file:"
        echo "GOOGLE_ADS_DEVELOPER_TOKEN=your_developer_token"
        setup_ok=false
    fi
    
    if [[ -z "$GOOGLE_ADS_CLIENT_ID" ]]; then
        log_error "GOOGLE_ADS_CLIENT_ID not found in environment"
        echo "Please add your OAuth Client ID to .env file:"
        echo "GOOGLE_ADS_CLIENT_ID=your_client_id"
        setup_ok=false
    fi
    
    if [[ -z "$GOOGLE_ADS_CLIENT_SECRET" ]]; then
        log_error "GOOGLE_ADS_CLIENT_SECRET not found in environment"
        echo "Please add your OAuth Client Secret to .env file:"
        echo "GOOGLE_ADS_CLIENT_SECRET=your_client_secret"
        setup_ok=false
    fi
    
    if [[ -z "$GOOGLE_ADS_REFRESH_TOKEN" ]]; then
        log_error "GOOGLE_ADS_REFRESH_TOKEN not found in environment"
        echo "Please add your OAuth Refresh Token to .env file:"
        echo "GOOGLE_ADS_REFRESH_TOKEN=your_refresh_token"
        setup_ok=false
    fi
    
    if [[ -z "$GOOGLE_ADS_CUSTOMER_ID" ]]; then
        log_error "GOOGLE_ADS_CUSTOMER_ID not found in environment"
        echo "Please add your Google Ads Customer ID to .env file:"
        echo "GOOGLE_ADS_CUSTOMER_ID=1234567890"
        setup_ok=false
    fi
    
    if [[ "$setup_ok" == "false" ]]; then
        echo ""
        echo "Google Ads Setup Guide:"
        echo "1. Go to Google Cloud Console (console.cloud.google.com)"
        echo "2. Create a new project or select existing one"
        echo "3. Enable Google Ads API"
        echo "4. Create OAuth 2.0 credentials (Desktop application)"
        echo "5. Apply for Google Ads Developer Token at developers.google.com/google-ads/api"
        echo "6. Use OAuth playground to get refresh token"
        echo "7. Add all credentials to .env file"
        return 1
    fi
    
    return 0
}

# Check for Python dependencies
check_python_deps() {
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 is required for Google Ads integration"
        echo "Please install Python 3: https://www.python.org/downloads/"
        return 1
    fi
    
    # Check if required Python packages are installed
    local missing_packages=()
    
    if ! python3 -c "import google.ads.googleads.client" >/dev/null 2>&1; then
        missing_packages+=("google-ads")
    fi
    
    if ! python3 -c "import google.auth" >/dev/null 2>&1; then
        missing_packages+=("google-auth")
    fi
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_error "Missing Python packages: ${missing_packages[*]}"
        echo "Install with: pip3 install ${missing_packages[*]}"
        return 1
    fi
    
    return 0
}

# Create Python script for Google Ads API calls
create_google_ads_python_script() {
    local script_path="/tmp/google_ads_client_$$.py"
    
    cat > "$script_path" << 'EOF'
#!/usr/bin/env python3
import sys
import json
import os
from datetime import datetime, timedelta
from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException

def init_client():
    """Initialize Google Ads client with OAuth credentials"""
    credentials = {
        "developer_token": os.environ.get('GOOGLE_ADS_DEVELOPER_TOKEN'),
        "client_id": os.environ.get('GOOGLE_ADS_CLIENT_ID'),
        "client_secret": os.environ.get('GOOGLE_ADS_CLIENT_SECRET'),
        "refresh_token": os.environ.get('GOOGLE_ADS_REFRESH_TOKEN'),
        "use_proto_plus": True
    }
    
    # Validate credentials
    for key, value in credentials.items():
        if not value and key != 'use_proto_plus':
            raise Exception(f"Missing credential: {key}")
    
    return GoogleAdsClient.load_from_dict(credentials)

def campaigns(customer_id):
    """Get campaign data"""
    client = init_client()
    ga_service = client.get_service("GoogleAdsService")
    
    query = """
        SELECT 
            campaign.id,
            campaign.name,
            campaign.status,
            campaign.advertising_channel_type,
            campaign.campaign_budget,
            campaign.start_date,
            campaign.end_date
        FROM campaign
        WHERE campaign.status != 'REMOVED'
        ORDER BY campaign.name
    """
    
    try:
        response = ga_service.search(customer_id=customer_id, query=query)
        
        campaigns_data = []
        for row in response:
            campaigns_data.append({
                "id": row.campaign.id,
                "name": row.campaign.name,
                "status": row.campaign.status.name,
                "channel_type": row.campaign.advertising_channel_type.name,
                "start_date": row.campaign.start_date,
                "end_date": row.campaign.end_date,
            })
        
        return {"campaigns": campaigns_data}
        
    except GoogleAdsException as ex:
        return {"error": f"Google Ads API error: {ex}"}

def campaign_performance(customer_id, days=30):
    """Get campaign performance metrics"""
    client = init_client()
    ga_service = client.get_service("GoogleAdsService")
    
    start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    end_date = datetime.now().strftime('%Y-%m-%d')
    
    query = f"""
        SELECT 
            campaign.id,
            campaign.name,
            metrics.impressions,
            metrics.clicks,
            metrics.ctr,
            metrics.average_cpc,
            metrics.cost_micros,
            metrics.conversions,
            metrics.conversion_rate,
            metrics.cost_per_conversion,
            segments.date
        FROM campaign
        WHERE campaign.status != 'REMOVED'
        AND segments.date BETWEEN '{start_date}' AND '{end_date}'
        ORDER BY metrics.cost_micros DESC
    """
    
    try:
        response = ga_service.search(customer_id=customer_id, query=query)
        
        performance_data = []
        for row in response:
            performance_data.append({
                "campaign_id": row.campaign.id,
                "campaign_name": row.campaign.name,
                "date": row.segments.date,
                "impressions": row.metrics.impressions,
                "clicks": row.metrics.clicks,
                "ctr": row.metrics.ctr,
                "average_cpc": row.metrics.average_cpc / 1000000,  # Convert from micros
                "cost": row.metrics.cost_micros / 1000000,  # Convert from micros
                "conversions": row.metrics.conversions,
                "conversion_rate": row.metrics.conversion_rate,
                "cost_per_conversion": row.metrics.cost_per_conversion / 1000000 if row.metrics.cost_per_conversion else 0,
            })
        
        return {
            "period": f"{start_date} to {end_date}",
            "performance_data": performance_data
        }
        
    except GoogleAdsException as ex:
        return {"error": f"Google Ads API error: {ex}"}

def keywords(customer_id, days=30):
    """Get keyword performance"""
    client = init_client()
    ga_service = client.get_service("GoogleAdsService")
    
    start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    end_date = datetime.now().strftime('%Y-%m-%d')
    
    query = f"""
        SELECT 
            campaign.name,
            ad_group.name,
            ad_group_criterion.keyword.text,
            ad_group_criterion.keyword.match_type,
            metrics.impressions,
            metrics.clicks,
            metrics.ctr,
            metrics.average_cpc,
            metrics.cost_micros,
            metrics.conversions,
            metrics.quality_score
        FROM keyword_view
        WHERE campaign.status != 'REMOVED'
        AND ad_group.status != 'REMOVED'
        AND ad_group_criterion.status != 'REMOVED'
        AND segments.date BETWEEN '{start_date}' AND '{end_date}'
        ORDER BY metrics.cost_micros DESC
        LIMIT 50
    """
    
    try:
        response = ga_service.search(customer_id=customer_id, query=query)
        
        keywords_data = []
        for row in response:
            keywords_data.append({
                "campaign_name": row.campaign.name,
                "ad_group_name": row.ad_group.name,
                "keyword_text": row.ad_group_criterion.keyword.text,
                "match_type": row.ad_group_criterion.keyword.match_type.name,
                "impressions": row.metrics.impressions,
                "clicks": row.metrics.clicks,
                "ctr": row.metrics.ctr,
                "average_cpc": row.metrics.average_cpc / 1000000,
                "cost": row.metrics.cost_micros / 1000000,
                "conversions": row.metrics.conversions,
                "quality_score": row.metrics.quality_score,
            })
        
        return {
            "period": f"{start_date} to {end_date}",
            "top_keywords": keywords_data
        }
        
    except GoogleAdsException as ex:
        return {"error": f"Google Ads API error: {ex}"}

def ad_groups(customer_id):
    """Get ad group data"""
    client = init_client()
    ga_service = client.get_service("GoogleAdsService")
    
    query = """
        SELECT 
            campaign.name,
            ad_group.id,
            ad_group.name,
            ad_group.status,
            ad_group.type,
            ad_group.cpc_bid_micros,
            ad_group.target_cpa_micros
        FROM ad_group
        WHERE campaign.status != 'REMOVED'
        AND ad_group.status != 'REMOVED'
        ORDER BY campaign.name, ad_group.name
    """
    
    try:
        response = ga_service.search(customer_id=customer_id, query=query)
        
        ad_groups_data = []
        for row in response:
            ad_groups_data.append({
                "campaign_name": row.campaign.name,
                "ad_group_id": row.ad_group.id,
                "ad_group_name": row.ad_group.name,
                "status": row.ad_group.status.name,
                "type": row.ad_group.type_.name,
                "cpc_bid": row.ad_group.cpc_bid_micros / 1000000 if row.ad_group.cpc_bid_micros else 0,
                "target_cpa": row.ad_group.target_cpa_micros / 1000000 if row.ad_group.target_cpa_micros else 0,
            })
        
        return {"ad_groups": ad_groups_data}
        
    except GoogleAdsException as ex:
        return {"error": f"Google Ads API error: {ex}"}

def account_info(customer_id):
    """Get account information"""
    client = init_client()
    ga_service = client.get_service("GoogleAdsService")
    
    query = """
        SELECT 
            customer.id,
            customer.descriptive_name,
            customer.currency_code,
            customer.time_zone,
            customer.auto_tagging_enabled,
            customer.test_account
        FROM customer
        LIMIT 1
    """
    
    try:
        response = ga_service.search(customer_id=customer_id, query=query)
        
        for row in response:
            return {
                "customer_id": row.customer.id,
                "account_name": row.customer.descriptive_name,
                "currency_code": row.customer.currency_code,
                "time_zone": row.customer.time_zone,
                "auto_tagging_enabled": row.customer.auto_tagging_enabled,
                "test_account": row.customer.test_account,
            }
        
        return {"error": "No account data found"}
        
    except GoogleAdsException as ex:
        return {"error": f"Google Ads API error: {ex}"}

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 script.py <action> <customer_id> [days]")
        sys.exit(1)
    
    action = sys.argv[1]
    customer_id = sys.argv[2]
    days = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    
    try:
        if action == "campaigns":
            result = campaigns(customer_id)
        elif action == "campaign-performance":
            result = campaign_performance(customer_id, days)
        elif action == "keywords":
            result = keywords(customer_id, days)
        elif action == "ad-groups":
            result = ad_groups(customer_id)
        elif action == "account-info":
            result = account_info(customer_id)
        else:
            raise Exception(f"Unknown action: {action}")
        
        print(json.dumps(result, indent=2))
        
    except Exception as e:
        error_result = {
            "error": str(e),
            "action": action,
            "timestamp": datetime.now().isoformat()
        }
        print(json.dumps(error_result, indent=2))
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    echo "$script_path"
}

# Action implementations
case "$ACTION" in
    "setup-check")
        log_info "Checking Google Ads setup and dependencies"
        
        if check_google_ads_setup && check_python_deps; then
            log_info "✅ Google Ads setup is complete and ready to use"
            echo '{"status": "ready", "message": "Google Ads integration is properly configured"}'
        else
            echo '{"status": "incomplete", "message": "Google Ads setup requires configuration"}'
            exit 1
        fi
        ;;
        
    "campaigns"|"campaign-performance"|"keywords"|"ad-groups"|"account-info")
        # Check setup first
        if ! check_google_ads_setup || ! check_python_deps; then
            exit 1
        fi
        
        log_info "Executing Google Ads action: $ACTION"
        
        # Extract days parameter if provided
        local days=30
        if [[ -n "$PARAMS" && "$PARAMS" =~ days= ]]; then
            days=$(echo "$PARAMS" | sed -n 's/.*days=\([^&]*\).*/\1/p')
        fi
        
        # Create and execute Python script
        local python_script
        python_script=$(create_google_ads_python_script)
        
        # Execute the Python script
        python3 "$python_script" "$ACTION" "$GOOGLE_ADS_CUSTOMER_ID" "$days"
        
        # Clean up
        rm -f "$python_script"
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: setup-check, campaigns, campaign-performance, keywords, ad-groups, account-info"
        exit 1
        ;;
esac