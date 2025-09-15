#!/bin/bash
# lib/batman.sh - Batman theme utilities and Master Wayne persona

source "${CLAUDE_HOME:-$HOME/.claude}/lib/utils.sh"

# Batman ASCII art
show_batman_logo() {
    cat << 'EOF'
       _,    _   _    ,_
  .o888P     Y8o8Y     Y888o.
 d88888      88888      88888b
d888888b_  _d88888b_  _d888888b
8888888888888888888888888888888
8888888888888888888888888888888
YJGS8P"Y888P"Y888P"Y888P"Y8888P
 Y888   '8'   Y8P   '8'   888Y
  '8o          V          o8'
    `                     `
    
    CLAUDE AGNETIC SYSTEM v3.0
    The Dark Knight of Development
EOF
}

# Batman quotes and responses
batman_quotes() {
    local quotes=(
        "I am vengeance, I am the night, I am Batman!"
        "It's not who I am underneath, but what I do that defines me."
        "Sometimes it's only madness that makes us what we are."
        "A hero can be anyone, even someone doing something as simple as putting a coat around a young boy's shoulders."
        "The night is darkest just before the dawn."
        "Why do we fall? So we can learn to pick ourselves up."
        "I won't kill you, but I don't have to save you."
        "I have one power: I never give up."
        "The training is nothing! The will is everything!"
        "It's not about money, it's about sending a message."
    )
    
    echo "${quotes[$((RANDOM % ${#quotes[@]}))]}"
}

# Master Wayne professional responses
master_wayne_responses() {
    local context="$1"
    
    case "$context" in
        "greeting")
            echo "Good evening, Master Wayne. How may Wayne Enterprises assist you tonight?"
            ;;
        "working")
            echo "Analyzing the situation from the Batcave, Master Wayne..."
            ;;
        "success")
            echo "Excellent work, Master Wayne. Gotham's codebase is secure."
            ;;
        "error")
            echo "Master Wayne, we've encountered a situation that requires your attention."
            ;;
        "thinking")
            echo "Processing through Wayne Tech's advanced analysis systems..."
            ;;
        "implementing")
            echo "Deploying Wayne Enterprise's finest development protocols..."
            ;;
        "testing")
            echo "Running comprehensive security protocols, Master Wayne..."
            ;;
        "completing")
            echo "Mission accomplished with Wayne Enterprise precision."
            ;;
        *)
            echo "At your service, Master Wayne."
            ;;
    esac
}

# Batman-themed progress indicators
batman_progress() {
    local stage="$1"
    local current="$2"
    local total="$3"
    
    local progress_chars=("🦇" "🌙" "⚡" "🌟" "🔥")
    local char_index=$((current % ${#progress_chars[@]}))
    local char="${progress_chars[$char_index]}"
    
    local percentage=$((current * 100 / total))
    local bar_length=20
    local filled_length=$((percentage * bar_length / 100))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    echo -e "${YELLOW}$char${NC} $stage: ${YELLOW}[$bar]${NC} $percentage% (${current}/${total})"
}

# Wayne Tech system status
wayne_tech_status() {
    local system="$1"
    local status="$2"
    
    case "$status" in
        "online")
            echo -e "${YELLOW}🟢${NC} Wayne Tech $system: ${YELLOW}ONLINE${NC}"
            ;;
        "offline")
            echo -e "${YELLOW}🔴${NC} Wayne Tech $system: ${GRAY}OFFLINE${NC}"
            ;;
        "maintenance")
            echo -e "${YELLOW}🟡${NC} Wayne Tech $system: ${YELLOW}MAINTENANCE${NC}"
            ;;
        "initializing")
            echo -e "${YELLOW}🔵${NC} Wayne Tech $system: ${GRAY}INITIALIZING${NC}"
            ;;
        *)
            echo -e "${YELLOW}🟡${NC} Wayne Tech $system: ${GRAY}UNKNOWN${NC}"
            ;;
    esac
}

# Batcave system announcements
batcave_announce() {
    local message="$1"
    local priority="${2:-normal}"
    
    case "$priority" in
        "urgent")
            echo -e "${YELLOW}🚨 BATCAVE URGENT:${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️ BATCAVE WARNING:${NC} $message"
            ;;
        "info")
            echo -e "${YELLOW}ℹ️ BATCAVE INFO:${NC} $message"
            ;;
        *)
            echo -e "${YELLOW}🦇 BATCAVE:${NC} $message"
            ;;
    esac
}

# Alfred-style service messages
alfred_service() {
    local service="$1"
    local action="$2"
    
    case "$action" in
        "start")
            echo -e "${GRAY}🎩 Alfred: Initializing $service for Master Wayne...${NC}"
            ;;
        "stop")
            echo -e "${GRAY}🎩 Alfred: Shutting down $service, Master Wayne.${NC}"
            ;;
        "ready")
            echo -e "${GRAY}🎩 Alfred: $service is ready for your use, Master Wayne.${NC}"
            ;;
        "error")
            echo -e "${GRAY}🎩 Alfred: I'm afraid there's been an issue with $service, Master Wayne.${NC}"
            ;;
        *)
            echo -e "${GRAY}🎩 Alfred: $service $action, Master Wayne.${NC}"
            ;;
    esac
}

# Batman-themed loading animation
batman_loading() {
    local message="$1"
    local duration="${2:-3}"
    
    local frames=("🦇" "🌙" "⚡" "🌟" "🔥" "🦇")
    local frame_count=${#frames[@]}
    
    echo -n -e "${GRAY}$message "
    
    for ((i=0; i<duration*2; i++)); do
        local frame_index=$((i % frame_count))
        echo -n -e "${YELLOW}${frames[$frame_index]}${NC}"
        sleep 0.5
        echo -n -e "\b"
    done
    
    echo -e "${YELLOW}✓${NC}"
}

# Gotham City time (with timezone humor)
gotham_time() {
    local current_time=$(date '+%H:%M:%S')
    local time_of_day=""
    
    local hour=$(date '+%H')
    if [[ $hour -ge 6 && $hour -lt 12 ]]; then
        time_of_day="Morning in Gotham"
    elif [[ $hour -ge 12 && $hour -lt 18 ]]; then
        time_of_day="Afternoon in Gotham"
    elif [[ $hour -ge 18 && $hour -lt 22 ]]; then
        time_of_day="Evening in Gotham"
    else
        time_of_day="Night in Gotham (Batman time)"
    fi
    
    echo -e "${GRAY}🌆 $time_of_day: ${YELLOW}$current_time${NC}"
}

# Wayne Enterprise project classification
classify_project() {
    local project_type="$1"
    local classification=""
    
    case "$project_type" in
        *"react"*|*"vue"*|*"angular"*)
            classification="Wayne Tech Frontend Division"
            ;;
        *"node"*|*"express"*|*"api"*)
            classification="Wayne Enterprises Backend Systems"
            ;;
        *"python"*|*"django"*|*"flask"*)
            classification="Wayne Research & Development"
            ;;
        *"docker"*|*"kubernetes"*)
            classification="Wayne Infrastructure Command"
            ;;
        *"security"*|*"auth"*)
            classification="Wayne Security Division"
            ;;
        *"data"*|*"analytics"*)
            classification="Wayne Intelligence Bureau"
            ;;
        *)
            classification="Wayne Enterprises General Division"
            ;;
    esac
    
    echo "$classification"
}

# Batman-themed command completion
batman_completion() {
    local command="$1"
    local success="$2"
    
    if [[ "$success" == "true" ]]; then
        case "$command" in
            "implement")
                echo -e "${YELLOW}🦇${NC} Implementation complete. Gotham is safer tonight."
                ;;
            "test")
                echo -e "${YELLOW}🦇${NC} All systems tested. The Batcave is secure."
                ;;
            "deploy")
                echo -e "${YELLOW}🦇${NC} Deployment successful. Wayne Tech is online."
                ;;
            "review")
                echo -e "${YELLOW}🦇${NC} Code review complete. Quality worthy of Wayne standards."
                ;;
            *)
                echo -e "${YELLOW}🦇${NC} Mission accomplished, Master Wayne."
                ;;
        esac
    else
        echo -e "${YELLOW}🦇${NC} Master Wayne, we need to regroup and try again."
    fi
}

# Generate Batman-themed commit messages
batman_commit_message() {
    local change_type="$1"
    local description="$2"
    
    local prefixes=(
        "🦇 Batman:"
        "🌙 Dark Knight:"
        "⚡ Wayne Tech:"
        "🏢 Wayne Enterprises:"
        "🎩 Alfred:"
        "🦇 Batcave:"
    )
    
    local prefix="${prefixes[$((RANDOM % ${#prefixes[@]}))]}"
    
    case "$change_type" in
        "feat")
            echo "$prefix Deploy new $description to protect Gotham"
            ;;
        "fix")
            echo "$prefix Resolve $description threat in the system"
            ;;
        "refactor")
            echo "$prefix Upgrade $description with Wayne Tech standards"
            ;;
        "test")
            echo "$prefix Strengthen $description security protocols"
            ;;
        "docs")
            echo "$prefix Document $description for the Batcave archives"
            ;;
        *)
            echo "$prefix $description - Another night protecting Gotham's code"
            ;;
    esac
}

# Batman-themed error messages
batman_error_message() {
    local error_type="$1"
    local context="$2"
    
    case "$error_type" in
        "syntax")
            echo -e "${YELLOW}🦇${NC} Master Wayne, there's a syntax error in the code. Even Batman makes typos."
            ;;
        "network")
            echo -e "${YELLOW}🦇${NC} The Batcave's network connection is down. Alfred is investigating."
            ;;
        "permission")
            echo -e "${YELLOW}🦇${NC} Access denied, Master Wayne. Not even Batman can bypass proper permissions."
            ;;
        "file_not_found")
            echo -e "${YELLOW}🦇${NC} File not found in the Batcave archives. It may have been moved to the Fortress of Solitude."
            ;;
        *)
            echo -e "${YELLOW}🦇${NC} Master Wayne, we've encountered an unexpected situation in $context."
            ;;
    esac
}

# Export Batman functions
export -f show_batman_logo batman_quotes master_wayne_responses
export -f batman_progress wayne_tech_status batcave_announce alfred_service
export -f batman_loading gotham_time classify_project batman_completion
export -f batman_commit_message batman_error_message