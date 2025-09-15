#!/bin/bash
# Music generation automation for content-creator agent
# Usage: ./music-generator.sh "genre" "mood" "duration" [tempo]
# Usage: ./music-generator.sh "ambient" "calm" "60" "slow"

source "${BASH_SOURCE%/*}/utils.sh"

GENRE="$1"
MOOD="${2:-neutral}"
DURATION="${3:-30}"
TEMPO="${4:-medium}"

if [[ -z "$GENRE" ]]; then
    echo "Usage: $0 <genre> [mood] [duration] [tempo]"
    echo ""
    echo "Genres:"
    echo "  ambient         - Atmospheric background music"
    echo "  cinematic       - Dramatic film-style music"
    echo "  corporate       - Professional business background"
    echo "  electronic      - Electronic/EDM style"
    echo "  acoustic        - Natural acoustic instruments"
    echo "  hip-hop         - Hip-hop and rap backing tracks"
    echo "  jazz            - Jazz and smooth jazz"
    echo "  classical       - Orchestral and classical"
    echo ""
    echo "Moods:"
    echo "  calm, energetic, dramatic, happy, sad, mysterious, upbeat, relaxed"
    echo ""
    echo "Examples:"
    echo "  $0 ambient calm 60 slow"
    echo "  $0 corporate upbeat 30 medium"
    echo "  $0 cinematic dramatic 120 medium"
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
OUTPUT_DIR="/tmp/generated_music"
mkdir -p "$OUTPUT_DIR"

log_info "Generating music: Genre=$GENRE, Mood=$MOOD, Duration=${DURATION}s, Tempo=$TEMPO"

# Function to generate music using Mubert API
generate_with_mubert() {
    local genre="$1"
    local mood="$2"
    local duration="$3"
    local tempo="$4"
    
    log_info "Using Mubert API for music generation"
    
    # Convert duration to seconds (API expects integer)
    local duration_int=$(echo "$duration" | cut -d'.' -f1)
    if [[ $duration_int -lt 15 ]]; then
        duration_int=15  # Minimum 15 seconds
        log_info "Duration adjusted to minimum: ${duration_int}s"
    elif [[ $duration_int -gt 300 ]]; then
        duration_int=300  # Maximum 5 minutes for free tier
        log_info "Duration adjusted to maximum: ${duration_int}s"
    fi
    
    # Map genres to Mubert tags
    local mubert_tags=""
    case "$genre" in
        "ambient")
            mubert_tags="ambient,atmospheric,chill"
            ;;
        "cinematic")
            mubert_tags="cinematic,dramatic,orchestral"
            ;;
        "corporate")
            mubert_tags="corporate,business,professional"
            ;;
        "electronic")
            mubert_tags="electronic,edm,synth"
            ;;
        "acoustic")
            mubert_tags="acoustic,guitar,organic"
            ;;
        "hip-hop")
            mubert_tags="hip-hop,rap,urban"
            ;;
        "jazz")
            mubert_tags="jazz,smooth,saxophone"
            ;;
        "classical")
            mubert_tags="classical,orchestral,piano"
            ;;
        *)
            mubert_tags="$genre"
            ;;
    esac
    
    # Add mood to tags
    mubert_tags="$mubert_tags,$mood"
    
    # Add tempo to tags
    case "$tempo" in
        "slow")
            mubert_tags="$mubert_tags,slow,relaxed"
            ;;
        "medium")
            mubert_tags="$mubert_tags,medium,balanced"
            ;;
        "fast")
            mubert_tags="$mubert_tags,fast,energetic"
            ;;
    esac
    
    log_info "Mubert tags: $mubert_tags"
    
    # Generate music using Mubert API
    local response=$(curl -s -X POST \
        "https://api-b2b.mubert.com/v2/GenTrackWCover" \
        -H "Content-Type: application/json" \
        -d "{
            \"method\": \"GenerateTrackByTags\",
            \"params\": {
                \"pat\": \"$MUBERT_API_KEY\",
                \"tags\": \"$mubert_tags\",
                \"duration\": $duration_int,
                \"format\": \"mp3\",
                \"bitrate\": 320
            }
        }")
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | python3 -c "
import sys, json, time
try:
    data = json.load(sys.stdin)
    if data.get('status') == 1 and 'data' in data:
        track_id = data['data'].get('track_id')
        if track_id:
            print(f'TRACK_ID={track_id}')
        else:
            print('ERROR=No track ID returned', file=sys.stderr)
    else:
        error_msg = data.get('error', 'Unknown error')
        print(f'ERROR={error_msg}', file=sys.stderr)
        print(f'RESPONSE={json.dumps(data)}', file=sys.stderr)
except Exception as e:
    print(f'ERROR=JSON parsing failed: {e}', file=sys.stderr)
"
    else
        log_error "Failed to generate music with Mubert API"
        return 1
    fi
}

# Function to poll music generation status and download
poll_music_status() {
    local track_id="$1"
    local max_attempts=30  # 2.5 minutes with 5-second intervals
    local attempt=0
    
    log_info "Polling music generation status: $track_id"
    
    while [[ $attempt -lt $max_attempts ]]; do
        local response=$(curl -s -X POST \
            "https://api-b2b.mubert.com/v2/GenTrackWCover" \
            -H "Content-Type: application/json" \
            -d "{
                \"method\": \"GetTrackStatus\",
                \"params\": {
                    \"pat\": \"$MUBERT_API_KEY\",
                    \"track_id\": \"$track_id\"
                }
            }")
        
        local status_info=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('status') == 1 and 'data' in data:
        track_status = data['data'].get('status')
        download_url = data['data'].get('download_link', '')
        print(f'STATUS={track_status}')
        if download_url:
            print(f'DOWNLOAD_URL={download_url}')
    else:
        print('STATUS=error')
except:
    print('STATUS=error')
")
        
        local track_status=$(echo "$status_info" | grep "STATUS=" | cut -d'=' -f2)
        log_info "Track generation status: $track_status (attempt $((attempt + 1))/$max_attempts)"
        
        case "$track_status" in
            "ready")
                local download_url=$(echo "$status_info" | grep "DOWNLOAD_URL=" | cut -d'=' -f2-)
                if [[ -n "$download_url" ]]; then
                    echo "MUSIC_URL=$download_url"
                    return 0
                else
                    log_error "Track ready but no download URL provided"
                    return 1
                fi
                ;;
            "processing")
                sleep 5
                ((attempt++))
                ;;
            "error"|"failed")
                log_error "Music generation failed with status: $track_status"
                return 1
                ;;
            *)
                log_error "Unknown music generation status: $track_status"
                return 1
                ;;
        esac
    done
    
    log_error "Music generation timed out after $max_attempts attempts"
    return 1
}

# Function to download music from URL
download_music() {
    local url="$1"
    local filename="$2"
    
    log_info "Downloading music from: $url"
    
    curl -L -s -o "$filename" "$url"
    if [[ $? -eq 0 && -f "$filename" ]]; then
        local file_size=$(stat -f%z "$filename" 2>/dev/null || stat -c%s "$filename" 2>/dev/null)
        if [[ "$file_size" -gt 50000 ]]; then  # Music should be larger than 50KB
            log_info "Music downloaded successfully: $filename (${file_size} bytes)"
            return 0
        else
            log_error "Downloaded music file is too small, might be corrupted"
            return 1
        fi
    else
        log_error "Failed to download music"
        return 1
    fi
}

# Main execution
main() {
    if [[ -z "$MUBERT_API_KEY" ]]; then
        log_error "MUBERT_API_KEY not found in environment"
        log_info "Please add your Mubert API key to your .env file"
        return 1
    fi
    
    # Generate timestamp for unique filenames
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local base_filename="music_${timestamp}"
    
    # Generate music
    local generation_result=$(generate_with_mubert "$GENRE" "$MOOD" "$DURATION" "$TEMPO")
    
    # Process the result
    if echo "$generation_result" | grep -q "TRACK_ID="; then
        local track_id=$(echo "$generation_result" | grep "TRACK_ID=" | cut -d'=' -f2)
        
        if poll_result=$(poll_music_status "$track_id"); then
            local music_url=$(echo "$poll_result" | grep "MUSIC_URL=" | cut -d'=' -f2-)
            
            local filename="$OUTPUT_DIR/${base_filename}.mp3"
            if download_music "$music_url" "$filename"; then
                echo "✅ Generated music saved: $filename"
                
                # Store generation info
                cat > "$OUTPUT_DIR/${base_filename}_info.txt" << EOF
Generated: $(date)
Genre: $GENRE
Mood: $MOOD
Duration: ${DURATION}s
Tempo: $TEMPO
Track ID: $track_id
Original URL: $music_url
Local File: $filename
EOF
                
                # Try to get audio info if ffprobe is available
                if command -v ffprobe >/dev/null 2>&1; then
                    local duration_actual=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$filename" 2>/dev/null)
                    local bitrate=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$filename" 2>/dev/null)
                    if [[ -n "$duration_actual" ]]; then
                        local duration_formatted=$(python3 -c "print(f'{float('$duration_actual'):.1f}s')" 2>/dev/null || echo "${duration_actual}s")
                        echo "Music info: ${duration_formatted}"
                        echo "Actual Duration: $duration_formatted" >> "$OUTPUT_DIR/${base_filename}_info.txt"
                        if [[ -n "$bitrate" ]]; then
                            local bitrate_kb=$(echo "$bitrate" | python3 -c "import sys; print(f'{int(sys.stdin.read().strip())//1000}kbps')" 2>/dev/null || echo "${bitrate}bps")
                            echo "Bitrate: $bitrate_kb"
                            echo "Bitrate: $bitrate_kb" >> "$OUTPUT_DIR/${base_filename}_info.txt"
                        fi
                    fi
                fi
                
                log_info "Music generation complete: $filename"
                return 0
            fi
        fi
    else
        log_error "Failed to start music generation"
        echo "$generation_result" >&2
        return 1
    fi
    
    log_error "Music generation failed"
    return 1
}

# Help command
case "${1:-help}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 <genre> [mood] [duration] [tempo]"
        echo ""
        echo "Arguments:"
        echo "  genre      Music genre (required)"
        echo "  mood       Music mood (default: neutral)"
        echo "  duration   Track length in seconds (default: 30, min: 15, max: 300)"
        echo "  tempo      Music tempo: slow, medium, fast (default: medium)"
        echo ""
        echo "Genres:"
        echo "  ambient         - Atmospheric background music"
        echo "  cinematic       - Dramatic film-style music"
        echo "  corporate       - Professional business background"
        echo "  electronic      - Electronic/EDM style"
        echo "  acoustic        - Natural acoustic instruments"
        echo "  hip-hop         - Hip-hop and rap backing tracks"
        echo "  jazz            - Jazz and smooth jazz"
        echo "  classical       - Orchestral and classical"
        echo ""
        echo "Moods:"
        echo "  calm, energetic, dramatic, happy, sad, mysterious, upbeat, relaxed"
        echo ""
        echo "Examples:"
        echo "  $0 ambient calm 60 slow"
        echo "  $0 corporate upbeat 30 medium"
        echo "  $0 cinematic dramatic 120 medium"
        echo "  $0 electronic energetic 45 fast"
        echo ""
        echo "Note: Requires MUBERT_API_KEY in environment or .env file"
        ;;
    *)
        main
        ;;
esac