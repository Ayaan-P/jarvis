#!/bin/bash
# lib/context.sh - Context analysis and project intelligence

source "${CLAUDE_HOME:-$HOME/.claude}/lib/utils.sh"

# Project type detection
detect_project_type() {
    local project_dir="${1:-$PWD}"
    local project_types=()
    
    # Check for various project indicators
    if [[ -f "$project_dir/package.json" ]]; then
        local package_content=$(cat "$project_dir/package.json")
        
        if echo "$package_content" | grep -q '"react"'; then
            project_types+=("react")
        fi
        
        if echo "$package_content" | grep -q '"next"'; then
            project_types+=("nextjs")
        fi
        
        if echo "$package_content" | grep -q '"express"'; then
            project_types+=("express")
        fi
        
        if echo "$package_content" | grep -q '"@types/"'; then
            project_types+=("typescript")
        fi
        
        project_types+=("nodejs")
    fi
    
    if [[ -f "$project_dir/requirements.txt" || -f "$project_dir/setup.py" || -f "$project_dir/pyproject.toml" ]]; then
        project_types+=("python")
        
        if [[ -f "$project_dir/manage.py" ]]; then
            project_types+=("django")
        fi
        
        if find "$project_dir" -name "*.py" -exec grep -l "from flask" {} \; | head -1 >/dev/null 2>&1; then
            project_types+=("flask")
        fi
    fi
    
    if [[ -f "$project_dir/Cargo.toml" ]]; then
        project_types+=("rust")
    fi
    
    if [[ -f "$project_dir/go.mod" ]]; then
        project_types+=("golang")
    fi
    
    if [[ -f "$project_dir/pom.xml" || -f "$project_dir/build.gradle" ]]; then
        project_types+=("java")
    fi
    
    # Docker detection
    if [[ -f "$project_dir/Dockerfile" || -f "$project_dir/docker-compose.yml" ]]; then
        project_types+=("docker")
    fi
    
    # Kubernetes detection
    if [[ -d "$project_dir/k8s" ]] || find "$project_dir" -name "*.yaml" -o -name "*.yml" | grep -E "(deployment|service|ingress)" >/dev/null 2>&1; then
        project_types+=("kubernetes")
    fi
    
    # Default to general if no specific type detected
    if [[ ${#project_types[@]} -eq 0 ]]; then
        project_types+=("general")
    fi
    
    join_array "," "${project_types[@]}"
}

# Technology stack analysis
analyze_tech_stack() {
    local project_dir="${1:-$PWD}"
    local tech_stack=()
    
    # Frontend technologies
    if [[ -f "$project_dir/package.json" ]]; then
        local deps=$(jq -r '.dependencies // {} | keys[]' "$project_dir/package.json" 2>/dev/null)
        local dev_deps=$(jq -r '.devDependencies // {} | keys[]' "$project_dir/package.json" 2>/dev/null)
        
        for dep in $deps $dev_deps; do
            case "$dep" in
                react) tech_stack+=("React") ;;
                vue) tech_stack+=("Vue.js") ;;
                angular) tech_stack+=("Angular") ;;
                svelte) tech_stack+=("Svelte") ;;
                next) tech_stack+=("Next.js") ;;
                nuxt) tech_stack+=("Nuxt.js") ;;
                typescript) tech_stack+=("TypeScript") ;;
                tailwindcss) tech_stack+=("TailwindCSS") ;;
                sass) tech_stack+=("Sass") ;;
                webpack) tech_stack+=("Webpack") ;;
                vite) tech_stack+=("Vite") ;;
                express) tech_stack+=("Express.js") ;;
                koa) tech_stack+=("Koa.js") ;;
                fastify) tech_stack+=("Fastify") ;;
                graphql) tech_stack+=("GraphQL") ;;
                apollo*) tech_stack+=("Apollo GraphQL") ;;
                prisma) tech_stack+=("Prisma") ;;
                mongoose) tech_stack+=("MongoDB") ;;
                sequelize) tech_stack+=("Sequelize") ;;
                typeorm) tech_stack+=("TypeORM") ;;
                jest) tech_stack+=("Jest") ;;
                vitest) tech_stack+=("Vitest") ;;
                cypress) tech_stack+=("Cypress") ;;
                playwright) tech_stack+=("Playwright") ;;
                storybook) tech_stack+=("Storybook") ;;
            esac
        done
    fi
    
    # Backend technologies
    if [[ -f "$project_dir/requirements.txt" ]]; then
        local python_deps=$(cat "$project_dir/requirements.txt" | grep -E "^[a-zA-Z]" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1)
        
        for dep in $python_deps; do
            case "$dep" in
                django) tech_stack+=("Django") ;;
                flask) tech_stack+=("Flask") ;;
                fastapi) tech_stack+=("FastAPI") ;;
                sqlalchemy) tech_stack+=("SQLAlchemy") ;;
                celery) tech_stack+=("Celery") ;;
                redis) tech_stack+=("Redis") ;;
                postgresql) tech_stack+=("PostgreSQL") ;;
                mysql) tech_stack+=("MySQL") ;;
                sqlite) tech_stack+=("SQLite") ;;
                pytest) tech_stack+=("pytest") ;;
                requests) tech_stack+=("Requests") ;;
                pandas) tech_stack+=("Pandas") ;;
                numpy) tech_stack+=("NumPy") ;;
                tensorflow) tech_stack+=("TensorFlow") ;;
                pytorch) tech_stack+=("PyTorch") ;;
            esac
        done
    fi
    
    # Database detection
    if [[ -f "$project_dir/docker-compose.yml" ]]; then
        local compose_content=$(cat "$project_dir/docker-compose.yml")
        
        if echo "$compose_content" | grep -q "postgres"; then
            tech_stack+=("PostgreSQL")
        fi
        
        if echo "$compose_content" | grep -q "mysql"; then
            tech_stack+=("MySQL")
        fi
        
        if echo "$compose_content" | grep -q "redis"; then
            tech_stack+=("Redis")
        fi
        
        if echo "$compose_content" | grep -q "mongodb"; then
            tech_stack+=("MongoDB")
        fi
    fi
    
    # Remove duplicates and sort
    printf '%s\n' "${tech_stack[@]}" | sort -u | tr '\n' ',' | sed 's/,$//'
}

# Complexity analysis
calculate_complexity() {
    local project_dir="${1:-$PWD}"
    local complexity_score=0
    
    # File count complexity
    local file_count=$(find "$project_dir" -type f -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" | wc -l)
    complexity_score=$((complexity_score + file_count / 10))
    
    # Line count complexity
    local line_count=$(find "$project_dir" -type f -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo 0)
    complexity_score=$((complexity_score + line_count / 1000))
    
    # Dependency complexity
    local dep_count=0
    if [[ -f "$project_dir/package.json" ]]; then
        dep_count=$(jq -r '.dependencies // {} | keys | length' "$project_dir/package.json" 2>/dev/null || echo 0)
    elif [[ -f "$project_dir/requirements.txt" ]]; then
        dep_count=$(wc -l < "$project_dir/requirements.txt" 2>/dev/null || echo 0)
    fi
    complexity_score=$((complexity_score + dep_count / 5))
    
    # Project type complexity
    local project_type=$(detect_project_type "$project_dir")
    if [[ "$project_type" == *"docker"* ]]; then
        complexity_score=$((complexity_score + 10))
    fi
    
    if [[ "$project_type" == *"kubernetes"* ]]; then
        complexity_score=$((complexity_score + 20))
    fi
    
    # Categorize complexity
    if [[ $complexity_score -lt 10 ]]; then
        echo "low"
    elif [[ $complexity_score -lt 30 ]]; then
        echo "medium"
    elif [[ $complexity_score -lt 60 ]]; then
        echo "high"
    else
        echo "very_high"
    fi
}

# Domain detection for appropriate persona selection
detect_problem_domain() {
    local problem="$*"
    local domain="general"
    
    # Convert to lowercase for matching
    local problem_lower=$(to_lower "$problem")
    
    # Architecture keywords
    if echo "$problem_lower" | grep -E "(architect|design|system|pattern|microservice|scalab|infrastruc)" >/dev/null; then
        domain="architecture"
    # Performance keywords
    elif echo "$problem_lower" | grep -E "(performance|speed|optimiz|slow|fast|latency|throughput)" >/dev/null; then
        domain="performance"
    # Security keywords
    elif echo "$problem_lower" | grep -E "(security|vulnerabil|auth|encrypt|token|permission|attack)" >/dev/null; then
        domain="security"
    # Frontend keywords
    elif echo "$problem_lower" | grep -E "(ui|frontend|react|vue|angular|component|css|html|responsive)" >/dev/null; then
        domain="frontend"
    # Backend keywords
    elif echo "$problem_lower" | grep -E "(backend|api|server|database|sql|nosql|endpoint|service)" >/dev/null; then
        domain="backend"
    # DevOps keywords
    elif echo "$problem_lower" | grep -E "(deploy|docker|kubernetes|ci/cd|pipeline|cloud|aws|azure|gcp)" >/dev/null; then
        domain="devops"
    # Testing keywords
    elif echo "$problem_lower" | grep -E "(test|testing|unit|integration|e2e|cypress|jest|spec)" >/dev/null; then
        domain="testing"
    # Data/Analytics keywords
    elif echo "$problem_lower" | grep -E "(data|analytics|ml|ai|machine|learning|model|dataset)" >/dev/null; then
        domain="data"
    fi
    
    echo "$domain"
}

# Project context analysis
analyze_project_context() {
    local project_dir="${1:-$PWD}"
    local context={}
    
    # Basic project info
    local project_name=$(basename "$project_dir")
    local project_type=$(detect_project_type "$project_dir")
    local tech_stack=$(analyze_tech_stack "$project_dir")
    local complexity=$(calculate_complexity "$project_dir")
    
    # Git context
    local git_branch=""
    local git_status=""
    if is_git_repo; then
        git_branch=$(git_current_branch)
        if git_is_clean; then
            git_status="clean"
        else
            git_status="dirty"
        fi
    fi
    
    # Recent activity
    local recent_files=()
    if [[ -d "$project_dir/.git" ]]; then
        while IFS= read -r file; do
            recent_files+=("$file")
        done < <(git log --name-only --oneline -10 | grep -v "^[a-f0-9]" | sort -u | head -5)
    fi
    
    # Build context
    cat << EOF
{
    "project_name": "$project_name",
    "project_type": "$project_type",
    "tech_stack": "$tech_stack",
    "complexity": "$complexity",
    "git_branch": "$git_branch",
    "git_status": "$git_status",
    "recent_files": [$(printf '"%s",' "${recent_files[@]}" | sed 's/,$//')],
    "timestamp": "$(timestamp)"
}
EOF
}

# Feature analysis for implementation commands
analyze_feature_complexity() {
    local feature="$1"
    local feature_lower=$(to_lower "$feature")
    
    # Simple features
    if echo "$feature_lower" | grep -E "(fix|update|change|add.*button|add.*link|text|color|style)" >/dev/null; then
        echo "low"
    # Medium features
    elif echo "$feature_lower" | grep -E "(form|component|page|modal|api.*endpoint|crud|validation)" >/dev/null; then
        echo "medium"
    # Complex features
    elif echo "$feature_lower" | grep -E "(auth|payment|search|real.*time|notification|integration|migration)" >/dev/null; then
        echo "high"
    # Very complex features
    elif echo "$feature_lower" | grep -E "(architect|system|platform|infrastructure|ml|ai|analytics)" >/dev/null; then
        echo "very_high"
    else
        echo "medium"
    fi
}

# Detect implementation needs
analyze_feature_needs() {
    local feature="$1"
    local feature_lower=$(to_lower "$feature")
    local needs=()
    
    # UI needs
    if echo "$feature_lower" | grep -E "(ui|component|page|modal|form|button|interface)" >/dev/null; then
        needs+=("ui")
    fi
    
    # API needs
    if echo "$feature_lower" | grep -E "(api|endpoint|service|backend|server|database)" >/dev/null; then
        needs+=("api")
    fi
    
    # Testing needs
    if echo "$feature_lower" | grep -E "(test|testing|spec|e2e|integration)" >/dev/null; then
        needs+=("testing")
    fi
    
    # Documentation needs
    if echo "$feature_lower" | grep -E "(doc|documentation|readme|guide|manual)" >/dev/null; then
        needs+=("documentation")
    fi
    
    # Authentication needs
    if echo "$feature_lower" | grep -E "(auth|login|register|permission|role|security)" >/dev/null; then
        needs+=("auth")
    fi
    
    # Data needs
    if echo "$feature_lower" | grep -E "(data|database|migration|model|schema)" >/dev/null; then
        needs+=("data")
    fi
    
    # Default to full-stack if multiple needs or unclear
    if [[ ${#needs[@]} -gt 2 ]] || [[ ${#needs[@]} -eq 0 ]]; then
        needs=("full-stack")
    fi
    
    join_array " " "${needs[@]}"
}

# Export functions
export -f detect_project_type analyze_tech_stack calculate_complexity
export -f detect_problem_domain analyze_project_context
export -f analyze_feature_complexity analyze_feature_needs