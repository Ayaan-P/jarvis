#!/bin/bash
# OpenAI Content Generation Integration
# Usage: ./openai-content-fetch.sh <action> [params]

set -e

ACTION="$1"
PARAMS="$2"

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <action> [params]"
    echo "Actions:"
    echo "  generate-text         - Generate text content"
    echo "  generate-image        - Generate image content"
    echo "  social-post           - Generate social media post"
    echo "  blog-post            - Generate blog post content"
    echo "  ad-copy              - Generate advertisement copy"
    echo "  email-content        - Generate email marketing content"
    echo "  product-description  - Generate product descriptions"
    echo "  analyze-tone         - Analyze content tone and sentiment"
    echo ""
    echo "Examples:"
    echo "  $0 social-post 'topic=new product launch&platform=instagram&tone=excited'"
    echo "  $0 blog-post 'topic=marketing trends 2025&length=800'"
    echo "  $0 generate-image 'prompt=modern marketing dashboard&style=professional'"
    echo "  $0 ad-copy 'product=SaaS tool&audience=small business owners'"
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

if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "Error: OPENAI_API_KEY not found in environment"
    echo "Please add your OpenAI API key to .env file:"
    echo "OPENAI_API_KEY=sk-your_key_here"
    exit 1
fi

# Utility functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
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
                value=$(printf '%b' "${value//%/\\x}")
                declare -g "PARAM_$key"="$value"
            fi
        done
    fi
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

# OpenAI API call wrapper
openai_api_call() {
    local endpoint="$1"
    local data="$2"
    
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "https://api.openai.com/v1/$endpoint")
    
    http_code=${response: -3}
    response=${response%???}
    
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        echo "$response"
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

# Create structured prompt based on content type
create_content_prompt() {
    local content_type="$1"
    local topic="$2"
    local platform="$3"
    local tone="$4"
    local length="$5"
    local audience="$6"
    local product="$7"
    
    case "$content_type" in
        "social-post")
            echo "Create an engaging ${platform:-social media} post about '$topic'. Tone: ${tone:-professional}. Include relevant hashtags and call-to-action. Keep it under ${length:-280} characters if for Twitter, or under ${length:-2200} characters for other platforms."
            ;;
        "blog-post")
            echo "Write a comprehensive blog post about '$topic'. Length: approximately ${length:-800} words. Tone: ${tone:-informative and engaging}. Target audience: ${audience:-general business audience}. Include an introduction, main points, and conclusion. Make it SEO-friendly."
            ;;
        "ad-copy")
            echo "Create compelling advertisement copy for '$product'. Target audience: ${audience:-general consumers}. Tone: ${tone:-persuasive}. Include a strong headline, key benefits, and clear call-to-action. Keep the main copy under ${length:-150} words."
            ;;
        "email-content")
            echo "Write an email marketing campaign about '$topic'. Tone: ${tone:-professional and friendly}. Target audience: ${audience:-subscribers}. Include subject line, engaging opening, main content, and clear call-to-action. Length: ${length:-300-500} words."
            ;;
        "product-description")
            echo "Write a compelling product description for '$product'. Target audience: ${audience:-potential customers}. Tone: ${tone:-professional and persuasive}. Highlight key features, benefits, and value proposition. Length: ${length:-100-200} words."
            ;;
        *)
            echo "$topic"
            ;;
    esac
}

# Parse parameters
parse_params

# Action implementations
case "$ACTION" in
    "generate-text")
        if [[ -z "$PARAM_prompt" ]]; then
            log_error "prompt parameter required for generate-text"
            echo "Usage: $0 generate-text 'prompt=your text prompt here'"
            exit 1
        fi
        
        log_info "Generating text content"
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$PARAM_prompt" \
            --argjson max_tokens "${PARAM_max_tokens:-1000}" \
            --argjson temperature "${PARAM_temperature:-0.7}" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: $max_tokens,
                temperature: $temperature
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    "generate-image")
        if [[ -z "$PARAM_prompt" ]]; then
            log_error "prompt parameter required for generate-image"
            echo "Usage: $0 generate-image 'prompt=your image description&size=1024x1024'"
            exit 1
        fi
        
        log_info "Generating image content"
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-image-1}" \
            --arg prompt "$PARAM_prompt" \
            --arg size "${PARAM_size:-1024x1024}" \
            --argjson n "${PARAM_n:-1}" \
            '{
                model: $model,
                prompt: $prompt,
                size: $size,
                n: $n,
                response_format: "url"
            }')
        
        retry_with_backoff openai_api_call "images/generations" "$json_data"
        ;;
        
    "social-post")
        if [[ -z "$PARAM_topic" ]]; then
            log_error "topic parameter required for social-post"
            echo "Usage: $0 social-post 'topic=your topic&platform=instagram&tone=excited'"
            exit 1
        fi
        
        log_info "Generating social media post about: $PARAM_topic"
        
        local prompt
        prompt=$(create_content_prompt "social-post" "$PARAM_topic" "$PARAM_platform" "$PARAM_tone" "$PARAM_length" "$PARAM_audience" "$PARAM_product")
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 500,
                temperature: 0.8
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    "blog-post")
        if [[ -z "$PARAM_topic" ]]; then
            log_error "topic parameter required for blog-post"
            echo "Usage: $0 blog-post 'topic=your topic&length=800&audience=business owners'"
            exit 1
        fi
        
        log_info "Generating blog post about: $PARAM_topic"
        
        local prompt
        prompt=$(create_content_prompt "blog-post" "$PARAM_topic" "$PARAM_platform" "$PARAM_tone" "$PARAM_length" "$PARAM_audience" "$PARAM_product")
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 2000,
                temperature: 0.7
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    "ad-copy")
        if [[ -z "$PARAM_product" ]]; then
            log_error "product parameter required for ad-copy"
            echo "Usage: $0 ad-copy 'product=your product&audience=target audience&tone=persuasive'"
            exit 1
        fi
        
        log_info "Generating ad copy for: $PARAM_product"
        
        local prompt
        prompt=$(create_content_prompt "ad-copy" "$PARAM_topic" "$PARAM_platform" "$PARAM_tone" "$PARAM_length" "$PARAM_audience" "$PARAM_product")
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 800,
                temperature: 0.8
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    "email-content")
        if [[ -z "$PARAM_topic" ]]; then
            log_error "topic parameter required for email-content"
            echo "Usage: $0 email-content 'topic=your topic&audience=subscribers&tone=friendly'"
            exit 1
        fi
        
        log_info "Generating email content about: $PARAM_topic"
        
        local prompt
        prompt=$(create_content_prompt "email-content" "$PARAM_topic" "$PARAM_platform" "$PARAM_tone" "$PARAM_length" "$PARAM_audience" "$PARAM_product")
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 1200,
                temperature: 0.7
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    "product-description")
        if [[ -z "$PARAM_product" ]]; then
            log_error "product parameter required for product-description"
            echo "Usage: $0 product-description 'product=your product&audience=customers&tone=professional'"
            exit 1
        fi
        
        log_info "Generating product description for: $PARAM_product"
        
        local prompt
        prompt=$(create_content_prompt "product-description" "$PARAM_topic" "$PARAM_platform" "$PARAM_tone" "$PARAM_length" "$PARAM_audience" "$PARAM_product")
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 600,
                temperature: 0.7
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    "analyze-tone")
        if [[ -z "$PARAM_content" ]]; then
            log_error "content parameter required for analyze-tone"
            echo "Usage: $0 analyze-tone 'content=your content to analyze'"
            exit 1
        fi
        
        log_info "Analyzing tone and sentiment"
        
        local prompt="Analyze the tone, sentiment, and style of the following content. Provide insights on emotional tone, formality level, target audience, and suggestions for improvement:\n\n$PARAM_content"
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 800,
                temperature: 0.3
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    "content-ideas")
        local topic="${PARAM_topic:-marketing}"
        local platform="${PARAM_platform:-social media}"
        local count="${PARAM_count:-10}"
        
        log_info "Generating content ideas for: $topic"
        
        local prompt="Generate $count creative content ideas for $platform about '$topic'. For each idea, provide a brief title and description. Make them engaging and shareable."
        
        local json_data=$(jq -n \
            --arg model "${PARAM_model:-gpt-4}" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 1500,
                temperature: 0.9
            }')
        
        retry_with_backoff openai_api_call "chat/completions" "$json_data"
        ;;
        
    *)
        log_error "Unknown action: $ACTION"
        echo "Supported actions: generate-text, generate-image, social-post, blog-post, ad-copy, email-content, product-description, analyze-tone, content-ideas"
        exit 1
        ;;
esac