#!/bin/bash
# Video generation automation for content-creator agent
# Usage: ./video-generator.sh "type" "prompt" "duration" [model]
# Usage: ./video-generator.sh "image-to-video" "smooth product rotation" "5" "runway"

source "${BASH_SOURCE%/*}/utils.sh"

VIDEO_TYPE="$1"
PROMPT="$2" 
DURATION="${3:-5}"
MODEL="${4:-runway}"

if [[ -z "$VIDEO_TYPE" || -z "$PROMPT" ]]; then
    echo "Usage: $0 <type> <prompt> [duration] [model]"
    echo ""
    echo "Video Types:"
    echo "  text-to-video      - Generate video from text description"
    echo "  image-to-video     - Animate an existing image"
    echo "  video-to-video     - Transform existing video with new prompt"
    echo ""
    echo "Examples:"
    echo "  $0 text-to-video 'A professional presenter speaking to camera' 10"
    echo "  $0 image-to-video 'smooth product rotation showcasing all angles' 5"
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
OUTPUT_DIR="/tmp/generated_videos"
mkdir -p "$OUTPUT_DIR"

log_info "Generating video: Type=$VIDEO_TYPE, Prompt='$PROMPT', Duration=${DURATION}s"

# Function to generate video using Runway ML API
generate_with_runway() {
    local type="$1"
    local prompt="$2"
    local duration="$3"
    local image_url="$4"
    
    log_info "Using Runway ML API for video generation"
    
    # Determine the appropriate model and parameters
    local model="gen4_turbo"
    local ratio="1280:720"  # Default to 16:9 landscape
    
    # Adjust settings based on video type
    case "$type" in
        "text-to-video")
            if [[ -z "$RUNWAYML_API_SECRET" ]]; then
                log_error "RUNWAYML_API_SECRET not found in environment"
                return 1
            fi
            
            local response=$(curl -s -X POST \
                "https://api.dev.runwayml.com/v1/text_to_video" \
                -H "Authorization: Bearer $RUNWAYML_API_SECRET" \
                -H "Content-Type: application/json" \
                -H "X-Runway-Version: 2024-11-06" \
                -d "{
                    \"promptText\": \"$prompt\",
                    \"model\": \"$model\",
                    \"ratio\": \"$ratio\",
                    \"duration\": $duration
                }")
            ;;
        "image-to-video")
            if [[ -z "$image_url" ]]; then
                log_error "Image URL required for image-to-video generation"
                return 1
            fi
            
            local response=$(curl -s -X POST \
                "https://api.dev.runwayml.com/v1/image_to_video" \
                -H "Authorization: Bearer $RUNWAYML_API_SECRET" \
                -H "Content-Type: application/json" \
                -H "X-Runway-Version: 2024-11-06" \
                -d "{
                    \"promptImage\": \"$image_url\",
                    \"promptText\": \"$prompt\",
                    \"model\": \"$model\", 
                    \"ratio\": \"$ratio\",
                    \"duration\": $duration
                }")
            ;;
        *)
            log_error "Unsupported video type: $type"
            return 1
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'id' in data:
        print(f'TASK_ID={data[\"id\"]}')
        print(f'STATUS={data.get(\"status\", \"processing\")}')
    elif 'error' in data:
        print(f'ERROR={data[\"error\"]}', file=sys.stderr)
    else:
        print('ERROR=Invalid response format', file=sys.stderr)
        print(f'RESPONSE={json.dumps(data)}', file=sys.stderr)
except Exception as e:
    print(f'ERROR=JSON parsing failed: {e}', file=sys.stderr)
"
    else
        log_error "Failed to submit video generation request"
        return 1
    fi
}

# Function to poll video generation status
poll_video_status() {
    local task_id="$1"
    local max_attempts=60  # 5 minutes with 5-second intervals
    local attempt=0
    
    log_info "Polling video generation status: $task_id"
    
    while [[ $attempt -lt $max_attempts ]]; do
        local response=$(curl -s \
            -H "Authorization: Bearer $RUNWAYML_API_SECRET" \
            -H "X-Runway-Version: 2024-11-06" \
            "https://api.dev.runwayml.com/v1/tasks/$task_id")
        
        local status=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('status', 'unknown'))
except:
    print('error')
")
        
        log_info "Video generation status: $status (attempt $((attempt + 1))/$max_attempts)"
        
        case "$status" in
            "SUCCEEDED")
                echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'output' in data and data['output']:
        outputs = data['output'] if isinstance(data['output'], list) else [data['output']]
        for i, url in enumerate(outputs):
            print(f'VIDEO_URL_{i}={url}')
    else:
        print('ERROR=No output URLs found', file=sys.stderr)
except Exception as e:
    print(f'ERROR=Failed to parse output: {e}', file=sys.stderr)
"
                return 0
                ;;
            "FAILED")
                local error=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('failure_reason', 'Unknown error'))
except:
    print('Failed to parse error')
")
                log_error "Video generation failed: $error"
                return 1
                ;;
            "RUNNING"|"QUEUED")
                sleep 5
                ((attempt++))
                ;;
            *)
                log_error "Unknown video generation status: $status"
                return 1
                ;;
        esac
    done
    
    log_error "Video generation timed out after $max_attempts attempts"
    return 1
}

# Function to download video from URL
download_video() {
    local url="$1"
    local filename="$2"
    
    log_info "Downloading video from: $url"
    
    curl -L -s -o "$filename" "$url"
    if [[ $? -eq 0 && -f "$filename" ]]; then
        local file_size=$(stat -f%z "$filename" 2>/dev/null || stat -c%s "$filename" 2>/dev/null)
        if [[ "$file_size" -gt 10000 ]]; then  # Videos should be larger than 10KB
            log_info "Video downloaded successfully: $filename (${file_size} bytes)"
            return 0
        else
            log_error "Downloaded video file is too small, might be corrupted"
            return 1
        fi
    else
        log_error "Failed to download video"
        return 1
    fi
}

# Function to find source image for image-to-video
find_source_image() {
    local search_term="$1"
    
    # Look for recently generated images
    local recent_images=($(find /tmp/generated_images -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" 2>/dev/null | head -5))
    
    if [[ ${#recent_images[@]} -gt 0 ]]; then
        log_info "Found recent generated image: ${recent_images[0]}"
        echo "${recent_images[0]}"
        return 0
    fi
    
    # Look in common asset directories
    local asset_dirs=("./assets" "./images" "./creative")
    for dir in "${asset_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local images=($(find "$dir" -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" 2>/dev/null | head -1))
            if [[ ${#images[@]} -gt 0 ]]; then
                log_info "Found asset image: ${images[0]}"
                echo "${images[0]}"
                return 0
            fi
        fi
    done
    
    log_error "No source image found for image-to-video generation"
    return 1
}

# Function to upload local image and get URL (simplified version)
upload_image_for_video() {
    local local_image="$1"
    
    # For now, we'll assume the image needs to be accessible via URL
    # In a real implementation, you might upload to a cloud service
    log_error "Image upload not implemented. Please provide a publicly accessible image URL."
    log_info "Local image found: $local_image"
    
    # Return the local path for now (won't work with Runway API)
    echo "$local_image"
}

# Main execution
main() {
    if [[ -z "$RUNWAYML_API_SECRET" ]]; then
        log_error "RUNWAYML_API_SECRET not found in environment"
        log_info "Please add your Runway ML API key to your .env file"
        return 1
    fi
    
    # Generate timestamp for unique filenames
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local base_filename="video_${timestamp}"
    
    # Handle image-to-video type
    local image_url=""
    if [[ "$VIDEO_TYPE" == "image-to-video" ]]; then
        # Try to find a source image
        local source_image=$(find_source_image "$PROMPT")
        if [[ $? -eq 0 && -n "$source_image" ]]; then
            # For demo purposes, we'll show what would happen
            log_info "Source image for animation: $source_image"
            log_info "Note: Image needs to be publicly accessible URL for Runway API"
            
            # In a real implementation, you'd upload this to a cloud service
            # For now, we'll skip the actual generation
            echo "⚠️  Image-to-video requires publicly accessible image URL"
            echo "Found local image: $source_image"
            echo "Please upload to a cloud service and use the URL directly"
            return 1
        else
            log_error "No source image found for image-to-video generation"
            return 1
        fi
    fi
    
    # Generate video
    local generation_result
    if [[ "$VIDEO_TYPE" == "image-to-video" ]]; then
        generation_result=$(generate_with_runway "$VIDEO_TYPE" "$PROMPT" "$DURATION" "$image_url")
    else
        generation_result=$(generate_with_runway "$VIDEO_TYPE" "$PROMPT" "$DURATION")
    fi
    
    # Process the result
    if echo "$generation_result" | grep -q "TASK_ID="; then
        local task_id=$(echo "$generation_result" | grep "TASK_ID=" | cut -d'=' -f2)
        
        if poll_result=$(poll_video_status "$task_id"); then
            local video_urls=($(echo "$poll_result" | grep "VIDEO_URL_" | cut -d'=' -f2))
            
            for i in "${!video_urls[@]}"; do
                local filename="$OUTPUT_DIR/${base_filename}_$i.mp4"
                if download_video "${video_urls[$i]}" "$filename"; then
                    echo "✅ Generated video saved: $filename"
                    
                    # Store generation info
                    cat > "$OUTPUT_DIR/${base_filename}_info.txt" << EOF
Generated: $(date)
Type: $VIDEO_TYPE
Prompt: $PROMPT
Duration: ${DURATION}s
Model: $MODEL
Task ID: $task_id
Original URL: ${video_urls[$i]}
Local File: $filename
EOF
                    
                    # Try to get video info if ffprobe is available
                    if command -v ffprobe >/dev/null 2>&1; then
                        local duration_actual=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$filename" 2>/dev/null)
                        local resolution=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$filename" 2>/dev/null)
                        if [[ -n "$duration_actual" && -n "$resolution" ]]; then
                            local duration_formatted=$(python3 -c "print(f'{float('$duration_actual'):.1f}s')" 2>/dev/null || echo "${duration_actual}s")
                            echo "Video info: ${resolution}, ${duration_formatted}"
                            echo -e "Actual Duration: $duration_formatted\nResolution: $resolution" >> "$OUTPUT_DIR/${base_filename}_info.txt"
                        fi
                    fi
                    
                    log_info "Video generation complete: $filename"
                    return 0
                fi
            done
        fi
    else
        log_error "Failed to start video generation"
        echo "$generation_result" >&2
        return 1
    fi
    
    log_error "Video generation failed"
    return 1
}

# Help command
case "${1:-help}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 <type> <prompt> [duration] [model]"
        echo ""
        echo "Arguments:"
        echo "  type        Video generation type (required)"
        echo "  prompt      Description or transformation prompt (required)"
        echo "  duration    Video length in seconds (default: 5, max: 10)"
        echo "  model       Model to use: runway (default: runway)"
        echo ""
        echo "Video Types:"
        echo "  text-to-video      - Generate video from text description"
        echo "  image-to-video     - Animate an existing image with motion prompt"
        echo "  video-to-video     - Transform existing video with new style/prompt"
        echo ""
        echo "Examples:"
        echo "  $0 text-to-video 'A professional presenter speaking to camera' 10"
        echo "  $0 image-to-video 'smooth product rotation showcasing all angles' 5"
        echo "  $0 text-to-video 'Ocean waves crashing on a beach at sunset' 8"
        echo ""
        echo "Note: Requires RUNWAYML_API_SECRET in environment or .env file"
        echo "      image-to-video requires publicly accessible image URLs"
        ;;
    *)
        main
        ;;
esac