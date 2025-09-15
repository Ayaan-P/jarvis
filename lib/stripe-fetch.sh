#!/bin/bash
# Stripe Revenue Attribution Integration
# Usage: ./stripe-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  charges               - Get recent charges/payments"
    echo "  customers             - Get customer data"
    echo "  subscriptions         - Get subscription data"
    echo "  invoices              - Get invoice data"
    echo "  revenue-summary       - Calculate revenue metrics"
    echo "  mrr-analysis          - Monthly Recurring Revenue analysis"
    echo "  churn-analysis        - Customer churn analysis"
    echo "  cac-calculation       - Customer Acquisition Cost calculation"
    echo ""
    echo "Examples:"
    echo "  $0 charges 'limit=10'"
    echo "  $0 revenue-summary"
    echo "  $0 mrr-analysis"
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

if [[ -z "$STRIPE_API_KEY" ]]; then
    echo "Error: STRIPE_API_KEY not found in environment"
    echo "Please add your Stripe API key to .env file:"
    echo "STRIPE_API_KEY=sk_live_your_key_here  # or sk_test_ for testing"
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
stripe_api_call() {
    local endpoint="$1"
    local query_params="$2"
    local url="https://api.stripe.com/v1/${endpoint}"
    
    if [[ -n "$query_params" ]]; then
        url="${url}?${query_params}"
    fi
    
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $STRIPE_API_KEY" \
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
    "charges")
        log_info "Fetching Stripe charges/payments"
        local limit="${PARAMS:-limit=25}"
        retry_with_backoff stripe_api_call "charges" "${limit}"
        ;;
        
    "customers")
        log_info "Fetching Stripe customers"
        local limit="${PARAMS:-limit=25}"
        retry_with_backoff stripe_api_call "customers" "${limit}"
        ;;
        
    "subscriptions")
        log_info "Fetching Stripe subscriptions"
        local limit="${PARAMS:-limit=25}"
        retry_with_backoff stripe_api_call "subscriptions" "${limit}"
        ;;
        
    "invoices")
        log_info "Fetching Stripe invoices"
        local limit="${PARAMS:-limit=25}"
        retry_with_backoff stripe_api_call "invoices" "${limit}"
        ;;
        
    "revenue-summary")
        log_info "Calculating revenue summary"
        
        # Get charges from last 30 days
        local start_date=$(date -d '30 days ago' '+%s')
        local charges_response
        charges_response=$(retry_with_backoff stripe_api_call "charges" "limit=100&created[gte]=${start_date}")
        
        if [[ $? -eq 0 ]]; then
            echo "$charges_response" | jq -r --arg start_date "$start_date" '
                .data as $charges |
                ($charges | map(select(.paid == true) | .amount) | add // 0) as $total_revenue |
                ($charges | map(select(.paid == true)) | length) as $successful_charges |
                ($charges | map(select(.paid == false)) | length) as $failed_charges |
                {
                    "period": "Last 30 days",
                    "total_revenue_cents": $total_revenue,
                    "total_revenue_dollars": ($total_revenue / 100),
                    "successful_charges": $successful_charges,
                    "failed_charges": $failed_charges,
                    "success_rate": (if ($successful_charges + $failed_charges) > 0 then ($successful_charges / ($successful_charges + $failed_charges) * 100) else 0 end),
                    "average_transaction": (if $successful_charges > 0 then ($total_revenue / $successful_charges / 100) else 0 end)
                }'
        fi
        ;;
        
    "mrr-analysis")
        log_info "Calculating Monthly Recurring Revenue (MRR)"
        
        # Get active subscriptions
        local subscriptions_response
        subscriptions_response=$(retry_with_backoff stripe_api_call "subscriptions" "status=active&limit=100")
        
        if [[ $? -eq 0 ]]; then
            echo "$subscriptions_response" | jq -r '
                .data as $subscriptions |
                ($subscriptions | map(.items.data[0].price.unit_amount * .items.data[0].quantity) | add // 0) as $total_mrr_cents |
                {
                    "active_subscriptions": ($subscriptions | length),
                    "mrr_cents": $total_mrr_cents,
                    "mrr_dollars": ($total_mrr_cents / 100),
                    "arr_dollars": ($total_mrr_cents / 100 * 12),
                    "average_subscription_value": (if ($subscriptions | length) > 0 then ($total_mrr_cents / ($subscriptions | length) / 100) else 0 end),
                    "subscription_breakdown": ($subscriptions | group_by(.items.data[0].price.unit_amount) | map({
                        "price_point": (.[0].items.data[0].price.unit_amount / 100),
                        "count": length,
                        "total_mrr": (length * .[0].items.data[0].price.unit_amount / 100)
                    }))
                }'
        fi
        ;;
        
    "churn-analysis")
        log_info "Analyzing customer churn"
        
        # Get canceled subscriptions from last 30 days
        local start_date=$(date -d '30 days ago' '+%s')
        local canceled_subs
        canceled_subs=$(retry_with_backoff stripe_api_call "subscriptions" "status=canceled&limit=100")
        
        local active_subs
        active_subs=$(retry_with_backoff stripe_api_call "subscriptions" "status=active&limit=100")
        
        if [[ $? -eq 0 ]]; then
            echo "$canceled_subs $active_subs" | jq -s -r --arg start_date "$start_date" '
                .[0].data as $canceled |
                .[1].data as $active |
                ($canceled | map(select(.canceled_at >= ($start_date | tonumber))) | length) as $recent_cancellations |
                ($active | length) as $active_count |
                {
                    "period": "Last 30 days",
                    "cancellations": $recent_cancellations,
                    "active_subscriptions": $active_count,
                    "churn_rate_percent": (if ($active_count + $recent_cancellations) > 0 then ($recent_cancellations / ($active_count + $recent_cancellations) * 100) else 0 end),
                    "retention_rate_percent": (if ($active_count + $recent_cancellations) > 0 then ($active_count / ($active_count + $recent_cancellations) * 100) else 100 end)
                }'
        fi
        ;;
        
    "cac-calculation")
        log_info "Calculating Customer Acquisition Cost (CAC)"
        
        # Note: This requires marketing spend data to be provided as parameter
        local marketing_spend
        if [[ -n "$PARAMS" && "$PARAMS" =~ marketing_spend= ]]; then
            marketing_spend=$(echo "$PARAMS" | sed -n 's/.*marketing_spend=\([^&]*\).*/\1/p')
        else
            echo "Error: marketing_spend parameter required for CAC calculation"
            echo "Usage: $0 cac-calculation 'marketing_spend=5000'"
            exit 1
        fi
        
        # Get new customers from last 30 days
        local start_date=$(date -d '30 days ago' '+%s')
        local customers_response
        customers_response=$(retry_with_backoff stripe_api_call "customers" "limit=100&created[gte]=${start_date}")
        
        if [[ $? -eq 0 ]]; then
            echo "$customers_response" | jq -r --arg marketing_spend "$marketing_spend" --arg start_date "$start_date" '
                .data as $customers |
                ($customers | length) as $new_customers |
                {
                    "period": "Last 30 days",
                    "new_customers": $new_customers,
                    "marketing_spend_dollars": ($marketing_spend | tonumber),
                    "cac_dollars": (if $new_customers > 0 then (($marketing_spend | tonumber) / $new_customers) else 0 end),
                    "customers_acquired": $new_customers
                }'
        fi
        ;;
        
    "ltv-calculation")
        log_info "Calculating Customer Lifetime Value (LTV)"
        
        # Get subscription data for LTV calculation
        local subscriptions_response
        subscriptions_response=$(retry_with_backoff stripe_api_call "subscriptions" "limit=100")
        
        if [[ $? -eq 0 ]]; then
            echo "$subscriptions_response" | jq -r '
                .data as $subscriptions |
                ($subscriptions | map(.items.data[0].price.unit_amount / 100) | add / length) as $avg_monthly_value |
                # Assume average customer lifetime of 24 months (adjust based on your data)
                ($avg_monthly_value * 24) as $estimated_ltv |
                {
                    "average_monthly_value": $avg_monthly_value,
                    "estimated_customer_lifetime_months": 24,
                    "estimated_ltv_dollars": $estimated_ltv,
                    "active_subscriptions_analyzed": ($subscriptions | length)
                }'
        fi
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: charges, customers, subscriptions, invoices, revenue-summary, mrr-analysis, churn-analysis, cac-calculation, ltv-calculation"
        exit 1
        ;;
esac