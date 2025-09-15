#!/bin/bash
# Google Analytics 4 Integration
# Usage: ./ga4-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  realtime-users        - Get real-time active users"
    echo "  traffic-sources       - Get traffic source data"
    echo "  page-views           - Get page view data"
    echo "  conversions          - Get conversion data"
    echo "  audience-overview    - Get audience demographics"
    echo "  setup-check          - Verify GA4 setup and credentials"
    echo ""
    echo "Examples:"
    echo "  $0 setup-check"
    echo "  $0 realtime-users"
    echo "  $0 traffic-sources 'days=30'"
    echo ""
    echo "Note: GA4 API requires Python client library for OAuth2 authentication"
    echo "This script will check for Python dependencies and guide setup if needed"
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
        set -a  # automatically export all variables
        source "$env_path"
        set +a  # turn off auto-export
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
check_ga4_setup() {
    local setup_ok=true
    
    if [[ -z "$GA4_PROPERTY_ID" ]]; then
        log_error "GA4_PROPERTY_ID not found in environment"
        echo "Please add your GA4 Property ID to .env file:"
        echo "GA4_PROPERTY_ID=123456789"
        setup_ok=false
    fi
    
    if [[ -z "$GA4_SERVICE_ACCOUNT_JSON" ]]; then
        log_error "GA4_SERVICE_ACCOUNT_JSON not found in environment"
        echo "Please add path to your service account JSON file to .env file:"
        echo "GA4_SERVICE_ACCOUNT_JSON=/path/to/service-account.json"
        setup_ok=false
    elif [[ ! -f "$GA4_SERVICE_ACCOUNT_JSON" ]]; then
        log_error "Service account JSON file not found: $GA4_SERVICE_ACCOUNT_JSON"
        setup_ok=false
    fi
    
    if [[ "$setup_ok" == "false" ]]; then
        echo ""
        echo "GA4 Setup Guide:"
        echo "1. Go to Google Cloud Console (console.cloud.google.com)"
        echo "2. Create a new project or select existing one"
        echo "3. Enable Google Analytics Reporting API"
        echo "4. Create a Service Account and download JSON key"
        echo "5. In GA4, add the service account email as a viewer"
        echo "6. Add GA4_PROPERTY_ID and GA4_SERVICE_ACCOUNT_JSON to .env"
        return 1
    fi
    
    return 0
}

# Check for Python dependencies
check_python_deps() {
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 is required for GA4 integration"
        echo "Please install Python 3: https://www.python.org/downloads/"
        return 1
    fi
    
    # Check if required Python packages are installed
    local missing_packages=()
    
    if ! python3 -c "import google.analytics.data_v1beta" >/dev/null 2>&1; then
        missing_packages+=("google-analytics-data")
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

# Create Python script for GA4 API calls
create_ga4_python_script() {
    local script_path="/tmp/ga4_client_$$.py"
    
    cat > "$script_path" << 'EOF'
#!/usr/bin/env python3
import sys
import json
import os
from datetime import datetime, timedelta
from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import (
    RunRealtimeReportRequest,
    RunReportRequest,
    Dimension,
    Metric,
    DateRange,
)
from google.oauth2 import service_account

def init_client():
    """Initialize GA4 client with service account credentials"""
    credentials_path = os.environ.get('GA4_SERVICE_ACCOUNT_JSON')
    if not credentials_path or not os.path.exists(credentials_path):
        raise Exception(f"Service account JSON not found: {credentials_path}")
    
    credentials = service_account.Credentials.from_service_account_file(
        credentials_path,
        scopes=['https://www.googleapis.com/auth/analytics.readonly']
    )
    
    return BetaAnalyticsDataClient(credentials=credentials)

def realtime_users(property_id):
    """Get real-time active users"""
    client = init_client()
    
    request = RunRealtimeReportRequest(
        property=f"properties/{property_id}",
        metrics=[Metric(name="activeUsers")],
    )
    
    response = client.run_realtime_report(request)
    
    result = {
        "realtime_active_users": int(response.rows[0].metric_values[0].value) if response.rows else 0,
        "timestamp": datetime.now().isoformat()
    }
    
    return result

def traffic_sources(property_id, days=30):
    """Get traffic source data"""
    client = init_client()
    
    start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    end_date = datetime.now().strftime('%Y-%m-%d')
    
    request = RunReportRequest(
        property=f"properties/{property_id}",
        dimensions=[
            Dimension(name="sessionSource"),
            Dimension(name="sessionMedium"),
        ],
        metrics=[
            Metric(name="sessions"),
            Metric(name="totalUsers"),
            Metric(name="newUsers"),
        ],
        date_ranges=[DateRange(start_date=start_date, end_date=end_date)],
    )
    
    response = client.run_report(request)
    
    traffic_data = []
    for row in response.rows:
        traffic_data.append({
            "source": row.dimension_values[0].value,
            "medium": row.dimension_values[1].value,
            "sessions": int(row.metric_values[0].value),
            "users": int(row.metric_values[1].value),
            "new_users": int(row.metric_values[2].value),
        })
    
    return {
        "period": f"{start_date} to {end_date}",
        "traffic_sources": traffic_data
    }

def page_views(property_id, days=30):
    """Get page view data"""
    client = init_client()
    
    start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    end_date = datetime.now().strftime('%Y-%m-%d')
    
    request = RunReportRequest(
        property=f"properties/{property_id}",
        dimensions=[Dimension(name="pagePath")],
        metrics=[
            Metric(name="screenPageViews"),
            Metric(name="totalUsers"),
            Metric(name="averageSessionDuration"),
        ],
        date_ranges=[DateRange(start_date=start_date, end_date=end_date)],
        order_bys=[{"metric": {"metric_name": "screenPageViews"}, "desc": True}],
        limit=20
    )
    
    response = client.run_report(request)
    
    pages_data = []
    for row in response.rows:
        pages_data.append({
            "page_path": row.dimension_values[0].value,
            "page_views": int(row.metric_values[0].value),
            "users": int(row.metric_values[1].value),
            "avg_session_duration": float(row.metric_values[2].value),
        })
    
    return {
        "period": f"{start_date} to {end_date}",
        "top_pages": pages_data
    }

def conversions(property_id, days=30):
    """Get conversion data"""
    client = init_client()
    
    start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    end_date = datetime.now().strftime('%Y-%m-%d')
    
    request = RunReportRequest(
        property=f"properties/{property_id}",
        dimensions=[Dimension(name="eventName")],
        metrics=[
            Metric(name="eventCount"),
            Metric(name="conversions"),
        ],
        date_ranges=[DateRange(start_date=start_date, end_date=end_date)],
        dimension_filter={
            "filter": {
                "field_name": "eventName",
                "string_filter": {
                    "match_type": "CONTAINS",
                    "value": "purchase"
                }
            }
        }
    )
    
    response = client.run_report(request)
    
    conversion_data = []
    for row in response.rows:
        conversion_data.append({
            "event_name": row.dimension_values[0].value,
            "event_count": int(row.metric_values[0].value),
            "conversions": int(row.metric_values[1].value),
        })
    
    return {
        "period": f"{start_date} to {end_date}",
        "conversions": conversion_data
    }

def audience_overview(property_id, days=30):
    """Get audience demographics"""
    client = init_client()
    
    start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
    end_date = datetime.now().strftime('%Y-%m-%d')
    
    request = RunReportRequest(
        property=f"properties/{property_id}",
        dimensions=[
            Dimension(name="country"),
            Dimension(name="city"),
            Dimension(name="deviceCategory"),
        ],
        metrics=[
            Metric(name="totalUsers"),
            Metric(name="sessions"),
            Metric(name="bounceRate"),
        ],
        date_ranges=[DateRange(start_date=start_date, end_date=end_date)],
    )
    
    response = client.run_report(request)
    
    audience_data = []
    for row in response.rows:
        audience_data.append({
            "country": row.dimension_values[0].value,
            "city": row.dimension_values[1].value,
            "device_category": row.dimension_values[2].value,
            "users": int(row.metric_values[0].value),
            "sessions": int(row.metric_values[1].value),
            "bounce_rate": float(row.metric_values[2].value),
        })
    
    return {
        "period": f"{start_date} to {end_date}",
        "audience_data": audience_data
    }

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 script.py <action> <property_id> [days]")
        sys.exit(1)
    
    action = sys.argv[1]
    property_id = sys.argv[2]
    days = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    
    try:
        if action == "realtime-users":
            result = realtime_users(property_id)
        elif action == "traffic-sources":
            result = traffic_sources(property_id, days)
        elif action == "page-views":
            result = page_views(property_id, days)
        elif action == "conversions":
            result = conversions(property_id, days)
        elif action == "audience-overview":
            result = audience_overview(property_id, days)
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
        log_info "Checking GA4 setup and dependencies"
        
        if check_ga4_setup && check_python_deps; then
            log_info "✅ GA4 setup is complete and ready to use"
            echo '{"status": "ready", "message": "GA4 integration is properly configured"}'
        else
            echo '{"status": "incomplete", "message": "GA4 setup requires configuration"}'
            exit 1
        fi
        ;;
        
    "realtime-users"|"traffic-sources"|"page-views"|"conversions"|"audience-overview")
        # Check setup first
        if ! check_ga4_setup || ! check_python_deps; then
            exit 1
        fi
        
        log_info "Executing GA4 action: $ACTION"
        
        # Extract days parameter if provided
        days=30
        if [[ -n "$PARAMS" && "$PARAMS" =~ days= ]]; then
            days=$(echo "$PARAMS" | sed -n 's/.*days=\([^&]*\).*/\1/p')
        fi
        
        # Create and execute Python script
        python_script=$(create_ga4_python_script)
        
        # Execute the Python script
        python3 "$python_script" "$ACTION" "$GA4_PROPERTY_ID" "$days"
        
        # Clean up
        rm -f "$python_script"
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: setup-check, realtime-users, traffic-sources, page-views, conversions, audience-overview"
        exit 1
        ;;
esac