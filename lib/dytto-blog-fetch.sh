#!/bin/bash
# Dytto Blog Integration
# Usage: ./dytto-blog-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  create-post           - Create a new blog post"
    echo "  create-post-from-file - Create blog post from file content"
    echo "  list-posts            - List existing blog posts"
    echo "  update-post           - Update existing blog post"
    echo "  delete-post           - Delete blog post"
    echo "  get-post             - Get specific blog post"
    echo "  setup-check          - Verify blog API setup"
    echo ""
    echo "Examples:"
    echo "  $0 setup-check"
    echo "  $0 create-post 'title=My Blog Post&content=This is the content&author=John&tags=tech,marketing'"
    echo "  $0 create-post-from-file 'title=My Blog Post&file=/path/to/content.md&author=John&tags=tech,marketing'"
    echo "  $0 list-posts"
    echo "  $0 get-post 'slug=my-blog-post'"
    exit 1
fi

# Find and load environment variables
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
check_blog_setup() {
    local setup_ok=true
    
    if [[ -z "$VITE_SUPABASE_URL" ]]; then
        log_error "VITE_SUPABASE_URL not found in environment"
        echo "Please add your Supabase URL to .env file:"
        echo "VITE_SUPABASE_URL=https://your-project.supabase.co"
        setup_ok=false
    fi
    
    if [[ -z "$SUPABASE_SERVICE_ROLE_KEY" ]]; then
        log_error "SUPABASE_SERVICE_ROLE_KEY not found in environment"
        echo "Please add your Supabase service role key to .env file:"
        echo "SUPABASE_SERVICE_ROLE_KEY=your_service_role_key"
        setup_ok=false
    fi
    
    if [[ "$setup_ok" == "false" ]]; then
        echo ""
        echo "Dytto Blog Setup Guide:"
        echo "1. Go to your Supabase project dashboard"
        echo "2. Go to Settings → API"
        echo "3. Copy the URL and service_role key"
        echo "4. Add both to your .env file"
        return 1
    fi
    
    return 0
}

# Parse URL parameters into variables
parse_params() {
    if [[ -n "$PARAMS" ]]; then
        # Split by & and set variables
        IFS='&' read -ra PARAM_ARRAY <<< "$PARAMS"
        for param in "${PARAM_ARRAY[@]}"; do
            if [[ $param =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                # URL decode value
                value=$(printf '%b' "${value//%/\\x}" | sed 's/+/ /g')
                declare -g "PARAM_$key"="$value"
            fi
        done
    fi
}

# Generate URL-friendly slug from title
generate_slug() {
    local title="$1"
    echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g'
}

# Exponential backoff retry function
retry_with_backoff() {
    local max_attempts=3
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

# Supabase API call wrapper
supabase_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local url="${VITE_SUPABASE_URL}/rest/v1/${endpoint}"
    
    local curl_cmd=(
        curl -s -w "%{http_code}"
        -X "$method"
        -H "apikey: $SUPABASE_SERVICE_ROLE_KEY"
        -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
        -H "Content-Type: application/json"
        -H "Prefer: return=representation"
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
        log_error "API call failed with HTTP $http_code"
        if command -v jq >/dev/null 2>&1; then
            echo "$response" | jq '.' >&2 || echo "$response" >&2
        else
            echo "$response" >&2
        fi
        return 1
    fi
}

# Parse parameters
parse_params

# Action implementations
case "$ACTION" in
    "setup-check")
        log_info "Checking Dytto blog setup"
        
        if check_blog_setup; then
            log_info "✅ Dytto blog setup is complete and ready to use"
            
            # Test API connectivity
            if retry_with_backoff supabase_api_call "GET" "blog_posts?limit=1"; then
                echo '{"status": "ready", "message": "Dytto blog integration is properly configured"}'
            else
                echo '{"status": "error", "message": "API credentials configured but connection failed"}'
                exit 1
            fi
        else
            echo '{"status": "incomplete", "message": "Dytto blog setup requires configuration"}'
            exit 1
        fi
        ;;
        
    "create-post")
        if ! check_blog_setup; then
            exit 1
        fi
        
        if [[ -z "$PARAM_title" || -z "$PARAM_content" ]]; then
            log_error "title and content parameters required for create-post"
            echo "Usage: $0 create-post 'title=My Title&content=My content&author=John&tags=tech,marketing'"
            exit 1
        fi
        
        log_info "Creating blog post: $PARAM_title"
        
        # Generate slug from title
        slug=$(generate_slug "$PARAM_title")
        
        # Parse tags if provided
        tags_json="[]"
        if [[ -n "$PARAM_tags" ]]; then
            # Convert comma-separated tags to JSON array
            IFS=',' read -ra TAG_ARRAY <<< "$PARAM_tags"
            tags_json=$(printf '"%s",' "${TAG_ARRAY[@]}" | sed 's/,$//' | sed 's/^/[/' | sed 's/$/]/')
        fi
        
        # Create JSON payload
        json_data=$(jq -n \
            --arg title "$PARAM_title" \
            --arg slug "$slug" \
            --arg content "$PARAM_content" \
            --arg author "${PARAM_author:-CMO Agent}" \
            --argjson tags "$tags_json" \
            --arg status "${PARAM_status:-published}" \
            '{
                title: $title,
                slug: $slug,
                content: $content,
                author: $author,
                tags: $tags,
                status: $status
            }')
        
        retry_with_backoff supabase_api_call "POST" "blog_posts" "$json_data"
        ;;
        
    "create-post-from-file")
        if ! check_blog_setup; then
            exit 1
        fi
        
        if [[ -z "$PARAM_title" || -z "$PARAM_file" ]]; then
            log_error "title and file parameters required for create-post-from-file"
            echo "Usage: $0 create-post-from-file 'title=My Title&file=/path/to/content.md&author=John&tags=tech,marketing'"
            exit 1
        fi
        
        if [[ ! -f "$PARAM_file" ]]; then
            log_error "Content file not found: $PARAM_file"
            exit 1
        fi
        
        log_info "Creating blog post from file: $PARAM_title"
        
        # Read content from file
        content=$(cat "$PARAM_file")
        
        # Generate slug from title
        slug=$(generate_slug "$PARAM_title")
        
        # Parse tags if provided
        tags_json="[]"
        if [[ -n "$PARAM_tags" ]]; then
            # Convert comma-separated tags to JSON array
            IFS=',' read -ra TAG_ARRAY <<< "$PARAM_tags"
            tags_json=$(printf '"%s",' "${TAG_ARRAY[@]}" | sed 's/,$//' | sed 's/^/[/' | sed 's/$/]/')
        fi
        
        # Create JSON payload
        json_data=$(jq -n \
            --arg title "$PARAM_title" \
            --arg slug "$slug" \
            --arg content "$content" \
            --arg author "${PARAM_author:-CMO Agent}" \
            --argjson tags "$tags_json" \
            --arg status "${PARAM_status:-published}" \
            '{
                title: $title,
                slug: $slug,
                content: $content,
                author: $author,
                tags: $tags,
                status: $status
            }')
        
        retry_with_backoff supabase_api_call "POST" "blog_posts" "$json_data"
        ;;
        
    "list-posts")
        if ! check_blog_setup; then
            exit 1
        fi
        
        log_info "Fetching blog posts list"
        
        limit="${PARAM_limit:-10}"
        order="${PARAM_order:-created_at.desc}"
        
        retry_with_backoff supabase_api_call "GET" "blog_posts?limit=$limit&order=$order"
        ;;
        
    "get-post")
        if ! check_blog_setup; then
            exit 1
        fi
        
        if [[ -z "$PARAM_slug" ]]; then
            log_error "slug parameter required for get-post"
            echo "Usage: $0 get-post 'slug=my-blog-post'"
            exit 1
        fi
        
        log_info "Fetching blog post: $PARAM_slug"
        
        retry_with_backoff supabase_api_call "GET" "blog_posts?slug=eq.$PARAM_slug"
        ;;
        
    "update-post")
        if ! check_blog_setup; then
            exit 1
        fi
        
        if [[ -z "$PARAM_slug" ]]; then
            log_error "slug parameter required for update-post"
            echo "Usage: $0 update-post 'slug=my-post&title=New Title&content=New content'"
            exit 1
        fi
        
        log_info "Updating blog post: $PARAM_slug"
        
        # Build update JSON dynamically based on provided parameters
        local json_data="{}"
        
        if [[ -n "$PARAM_title" ]]; then
            json_data=$(echo "$json_data" | jq --arg title "$PARAM_title" '. + {title: $title}')
        fi
        
        if [[ -n "$PARAM_content" ]]; then
            json_data=$(echo "$json_data" | jq --arg content "$PARAM_content" '. + {content: $content}')
        fi
        
        if [[ -n "$PARAM_author" ]]; then
            json_data=$(echo "$json_data" | jq --arg author "$PARAM_author" '. + {author: $author}')
        fi
        
        if [[ -n "$PARAM_status" ]]; then
            json_data=$(echo "$json_data" | jq --arg status "$PARAM_status" '. + {status: $status}')
        fi
        
        if [[ -n "$PARAM_tags" ]]; then
            IFS=',' read -ra TAG_ARRAY <<< "$PARAM_tags"
            local tags_json
            tags_json=$(printf '"%s",' "${TAG_ARRAY[@]}" | sed 's/,$//' | sed 's/^/[/' | sed 's/$/]/')
            json_data=$(echo "$json_data" | jq --argjson tags "$tags_json" '. + {tags: $tags}')
        fi
        
        retry_with_backoff supabase_api_call "PATCH" "blog_posts?slug=eq.$PARAM_slug" "$json_data"
        ;;
        
    "delete-post")
        if ! check_blog_setup; then
            exit 1
        fi
        
        if [[ -z "$PARAM_slug" ]]; then
            log_error "slug parameter required for delete-post"
            echo "Usage: $0 delete-post 'slug=my-blog-post'"
            exit 1
        fi
        
        log_info "Deleting blog post: $PARAM_slug"
        
        retry_with_backoff supabase_api_call "DELETE" "blog_posts?slug=eq.$PARAM_slug"
        ;;
        
    "marketing-post")
        if ! check_blog_setup; then
            exit 1
        fi
        
        if [[ -z "$PARAM_topic" ]]; then
            log_error "topic parameter required for marketing-post"
            echo "Usage: $0 marketing-post 'topic=product launch&audience=developers&length=800'"
            exit 1
        fi
        
        log_info "Creating marketing blog post about: $PARAM_topic"
        
        # Generate blog content using Claude (or could integrate with OpenAI)
        local title="$PARAM_topic"
        local content="This is a marketing blog post about $PARAM_topic targeted at ${PARAM_audience:-general audience}. 
        
This post would normally be generated by Claude or another content generation system with detailed, engaging content about the topic.

Key points to cover:
- Introduction to the topic
- Key benefits and features
- Real-world applications
- Call to action

Length: ${PARAM_length:-800} words
Tone: ${PARAM_tone:-professional and engaging}"
        
        # Generate slug
        local slug
        slug=$(generate_slug "$title")
        
        # Create JSON payload
        local json_data
        json_data=$(jq -n \
            --arg title "$title" \
            --arg slug "$slug" \
            --arg content "$content" \
            --arg author "CMO Agent" \
            --argjson tags '["marketing", "content"]' \
            --arg status "published" \
            '{
                title: $title,
                slug: $slug,
                content: $content,
                author: $author,
                tags: $tags,
                status: $status
            }')
        
        retry_with_backoff supabase_api_call "POST" "blog_posts" "$json_data"
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: setup-check, create-post, create-post-from-file, list-posts, get-post, update-post, delete-post, marketing-post"
        exit 1
        ;;
esac