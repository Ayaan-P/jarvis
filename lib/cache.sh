#!/bin/bash
# lib/cache.sh - Intelligent caching system for Wayne Tech operations

source "${CLAUDE_HOME:-$HOME/.claude}/lib/utils.sh"

# Cache configuration
CACHE_DIR="${CLAUDE_HOME:-$HOME/.claude}/cache"
DEFAULT_TTL="${DEFAULT_TTL:-3600}  # 1 hour"
MAX_CACHE_SIZE="${MAX_CACHE_SIZE:-100}  # MB"
CACHE_VERSION="${CACHE_VERSION:-1.0}"

# Initialize cache system
init_cache() {
    ensure_directory "$CACHE_DIR"
    ensure_directory "$CACHE_DIR/mcp"
    ensure_directory "$CACHE_DIR/personas"
    ensure_directory "$CACHE_DIR/context"
    ensure_directory "$CACHE_DIR/commands"
    
    # Create cache metadata
    cat > "$CACHE_DIR/cache.json" <<EOF
{
    "version": "$CACHE_VERSION",
    "initialized": "$(timestamp)",
    "stats": {
        "hits": 0,
        "misses": 0,
        "evictions": 0
    }
}
EOF
    
    alfred_service "Cache System" "ready"
}

# Cache key generation
generate_cache_key() {
    local namespace="$1"
    local identifier="$2"
    local context="$3"
    
    # Create a hash of the inputs for consistent key generation
    local key_input="${namespace}:${identifier}:${context}"
    local key_hash=$(echo -n "$key_input" | shasum -a 256 | cut -d' ' -f1)
    
    echo "${namespace}_${key_hash:0:16}"
}

# Advanced cache operations
cache_get_advanced() {
    local namespace="$1"
    local identifier="$2"
    local context="$3"
    
    local cache_key=$(generate_cache_key "$namespace" "$identifier" "$context")
    local cache_file="$CACHE_DIR/$namespace/$cache_key"
    local meta_file="$CACHE_DIR/$namespace/$cache_key.meta"
    
    # Check if cache exists and is valid
    if [[ -f "$cache_file" && -f "$meta_file" ]]; then
        local created=$(json_get "$meta_file" "created")
        local ttl=$(json_get "$meta_file" "ttl")
        local now=$(epoch_time)
        
        if [[ $((now - created)) -lt $ttl ]]; then
            # Update cache stats
            update_cache_stats "hit"
            
            # Update access time
            json_set "$meta_file" "last_accessed" "$now"
            
            cat "$cache_file"
            return 0
        else
            # Cache expired
            rm -f "$cache_file" "$meta_file"
            update_cache_stats "miss"
            return 1
        fi
    else
        update_cache_stats "miss"
        return 1
    fi
}

cache_set_advanced() {
    local namespace="$1"
    local identifier="$2"
    local context="$3"
    local value="$4"
    local ttl="${5:-$DEFAULT_TTL}"
    
    local cache_key=$(generate_cache_key "$namespace" "$identifier" "$context")
    local cache_file="$CACHE_DIR/$namespace/$cache_key"
    local meta_file="$CACHE_DIR/$namespace/$cache_key.meta"
    
    ensure_directory "$CACHE_DIR/$namespace"
    
    # Store the value
    echo "$value" > "$cache_file"
    
    # Store metadata
    cat > "$meta_file" <<EOF
{
    "created": $(epoch_time),
    "ttl": $ttl,
    "last_accessed": $(epoch_time),
    "namespace": "$namespace",
    "identifier": "$identifier",
    "context": "$context",
    "size": $(wc -c < "$cache_file")
}
EOF
    
    # Check cache size and evict if necessary
    maintain_cache_size
}

# Cache invalidation
cache_invalidate() {
    local namespace="$1"
    local pattern="$2"
    
    if [[ -z "$pattern" ]]; then
        # Invalidate entire namespace
        rm -rf "$CACHE_DIR/$namespace"
        ensure_directory "$CACHE_DIR/$namespace"
        batcave_announce "Cache cleared for $namespace" "info"
    else
        # Invalidate specific pattern
        find "$CACHE_DIR/$namespace" -name "*$pattern*" -type f -delete
        batcave_announce "Cache invalidated for pattern: $pattern" "info"
    fi
}

# Cache maintenance
maintain_cache_size() {
    local current_size=$(du -sm "$CACHE_DIR" 2>/dev/null | cut -f1)
    
    if [[ $current_size -gt $MAX_CACHE_SIZE ]]; then
        # Find oldest files and remove them
        find "$CACHE_DIR" -name "*.meta" -type f -print0 | \
        xargs -0 ls -lt | \
        tail -n +$((MAX_CACHE_SIZE / 2)) | \
        while read -r line; do
            local meta_file=$(echo "$line" | awk '{print $NF}')
            local cache_file="${meta_file%.meta}"
            
            rm -f "$meta_file" "$cache_file"
            update_cache_stats "eviction"
        done
        
        batcave_announce "Cache maintenance completed" "info"
    fi
}

# Cache statistics
update_cache_stats() {
    local stat_type="$1"
    local stats_file="$CACHE_DIR/cache.json"
    
    case "$stat_type" in
        "hit")
            local hits=$(json_get "$stats_file" "stats.hits")
            json_set "$stats_file" "stats.hits" $((hits + 1))
            ;;
        "miss")
            local misses=$(json_get "$stats_file" "stats.misses")
            json_set "$stats_file" "stats.misses" $((misses + 1))
            ;;
        "eviction")
            local evictions=$(json_get "$stats_file" "stats.evictions")
            json_set "$stats_file" "stats.evictions" $((evictions + 1))
            ;;
    esac
}

get_cache_stats() {
    local stats_file="$CACHE_DIR/cache.json"
    
    if [[ -f "$stats_file" ]]; then
        local hits=$(json_get "$stats_file" "stats.hits")
        local misses=$(json_get "$stats_file" "stats.misses")
        local evictions=$(json_get "$stats_file" "stats.evictions")
        local total=$((hits + misses))
        
        if [[ $total -gt 0 ]]; then
            local hit_rate=$((hits * 100 / total))
            
            echo -e "${YELLOW}🦇 Batcave Cache Statistics:${NC}"
            echo -e "  Cache Hits: $hits"
            echo -e "  Cache Misses: $misses"
            echo -e "  Hit Rate: ${hit_rate}%"
            echo -e "  Evictions: $evictions"
            echo -e "  Cache Size: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)"
        else
            echo -e "${GRAY}🦇 Cache statistics not available${NC}"
        fi
    fi
}

# Specialized cache functions for different components

# MCP response caching
cache_mcp_response() {
    local server="$1"
    local query="$2"
    local response="$3"
    local ttl="${4:-1800}"  # 30 minutes for MCP responses
    
    cache_set_advanced "mcp" "$server" "$query" "$response" "$ttl"
}

get_cached_mcp_response() {
    local server="$1"
    local query="$2"
    
    cache_get_advanced "mcp" "$server" "$query"
}

# Persona context caching
cache_persona_context() {
    local persona="$1"
    local project_context="$2"
    local context_data="$3"
    local ttl="${4:-7200}"  # 2 hours for persona context
    
    cache_set_advanced "personas" "$persona" "$project_context" "$context_data" "$ttl"
}

get_cached_persona_context() {
    local persona="$1"
    local project_context="$2"
    
    cache_get_advanced "personas" "$persona" "$project_context"
}

# Project context caching
cache_project_context() {
    local project_path="$1"
    local context_data="$2"
    local ttl="${3:-3600}"  # 1 hour for project context
    
    local project_hash=$(echo -n "$project_path" | shasum -a 256 | cut -d' ' -f1 | head -c 16)
    cache_set_advanced "context" "project" "$project_hash" "$context_data" "$ttl"
}

get_cached_project_context() {
    local project_path="$1"
    
    local project_hash=$(echo -n "$project_path" | shasum -a 256 | cut -d' ' -f1 | head -c 16)
    cache_get_advanced "context" "project" "$project_hash"
}

# Command result caching
cache_command_result() {
    local command="$1"
    local args="$2"
    local result="$3"
    local ttl="${4:-600}"  # 10 minutes for command results
    
    cache_set_advanced "commands" "$command" "$args" "$result" "$ttl"
}

get_cached_command_result() {
    local command="$1"
    local args="$2"
    
    cache_get_advanced "commands" "$command" "$args"
}

# Cache warming for common operations
warm_cache() {
    local project_dir="${1:-$PWD}"
    
    batcave_announce "Warming cache for optimal performance..." "info"
    
    # Pre-cache project context
    local project_context=$(analyze_project_context "$project_dir")
    cache_project_context "$project_dir" "$project_context"
    
    # Pre-cache common persona contexts
    local personas=("master_wayne" "frontend" "backend" "architect")
    for persona in "${personas[@]}"; do
        local persona_context="{\"persona\": \"$persona\", \"project\": \"$(basename "$project_dir")\", \"timestamp\": \"$(timestamp)\"}"
        cache_persona_context "$persona" "$project_dir" "$persona_context"
    done
    
    batcave_announce "Cache warming completed" "info"
}

# Cache cleanup
cleanup_cache() {
    local age_days="${1:-7}"  # Default: clean files older than 7 days
    
    batcave_announce "Cleaning cache older than $age_days days..." "info"
    
    find "$CACHE_DIR" -type f -mtime +$age_days -delete
    
    # Clean empty directories
    find "$CACHE_DIR" -type d -empty -delete
    
    batcave_announce "Cache cleanup completed" "info"
}

# Initialize cache if not already done
if [[ ! -f "$CACHE_DIR/cache.json" ]]; then
    init_cache
fi

# Export cache functions
export -f init_cache generate_cache_key cache_get_advanced cache_set_advanced
export -f cache_invalidate maintain_cache_size update_cache_stats get_cache_stats
export -f cache_mcp_response get_cached_mcp_response
export -f cache_persona_context get_cached_persona_context
export -f cache_project_context get_cached_project_context
export -f cache_command_result get_cached_command_result
export -f warm_cache cleanup_cache