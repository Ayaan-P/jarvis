#!/bin/bash
# Veo 3 video generation automation for content-creator agent
# Usage: ./veo3-video-generator.sh "text-to-video" "prompt" "resolution" [aspect_ratio]
# Usage: ./veo3-video-generator.sh "image-to-video" "prompt" "720p" "16:9"

source "${BASH_SOURCE%/*}/utils.sh"

VIDEO_TYPE="$1"
PROMPT="$2"
RESOLUTION="${3:-720p}"
ASPECT_RATIO="${4:-16:9}"

if [[ -z "$VIDEO_TYPE" || -z "$PROMPT" ]]; then
    echo "Usage: $0 <type> <prompt> [resolution] [aspect_ratio]"
    echo ""
    echo "Video Types:"
    echo "  text-to-video      - Generate video from text description"
    echo "  image-to-video     - Animate an existing image"
    echo ""
    echo "Examples:"
    echo "  $0 text-to-video 'A cinematic shot of a majestic lion in the savannah' 1080p 16:9"
    echo "  $0 image-to-video 'Bunny runs away happily' 720p 16:9"
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

log_info "Generating video with Veo 3: Type=$VIDEO_TYPE, Prompt='$PROMPT', Resolution=$RESOLUTION, Aspect Ratio=$ASPECT_RATIO"

# Function to generate video using Google Gemini API with Veo 3
generate_with_veo3() {
    local type="$1"
    local prompt="$2"
    local resolution="$3"
    local aspect_ratio="$4"
    local image_path="$5"
    
    log_info "Using Google Gemini API with Veo 3 model"
    
    # Validate resolution and aspect ratio
    case "$resolution" in
        "720p")
            if [[ "$aspect_ratio" != "16:9" && "$aspect_ratio" != "9:16" ]]; then
                log_error "For 720p, only 16:9 and 9:16 aspect ratios are supported"
                return 1
            fi
            ;;
        "1080p")
            if [[ "$aspect_ratio" != "16:9" ]]; then
                log_error "For 1080p, only 16:9 aspect ratio is supported"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported resolution: $resolution. Use 720p or 1080p"
            return 1
            ;;
    esac
    
    # Prepare the API request
    local api_url="https://generativelanguage.googleapis.com/v1beta/models/veo-3.0-generate-001:predictLongRunning"
    
    # Build the request payload
    local request_payload=""
    if [[ "$type" == "text-to-video" ]]; then
        request_payload=$(cat << EOF
{
    "instances": [{
        "prompt": "$prompt"
    }],
    "parameters": {
        "aspectRatio": "$aspect_ratio",
        "personGeneration": "allow_all"
    }
}
EOF
)
    elif [[ "$type" == "image-to-video" && -n "$image_path" ]]; then
        # For image-to-video, we need to encode the image
        local image_base64=$(base64 -w 0 "$image_path")
        local mime_type="image/png"
        [[ "$image_path" == *.jpg ]] && mime_type="image/jpeg"
        [[ "$image_path" == *.jpeg ]] && mime_type="image/jpeg"
        
        request_payload=$(cat << EOF
{
    "instances": [{
        "prompt": "$prompt",
        "image": {
            "bytesBase64Encoded": "$image_base64"
        }
    }],
    "parameters": {
        "aspectRatio": "$aspect_ratio",
        "personGeneration": "allow_adult"
    }
}
EOF
)
    else
        log_error "Invalid video type or missing image for image-to-video"
        return 1
    fi
    
    log_info "Sending request to Veo 3 API..."
    
    # Make the API request
    local response=$(curl -s -X POST \
        -H "x-goog-api-key: $GOOGLE_GENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$request_payload" \
        "$api_url")
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'name' in data:
        print(f'OPERATION_NAME={data[\"name\"]}')
        print('STATUS=processing')
    elif 'error' in data:
        error_msg = data['error'].get('message', 'Unknown error')
        print(f'ERROR={error_msg}', file=sys.stderr)
    else:
        print('ERROR=Invalid response format', file=sys.stderr)
        print(f'RESPONSE={json.dumps(data)}', file=sys.stderr)
except Exception as e:
    print(f'ERROR=JSON parsing failed: {e}', file=sys.stderr)
    print(f'RAW_RESPONSE: {sys.stdin.read()}', file=sys.stderr)
"
    else
        log_error "Failed to submit video generation request"
        return 1
    fi
}

# Function to poll video generation status
poll_video_status() {
    local operation_name="$1"
    local max_attempts=60  # 10 minutes with 10-second intervals
    local attempt=0
    
    log_info "Polling video generation status: $operation_name"
    
    while [[ $attempt -lt $max_attempts ]]; do
        local response=$(curl -s -H "x-goog-api-key: $GOOGLE_GENAI_API_KEY" \
            "https://generativelanguage.googleapis.com/v1beta/$operation_name")
        
        local status=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'done' in data and data['done']:
        if 'response' in data and 'generateVideoResponse' in data['response']:
            video_response = data['response']['generateVideoResponse']
            if 'generatedSamples' in video_response:
                samples = video_response['generatedSamples']
                for i, sample in enumerate(samples):
                    if 'video' in sample and 'uri' in sample['video']:
                        print(f'VIDEO_URI_{i}={sample[\"video\"][\"uri\"]}')
                print('STATUS=completed')
            else:
                print('STATUS=completed_no_video')
        elif 'error' in data:
            error_msg = data.get('error', {}).get('message', 'Unknown error')
            print('STATUS=failed')
            print(f'ERROR={error_msg}', file=sys.stderr)
        else:
            print('STATUS=completed_no_video')
    else:
        print('STATUS=processing')
except Exception as e:
    print('STATUS=error')
    print(f'ERROR=Failed to parse response: {e}', file=sys.stderr)
")
        
        local current_status=$(echo "$status" | grep "STATUS=" | cut -d'=' -f2)
        log_info "Video generation status: $current_status (attempt $((attempt + 1))/$max_attempts)"
        
        case "$current_status" in
            "completed")
                echo "$status"
                return 0
                ;;
            "failed"|"error")
                local error=$(echo "$status" | grep "ERROR=" | cut -d'=' -f2-)
                log_error "Video generation failed: $error"
                return 1
                ;;
            "processing")
                sleep 10
                ((attempt++))
                ;;
            "completed_no_video")
                log_error "Video generation completed but no video was produced"
                return 1
                ;;
            *)
                log_error "Unknown video generation status: $current_status"
                return 1
                ;;
        esac
    done
    
    log_error "Video generation timed out after $max_attempts attempts"
    return 1
}

# Function to download video from Gemini API
download_video() {
    local video_uri="$1"
    local filename="$2"
    
    log_info "Downloading video from: $video_uri"
    
    # Download using API key in header
    curl -L -s -o "$filename" -H "x-goog-api-key: $GOOGLE_GENAI_API_KEY" "$video_uri"
    if [[ $? -eq 0 && -f "$filename" ]]; then
        local file_size=$(stat -f%z "$filename" 2>/dev/null || stat -c%s "$filename" 2>/dev/null)
        if [[ "$file_size" -gt 50000 ]]; then  # Videos should be larger than 50KB
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

# Main execution
main() {
    if [[ -z "$GOOGLE_GENAI_API_KEY" ]]; then
        log_error "GOOGLE_GENAI_API_KEY not found in environment"
        log_info "Please add your Google Gemini API key to your .env file"
        return 1
    fi
    
    # Generate timestamp for unique filenames
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local base_filename="veo3_video_${timestamp}"
    
    # Handle image-to-video type
    local source_image=""
    if [[ "$VIDEO_TYPE" == "image-to-video" ]]; then
        source_image=$(find_source_image "$PROMPT")
        if [[ $? -ne 0 || -z "$source_image" ]]; then
            log_error "No source image found for image-to-video generation"
            return 1
        fi
        log_info "Using source image: $source_image"
    fi
    
    # Generate video
    local generation_result
    if [[ "$VIDEO_TYPE" == "image-to-video" ]]; then
        generation_result=$(generate_with_veo3 "$VIDEO_TYPE" "$PROMPT" "$RESOLUTION" "$ASPECT_RATIO" "$source_image")
    else
        generation_result=$(generate_with_veo3 "$VIDEO_TYPE" "$PROMPT" "$RESOLUTION" "$ASPECT_RATIO")
    fi
    
    # Process the result
    if echo "$generation_result" | grep -q "OPERATION_NAME="; then
        local operation_name=$(echo "$generation_result" | grep "OPERATION_NAME=" | cut -d'=' -f2-)
        
        if poll_result=$(poll_video_status "$operation_name"); then
            local video_uris=($(echo "$poll_result" | grep "VIDEO_URI_" | cut -d'=' -f2-))
            
            for i in "${!video_uris[@]}"; do
                local filename="$OUTPUT_DIR/${base_filename}_$i.mp4"
                if download_video "${video_uris[$i]}" "$filename"; then
                    echo "✅ Generated video saved: $filename"
                    
                    # Store generation info
                    cat > "$OUTPUT_DIR/${base_filename}_info.txt" << EOF
Generated: $(date)
Type: $VIDEO_TYPE
Prompt: $PROMPT
Resolution: $RESOLUTION
Aspect Ratio: $ASPECT_RATIO
Operation: $operation_name
Original URI: ${video_uris[$i]}
Local File: $filename
Model: Veo 3 (Google Gemini API)
EOF
                    
                    if [[ -n "$source_image" ]]; then
                        echo "Source Image: $source_image" >> "$OUTPUT_DIR/${base_filename}_info.txt"
                    fi
                    
                    # Try to get video info if ffprobe is available
                    if command -v ffprobe >/dev/null 2>&1; then
                        local duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$filename" 2>/dev/null)
                        local resolution_info=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$filename" 2>/dev/null)
                        if [[ -n "$duration" && -n "$resolution_info" ]]; then
                            local duration_formatted=$(python3 -c "print(f'{float('$duration'):.1f}s')" 2>/dev/null || echo "${duration}s")
                            echo "Video info: ${resolution_info}, ${duration_formatted}"
                            echo -e "Actual Duration: $duration_formatted\\nActual Resolution: $resolution_info" >> "$OUTPUT_DIR/${base_filename}_info.txt"
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
        echo "Usage: $0 <type> <prompt> [resolution] [aspect_ratio]"
        echo ""
        echo "Arguments:"
        echo "  type           Video generation type (required)"
        echo "  prompt         Description or animation prompt (required)"
        echo "  resolution     Video resolution: 720p, 1080p (default: 720p)"
        echo "  aspect_ratio   Video aspect ratio: 16:9, 9:16 (default: 16:9)"
        echo ""
        echo "Video Types:"
        echo "  text-to-video      - Generate video from text description"
        echo "  image-to-video     - Animate an existing image with motion prompt"
        echo ""
        echo "Supported Resolutions & Aspect Ratios:"
        echo "  720p: 16:9, 9:16"
        echo "  1080p: 16:9 only"
        echo ""
        echo "Examples:"
        echo "  $0 text-to-video 'A cinematic shot of a majestic lion in the savannah' 1080p 16:9"
        echo "  $0 text-to-video 'Close up shot of melting icicles with cool blue tones' 720p 16:9"
        echo "  $0 image-to-video 'Bunny runs away happily through the garden' 720p 16:9"
        echo ""
        echo "Features:"
        echo "  • 8-second 720p or 1080p videos with native audio"
        echo "  • Cinematic realism and creative animation styles"
        echo "  • Dialogue and sound effects generation"
        echo "  • Image-to-video animation capabilities"
        echo ""
        echo "Note: Requires GOOGLE_GENAI_API_KEY in environment or .env file"
        echo "      Generated videos are watermarked with SynthID"
        echo "      Videos are retained on server for 2 days only"
        ;;
    *)
        main
        ;;
esac