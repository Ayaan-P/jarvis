#!/bin/bash
# Image generation automation for content-creator agent
# Usage: ./image-generator.sh "prompt" "style" "dimensions" [model]
# Usage: ./image-generator.sh "professional headshot of a CEO" "corporate" "1024x1024" "custom"

source "${BASH_SOURCE%/*}/utils.sh"

PROMPT="$1"
STYLE="${2:-default}"
DIMENSIONS="${3:-1024x1024}"
MODEL_TYPE="${4:-replicate}"

if [[ -z "$PROMPT" ]]; then
    echo "Usage: $0 <prompt> [style] [dimensions] [model_type]"
    echo ""
    echo "Examples:"
    echo "  $0 'professional headshot of a CEO' corporate 1024x1024"
    echo "  $0 'abstract art background' creative 1792x1024 custom"
    echo "  $0 'product photo on white background' clean 1024x1024"
    exit 1
fi

# Find and load environment variables
ENV_PATHS=(
    "./.env"
    "../Claude-Agentic-Files/.env"
    "/home/ayaan/Projects/Claude-Agentic-Files/.env"
    "$HOME/.env"
)

for env_path in "${ENV_PATHS[@]}"; do
    if [[ -f "$env_path" ]]; then
        source "$env_path"
        break
    fi
done

# Create output directory
OUTPUT_DIR="/tmp/generated_images"
mkdir -p "$OUTPUT_DIR"

log_info "Generating image: '$PROMPT'"
log_info "Style: $STYLE, Dimensions: $DIMENSIONS, Model: $MODEL_TYPE"

# Function to generate image using Replicate API
generate_with_replicate() {
    local prompt="$1"
    local model_version="$2"
    
    log_info "Using Replicate API with model: $model_version"
    
    # Check for custom models from the finetune project
    if [[ "$MODEL_TYPE" == "custom" ]]; then
        # Check if finetune project has custom models available
        local finetune_models_file="/home/ayaan/projects/finetune/custom_models.json"
        if [[ -f "$finetune_models_file" ]]; then
            log_info "Checking for custom fine-tuned models..."
            # You would read from your custom models here
            # For now, fall back to standard model
        fi
    fi
    
    # Default to your custom model if no specific model provided
    if [[ -z "$model_version" ]]; then
        model_version="ayaan-p/shinkai_landscape-b6b49eae"
    fi
    
    # Enhance prompt based on style
    local enhanced_prompt="$prompt"
    case "$STYLE" in
        "corporate"|"professional")
            enhanced_prompt="professional, clean, corporate style, $prompt, high quality, studio lighting"
            ;;
        "creative"|"artistic")
            enhanced_prompt="creative, artistic, vibrant colors, $prompt, detailed, masterpiece"
            ;;
        "clean"|"minimal")
            enhanced_prompt="clean, minimal, simple, $prompt, white background, product photography"
            ;;
        "social"|"instagram")
            enhanced_prompt="social media optimized, trendy, $prompt, bright colors, engaging"
            ;;
    esac
    
    log_info "Enhanced prompt: $enhanced_prompt"
    
    # Parse dimensions for aspect ratio
    local width height aspect_ratio
    IFS='x' read -r width height <<< "$DIMENSIONS"
    if [[ "$width" -eq "$height" ]]; then
        aspect_ratio="1:1"
    elif [[ "$width" -gt "$height" ]]; then
        # Landscape ratios
        local ratio=$(python3 -c "print(f'{$width/$height:.1f}')" 2>/dev/null || echo "1.8")
        if [[ "$ratio" == "1.8" ]]; then
            aspect_ratio="16:9"
        else
            aspect_ratio="4:3"
        fi
    else
        # Portrait ratios
        aspect_ratio="2:3"
    fi
    
    # Create prediction using Replicate API
    local response=$(curl -s -X POST \
        -H "Authorization: Bearer $REPLICATE_API_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Prefer: wait" \
        -d "{
            \"version\": \"$(get_model_version $model_version)\",
            \"input\": {
                \"prompt\": \"$enhanced_prompt\",
                \"model\": \"dev\",
                \"go_fast\": false,
                \"lora_scale\": 1,
                \"megapixels\": \"1\",
                \"num_outputs\": 1,
                \"aspect_ratio\": \"$aspect_ratio\",
                \"output_format\": \"webp\",
                \"guidance_scale\": 3,
                \"output_quality\": 80,
                \"prompt_strength\": 0.8,
                \"extra_lora_scale\": 1,
                \"num_inference_steps\": 28
            }
        }" \
        https://api.replicate.com/v1/predictions)
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'output' in data and data['output']:
        urls = data['output'] if isinstance(data['output'], list) else [data['output']]
        for i, url in enumerate(urls):
            print(f'IMAGE_URL_{i}={url}')
    elif 'id' in data:
        print(f'PREDICTION_ID={data[\"id\"]}')
        print('STATUS=processing')
    else:
        print('ERROR=Invalid response format')
        print(f'RESPONSE={json.dumps(data)}', file=sys.stderr)
except Exception as e:
    print(f'ERROR=JSON parsing failed: {e}', file=sys.stderr)
"
    else
        log_error "Failed to create Replicate prediction"
        return 1
    fi
}

# Function to get model version (simplified for now)
get_model_version() {
    local model="$1"
    case "$model" in
        "ayaan-p/shinkai_landscape-b6b49eae")
            # Your custom model
            echo "00b7a0d78097cc51ff550ea9fd3072966667cca8cf728d9faa9b366a1a367b29"
            ;;
        "black-forest-labs/flux-schnell")
            # FLUX.1 Schnell - fast, free model
            echo "bf2f8b5ca850b7f35d8bb32bfb7876638b98c5b0e1c0bf21a60c6c86d8da6e89"
            ;;
        "stability-ai/stable-diffusion-3.5-large")
            # Known working version for SD 3.5 Large 
            echo "75d51a73fce3c00de31ed9ab4358c59e8422c68563bbf2f4bf1d9ab6c47e33d0"
            ;;
        *)
            # Default to your custom model
            echo "00b7a0d78097cc51ff550ea9fd3072966667cca8cf728d9faa9b366a1a367b29"
            ;;
    esac
}

# Function to download image from URL
download_image() {
    local url="$1"
    local filename="$2"
    
    log_info "Downloading image from: $url"
    
    curl -s -o "$filename" "$url"
    if [[ $? -eq 0 && -f "$filename" ]]; then
        local file_size=$(stat -f%z "$filename" 2>/dev/null || stat -c%s "$filename" 2>/dev/null)
        if [[ "$file_size" -gt 1000 ]]; then
            log_info "Image downloaded successfully: $filename (${file_size} bytes)"
            return 0
        else
            log_error "Downloaded file is too small, might be corrupted"
            return 1
        fi
    else
        log_error "Failed to download image"
        return 1
    fi
}

# Function to poll prediction status
poll_prediction() {
    local prediction_id="$1"
    local max_attempts=30
    local attempt=0
    
    log_info "Polling prediction status: $prediction_id"
    
    while [[ $attempt -lt $max_attempts ]]; do
        local response=$(curl -s \
            -H "Authorization: Bearer $REPLICATE_API_TOKEN" \
            https://api.replicate.com/v1/predictions/$prediction_id)
        
        local status=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('status', 'unknown'))
except:
    print('error')
")
        
        log_info "Prediction status: $status (attempt $((attempt + 1))/$max_attempts)"
        
        case "$status" in
            "succeeded")
                echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'output' in data and data['output']:
        urls = data['output'] if isinstance(data['output'], list) else [data['output']]
        for i, url in enumerate(urls):
            print(f'IMAGE_URL_{i}={url}')
except Exception as e:
    print(f'ERROR=Failed to parse output: {e}', file=sys.stderr)
"
                return 0
                ;;
            "failed"|"canceled")
                local error=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('error', 'Unknown error'))
except:
    print('Failed to parse error')
")
                log_error "Prediction failed: $error"
                return 1
                ;;
            "processing"|"starting")
                sleep 5
                ((attempt++))
                ;;
            *)
                log_error "Unknown prediction status: $status"
                return 1
                ;;
        esac
    done
    
    log_error "Prediction timed out after $max_attempts attempts"
    return 1
}

# Main execution
main() {
    if [[ -z "$REPLICATE_API_TOKEN" ]]; then
        log_error "REPLICATE_API_TOKEN not found in environment"
        return 1
    fi
    
    # Generate timestamp for unique filenames
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local base_filename="generated_${timestamp}"
    
    # Generate image
    local generation_result=$(generate_with_replicate "$PROMPT")
    
    # Process the result
    if echo "$generation_result" | grep -q "IMAGE_URL_"; then
        # Direct image URL returned
        local image_urls=($(echo "$generation_result" | grep "IMAGE_URL_" | cut -d'=' -f2))
        
        for i in "${!image_urls[@]}"; do
            local filename="$OUTPUT_DIR/${base_filename}_$i.png"
            if download_image "${image_urls[$i]}" "$filename"; then
                echo "✅ Generated image saved: $filename"
                
                # Store generation info
                cat > "$OUTPUT_DIR/${base_filename}_info.txt" << EOF
Generated: $(date)
Prompt: $PROMPT
Style: $STYLE
Dimensions: $DIMENSIONS
Model: $MODEL_TYPE
Original URL: ${image_urls[$i]}
Local File: $filename
EOF
                
                log_info "Generation complete: $filename"
                return 0
            fi
        done
    elif echo "$generation_result" | grep -q "PREDICTION_ID="; then
        # Async prediction, need to poll
        local prediction_id=$(echo "$generation_result" | grep "PREDICTION_ID=" | cut -d'=' -f2)
        
        if poll_result=$(poll_prediction "$prediction_id"); then
            local image_urls=($(echo "$poll_result" | grep "IMAGE_URL_" | cut -d'=' -f2))
            
            for i in "${!image_urls[@]}"; do
                local filename="$OUTPUT_DIR/${base_filename}_$i.png"
                if download_image "${image_urls[$i]}" "$filename"; then
                    echo "✅ Generated image saved: $filename"
                    
                    # Store generation info  
                    cat > "$OUTPUT_DIR/${base_filename}_info.txt" << EOF
Generated: $(date)
Prompt: $PROMPT
Style: $STYLE
Dimensions: $DIMENSIONS
Model: $MODEL_TYPE
Prediction ID: $prediction_id
Original URL: ${image_urls[$i]}
Local File: $filename
EOF
                    
                    log_info "Generation complete: $filename"
                    return 0
                fi
            done
        fi
    else
        log_error "Failed to generate image"
        echo "$generation_result" >&2
        return 1
    fi
    
    log_error "Image generation failed"
    return 1
}

# Help command
case "${1:-help}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 <prompt> [style] [dimensions] [model_type]"
        echo ""
        echo "Arguments:"
        echo "  prompt      Text description of the image to generate (required)"
        echo "  style       Style preset: corporate, creative, clean, social (default: default)"
        echo "  dimensions  Image size in WxH format (default: 1024x1024)"
        echo "  model_type  Model to use: replicate, custom (default: replicate)"
        echo ""
        echo "Styles:"
        echo "  corporate   - Professional, clean, corporate style with studio lighting"
        echo "  creative    - Artistic, vibrant colors, detailed masterpiece style"
        echo "  clean       - Minimal, simple, white background, product photography"
        echo "  social      - Social media optimized, trendy, bright colors"
        echo ""
        echo "Examples:"
        echo "  $0 'professional headshot of a CEO' corporate 1024x1024"
        echo "  $0 'abstract art background' creative 1792x1024"
        echo "  $0 'product photo on white background' clean"
        echo "  $0 'trendy social media post design' social 1080x1080"
        ;;
    *)
        main
        ;;
esac