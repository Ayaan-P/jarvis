#!/bin/bash
# Audio generation automation for content-creator agent  
# Usage: ./audio-generator.sh "text" "voice_style" "format"
# Usage: ./audio-generator.sh "Welcome to our presentation" "professional_male" "mp3"

source "${BASH_SOURCE%/*}/utils.sh"

TEXT="$1"
VOICE_STYLE="${2:-professional_female}"
FORMAT="${3:-mp3}"

if [[ -z "$TEXT" ]]; then
    echo "Usage: $0 <text> [voice_style] [format]"
    echo ""
    echo "Voice Styles:"
    echo "  professional_male    - Clear, authoritative male voice"
    echo "  professional_female  - Clear, authoritative female voice" 
    echo "  friendly_male        - Warm, conversational male voice"
    echo "  friendly_female      - Warm, conversational female voice"
    echo "  narrator_male        - Deep, storytelling male voice"
    echo "  narrator_female      - Smooth, storytelling female voice"
    echo ""
    echo "Examples:"
    echo "  $0 'Welcome to our company presentation' professional_female"
    echo "  $0 'This is a friendly introduction' friendly_male mp3"
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
OUTPUT_DIR="/tmp/generated_audio"
mkdir -p "$OUTPUT_DIR"

log_info "Generating audio: '$TEXT'"
log_info "Voice style: $VOICE_STYLE, Format: $FORMAT"

# Voice ID mapping based on ElevenLabs popular voices
get_voice_id() {
    local style="$1"
    case "$style" in
        "professional_male")
            echo "29vD33N1CtxCmqQRPOHJ" # Drew - calm, professional male
            ;;
        "professional_female")
            echo "21m00Tcm4TlvDq8ikWAM" # Rachel - calm, professional female
            ;;
        "friendly_male")
            echo "AZnzlk1XvdvUeBnXmlld" # Domi - friendly, warm male
            ;;
        "friendly_female")
            echo "EXAVITQu4vr4xnSDxMaL" # Bella - friendly, warm female  
            ;;
        "narrator_male")
            echo "2EiwWnXFnvU5JabPnv8n" # Clyde - deep, storytelling male
            ;;
        "narrator_female")
            echo "oWAxZDx7w5VEj9dCyTzz" # Grace - smooth, storytelling female
            ;;
        *)
            log_error "Unknown voice style: $style"
            echo "21m00Tcm4TlvDq8ikWAM" # Default to Rachel
            ;;
    esac
}

# Function to generate speech using ElevenLabs API
generate_speech() {
    local text="$1"
    local voice_id="$2"
    local output_file="$3"
    
    log_info "Using ElevenLabs API with voice ID: $voice_id"
    
    # Configure voice settings based on style
    local stability="0.5"
    local similarity_boost="0.8"
    local style_strength="0.4"
    
    case "$VOICE_STYLE" in
        "professional_"*)
            stability="0.7"
            similarity_boost="0.9"
            style_strength="0.2"
            ;;
        "friendly_"*)
            stability="0.4" 
            similarity_boost="0.7"
            style_strength="0.6"
            ;;
        "narrator_"*)
            stability="0.8"
            similarity_boost="0.9"
            style_strength="0.3"
            ;;
    esac
    
    log_info "Voice settings - Stability: $stability, Similarity: $similarity_boost, Style: $style_strength"
    
    # Create the audio using ElevenLabs API
    local response=$(curl -s -X POST \
        "https://api.elevenlabs.io/v1/text-to-speech/$voice_id" \
        -H "xi-api-key: $ELEVENLABS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"text\": \"$text\",
            \"model_id\": \"eleven_multilingual_v2\",
            \"voice_settings\": {
                \"stability\": $stability,
                \"similarity_boost\": $similarity_boost,
                \"style\": $style_strength,
                \"use_speaker_boost\": true
            }
        }" \
        --output "$output_file")
    
    if [[ $? -eq 0 ]]; then
        # Check if the output file was created and has content
        if [[ -f "$output_file" ]]; then
            local file_size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
            if [[ "$file_size" -gt 1000 ]]; then
                log_info "Audio generated successfully: $output_file (${file_size} bytes)"
                return 0
            else
                log_error "Generated audio file is too small, might be an error response"
                # Try to read the file as text to see if it's an error message
                if command -v file >/dev/null 2>&1; then
                    local file_type=$(file "$output_file")
                    log_error "File type: $file_type"
                fi
                if [[ "$file_size" -lt 200 ]]; then
                    log_error "Response content: $(cat "$output_file")"
                fi
                return 1
            fi
        else
            log_error "Audio file was not created"
            return 1
        fi
    else
        log_error "Failed to generate audio with ElevenLabs API"
        return 1
    fi
}

# Function to check if text is suitable for speech generation
validate_text() {
    local text="$1"
    local length=${#text}
    
    if [[ $length -lt 1 ]]; then
        log_error "Text is empty"
        return 1
    elif [[ $length -gt 5000 ]]; then
        log_error "Text is too long (${length} characters). Maximum is 5000 characters."
        return 1
    fi
    
    # Check for unsupported characters or formatting
    if echo "$text" | grep -q '[<>{}]'; then
        log_info "Warning: Text contains HTML-like tags that might affect speech generation"
    fi
    
    return 0
}

# Function to optimize text for speech
optimize_text_for_speech() {
    local text="$1"
    
    # Replace common abbreviations and symbols for better pronunciation
    text=$(echo "$text" | sed 's/&/and/g')
    text=$(echo "$text" | sed 's/@/ at /g')
    text=$(echo "$text" | sed 's/#/ number /g')
    text=$(echo "$text" | sed 's/%/ percent/g')
    text=$(echo "$text" | sed 's/\$/ dollars/g')
    
    # Add pauses for better pacing
    text=$(echo "$text" | sed 's/\. /. ... /g')
    text=$(echo "$text" | sed 's/! /! ... /g') 
    text=$(echo "$text" | sed 's/? /? ... /g')
    
    echo "$text"
}

# Main execution
main() {
    if [[ -z "$ELEVENLABS_API_KEY" ]]; then
        log_error "ELEVENLABS_API_KEY not found in environment"
        log_info "Please add your ElevenLabs API key to your .env file"
        return 1
    fi
    
    # Validate and optimize the input text
    if ! validate_text "$TEXT"; then
        return 1
    fi
    
    local optimized_text=$(optimize_text_for_speech "$TEXT")
    if [[ "$optimized_text" != "$TEXT" ]]; then
        log_info "Text optimized for speech generation"
    fi
    
    # Generate timestamp for unique filenames
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="audio_${timestamp}.${FORMAT}"
    local output_file="$OUTPUT_DIR/$filename"
    
    # Get voice ID for the specified style
    local voice_id=$(get_voice_id "$VOICE_STYLE")
    
    # Generate the speech
    if generate_speech "$optimized_text" "$voice_id" "$output_file"; then
        echo "✅ Generated audio saved: $output_file"
        
        # Store generation info
        cat > "$OUTPUT_DIR/audio_${timestamp}_info.txt" << EOF
Generated: $(date)
Text: $TEXT
Optimized Text: $optimized_text
Voice Style: $VOICE_STYLE
Voice ID: $voice_id
Format: $FORMAT
Local File: $output_file
EOF
        
        # Try to get audio duration if ffprobe is available
        if command -v ffprobe >/dev/null 2>&1; then
            local duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$output_file" 2>/dev/null)
            if [[ -n "$duration" ]]; then
                local duration_formatted=$(python3 -c "print(f'{float('$duration'):.1f}s')" 2>/dev/null || echo "${duration}s")
                echo "Audio duration: $duration_formatted"
                echo "Duration: $duration_formatted" >> "$OUTPUT_DIR/audio_${timestamp}_info.txt"
            fi
        fi
        
        log_info "Audio generation complete: $output_file"
        return 0
    else
        log_error "Failed to generate audio"
        return 1
    fi
}

# Help command
case "${1:-help}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 <text> [voice_style] [format]"
        echo ""
        echo "Arguments:"
        echo "  text         Text to convert to speech (required, max 5000 chars)"
        echo "  voice_style  Voice style preset (default: professional_female)"
        echo "  format       Output format: mp3, wav (default: mp3)"
        echo ""
        echo "Voice Styles:"
        echo "  professional_male    - Clear, authoritative male voice (Drew)"
        echo "  professional_female  - Clear, authoritative female voice (Rachel)"
        echo "  friendly_male        - Warm, conversational male voice (Domi)"
        echo "  friendly_female      - Warm, conversational female voice (Bella)"
        echo "  narrator_male        - Deep, storytelling male voice (Clyde)"
        echo "  narrator_female      - Smooth, storytelling female voice (Grace)"
        echo ""
        echo "Examples:"
        echo "  $0 'Welcome to our company presentation' professional_female"
        echo "  $0 'This is a friendly introduction to our product' friendly_male"
        echo "  $0 'Once upon a time, in a digital world far away' narrator_female"
        echo ""
        echo "Note: Requires ELEVENLABS_API_KEY in environment or .env file"
        ;;
    *)
        main
        ;;
esac