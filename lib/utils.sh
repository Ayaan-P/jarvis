#!/bin/bash
# lib/utils.sh - Core utilities for Claude Agnetic System

# Configuration
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDE_VERSION="3.0.0"

# Colors for Batman theme
export BLACK='\033[0;30m'
export YELLOW='\033[1;33m'
export GRAY='\033[0;37m'
export DARK_GRAY='\033[1;30m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GRAY}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${YELLOW}[ERROR]${NC} $1" >&2
}

log_batman() {
    echo -e "${YELLOW}🦇${NC} $1" >&2
}

# Batman-themed messages
batman_greet() {
    echo -e "${YELLOW}🦇 Ready to serve, Master Wayne.${NC}"
}

batman_working() {
    echo -e "${GRAY}🦇 Engaging Wayne Tech systems...${NC}"
}

batman_complete() {
    echo -e "${YELLOW}🦇 Mission accomplished, Master Wayne.${NC}"
}

batman_error() {
    echo -e "${YELLOW}🦇 The Batcave systems encountered an issue, Master Wayne.${NC}"
}

# File operations
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            return 1
        }
    fi
}

safe_write() {
    local file="$1"
    local content="$2"
    local backup_suffix="${3:-.backup}"
    
    ensure_directory "$(dirname "$file")"
    
    if [[ -f "$file" ]]; then
        cp "$file" "${file}${backup_suffix}"
    fi
    
    echo "$content" > "$file"
}

# JSON operations
json_get() {
    local file="$1"
    local key="$2"
    
    if [[ -f "$file" ]]; then
        jq -r ".$key // empty" "$file" 2>/dev/null
    fi
}

json_set() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    ensure_directory "$(dirname "$file")"
    
    if [[ -f "$file" ]]; then
        jq ".$key = \"$value\"" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    else
        echo "{\"$key\": \"$value\"}" > "$file"
    fi
}

# Process management
is_running() {
    local process="$1"
    pgrep -f "$process" >/dev/null 2>&1
}

kill_process() {
    local process="$1"
    local signal="${2:-TERM}"
    
    if is_running "$process"; then
        pkill -"$signal" -f "$process"
        return $?
    fi
    return 1
}

# String utilities
trim() {
    local str="$1"
    echo "$str" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Array utilities
contains() {
    local element="$1"
    shift
    local array=("$@")
    
    for item in "${array[@]}"; do
        if [[ "$item" == "$element" ]]; then
            return 0
        fi
    done
    return 1
}

join_array() {
    local delimiter="$1"
    shift
    local array=("$@")
    
    local result=""
    for item in "${array[@]}"; do
        if [[ -n "$result" ]]; then
            result="$result$delimiter$item"
        else
            result="$item"
        fi
    done
    echo "$result"
}

# Time utilities
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

epoch_time() {
    date +%s
}

# Git utilities
is_git_repo() {
    git rev-parse --git-dir >/dev/null 2>&1
}

git_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null
}

git_is_clean() {
    [[ -z "$(git status --porcelain 2>/dev/null)" ]]
}

# Environment detection
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

detect_shell() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        echo "zsh"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

# Dependency checks
check_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

check_dependencies() {
    local deps=("$@")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! check_command "$dep"; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Cache utilities
get_cache_dir() {
    echo "$CLAUDE_HOME/cache"
}

cache_get() {
    local key="$1"
    local cache_file="$(get_cache_dir)/$key"
    
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    fi
}

cache_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-3600}" # 1 hour default
    
    local cache_dir="$(get_cache_dir)"
    ensure_directory "$cache_dir"
    
    local cache_file="$cache_dir/$key"
    local meta_file="$cache_dir/$key.meta"
    
    echo "$value" > "$cache_file"
    echo "{\"created\": $(epoch_time), \"ttl\": $ttl}" > "$meta_file"
}

cache_is_valid() {
    local key="$1"
    local cache_dir="$(get_cache_dir)"
    local meta_file="$cache_dir/$key.meta"
    
    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi
    
    local created=$(json_get "$meta_file" "created")
    local ttl=$(json_get "$meta_file" "ttl")
    local now=$(epoch_time)
    
    if [[ $((now - created)) -lt $ttl ]]; then
        return 0
    else
        return 1
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    if [[ $exit_code -ne 0 ]]; then
        batman_error
        log_error "Command failed at line $line_number: $command (exit code: $exit_code)"
        exit $exit_code
    fi
}

# Set up error handling
set -eE
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Export functions for use in other scripts
export -f log_info log_warn log_error log_batman
export -f batman_greet batman_working batman_complete batman_error
export -f ensure_directory safe_write json_get json_set
export -f is_running kill_process trim to_lower to_upper
export -f contains join_array timestamp epoch_time
export -f is_git_repo git_current_branch git_is_clean
export -f detect_os detect_shell check_command check_dependencies
export -f cache_get cache_set cache_is_valid handle_error