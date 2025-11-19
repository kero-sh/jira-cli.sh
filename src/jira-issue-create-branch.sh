# ==================== USAGE ====================

usage() {
        cat <<EOF
Usage: $(basename "$0") [options] <issue-key>

Options:
    -m                       Rename the current branch instead of creating a new one
    --summary <title>        Branch title (sanitized)
    -t <title>               Alias for --summary
    --summary=<title>        Branch title (sanitized)
    --prefix <prefix>        Branch prefix (feature, bugfix, hotfix, chore, etc)
    --prefix=<prefix>        Branch prefix (alternative form)
    -h, --help               Show this help and exit

Examples:
    $(basename "$0") PROJ-123
    $(basename "$0") --summary "My new feature" PROJ-123
    $(basename "$0") --prefix=hotfix --summary="Critical fix" PROJ-123
    $(basename "$0") -m --prefix feature PROJ-123

Notes:
    - If --summary/-t is not specified, the ticket title will be used.
    - If --prefix is not specified, it will be calculated automatically based on the ticket type/priority.
    - If the ticket is closed (has a resolution), a warning will be shown.
EOF
}
#!/bin/bash

DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";
source $DIR/../lib/helpers.sh

# ==================== UTILITY FUNCTIONS ====================

normalize_for_match() {
    printf '%s' "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT | tr '[:upper:]' '[:lower:]'
}

confirm() {
    local prompt="$1"
    local response
    echo -n "$prompt (y/n): " > /dev/tty
    read -r response < /dev/tty
    case "$response" in
        [yY]|[yY][eE][sS]|[sS]|[sS][iI])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==================== ARGUMENT PARSING ====================

parse_arguments() {
    RENAME_MODE=false
    ISSUE_KEY=""
    BRANCH_SUMMARY=""
    BRANCH_PREFIX=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -m)
                RENAME_MODE=true
                shift
                ;;
            --summary=*)
                BRANCH_SUMMARY="${1#*=}"
                shift
                ;;
            --summary|-t)
                BRANCH_SUMMARY="$2"
                shift 2
                ;;
            --prefix=*)
                BRANCH_PREFIX="${1#*=}"
                shift
                ;;
            --prefix)
                BRANCH_PREFIX="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ -z "$ISSUE_KEY" ]]; then
                    ISSUE_KEY="$1"
                else
                    error "Unknown option: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$ISSUE_KEY" ]; then
        error "You must provide an issue key"
        usage
        exit 1
    fi
    
    # Normalize issue key to uppercase (JIRA API requires uppercase)
    ISSUE_KEY=$(echo "$ISSUE_KEY" | tr '[:lower:]' '[:upper:]')
}

# ==================== JIRA ISSUE FUNCTIONS ====================

fetch_jira_issue() {
    local issue_key="$1"
    local issue_json=""

    info "Retrieving issue $issue_key from JIRA..."
    issue_json=$(jira issue-for-branch "$issue_key")

    if [ -z "$issue_json" ] || [ "$issue_json" = "null" ]; then
        error "Issue not found: $issue_key"
        exit 1
    fi

    # Sanitize JSON from control characters that break jq
    issue_json=$(printf '%s' "$issue_json" | tr -d '\000-\010\b\013\014\016-\037\177')

    info "Processing issue data..."
    local flat_issue
    flat_issue=$(echo "$issue_json" | jq -r --arg key "$issue_key" '{
        key: $key,
        summary: .fields.summary,
        type: .fields.issuetype.name,
        priority: .fields.priority.name,
        status: .fields.status.name,
        resolution: (.fields.resolution.name? // "")
    }')

    if [ $? -ne 0 ]; then
        error "Failed to parse issue data for $issue_key"
        error "JQ exit code: $?"
        error "Received JSON:"
        error "$issue_json"
        exit 1
    fi

    if [ -z "$flat_issue" ] || [ "$flat_issue" = "null" ]; then
        error "Could not extract key fields from issue $issue_key"
        exit 1
    fi

    echo "$flat_issue"
}

parse_issue_data() {
    local issue="$1"
    
    issue_key=$(echo "$issue" | jq -r '.key')
    issue_summary=$(echo "$issue" | jq -r '(.summary // "")')
    if [[ "$issue_summary" == "null" ]]; then
        issue_summary=""
    fi
    issue_type=$(echo "$issue" | jq -r '(.type // "")')
    issue_priority=$(echo "$issue" | jq -r '(.priority // "")')
    issue_status=$(echo "$issue" | jq -r '(.status // "")')
    issue_resolution=$(echo "$issue" | jq -r '(.resolution // "")')

    if [ -z "$issue_key" ] || [ "$issue_key" = "null" ]; then
        error "Issue not found"
        exit 1
    fi

    # Warn if the ticket is closed (has a non-empty resolution)
    if [ -n "$issue_resolution" ] && [ "$issue_resolution" != "null" ]; then
        warning "Ticket $issue_key is closed (resolution: $issue_resolution, status: $issue_status)"
    fi
}

# ==================== BRANCH NAME GENERATION ====================

determine_branch_prefix() {
    local type="$1"
    local priority="$2"
    
    local type_norm=$(normalize_for_match "$type")
    local priority_norm=$(normalize_for_match "$priority")
    local critical_priorities="blocker critical highest high mayor alta p0 p1 urgente sev-1 sev1 severidad-1"
    local prefix=""
    
    case "$type_norm" in
        bug|defect|error|bugfix|falla|fallo|defecto)
            if [[ " $critical_priorities " == *" $priority_norm "* ]]; then
                prefix="hotfix"
            else
                prefix="bugfix"
            fi
            ;;
        incident|incidente|production-incident|major-incident|problema-produccion)
            prefix="hotfix"
            ;;
        task|tarea|sub-task|subtask|story-task|technical-task|"solicitud de identidad en aws")
            prefix="task"
            ;;
        support|support-task|soporte)
            # For support tickets, treat as fixes by default; escalate to hotfix for critical priorities
            if [[ " $critical_priorities " == *" $priority_norm "* ]]; then
                prefix="hotfix"
            else
                prefix="fix"
            fi
            ;;
        chore|maintenance|maintenance-task|mantenimiento|operacion|"deuda tecnica"|kaizen)
            prefix="chore"
            ;;
        story|user-story|feature|improvement|enhancement|epic|historia|mejora|mejoras|feature-request|"historia funcional"|"historia tecnica"|"collocated design")
            prefix="feature"
            ;;
        "epica de discovery"|spike|experimentos|hypothesis|discovery|risk|riesgo)
            prefix="spike"
            ;;
        "release candidate")
            prefix="release"
            ;;
        *)
            if [[ "$type_norm" == *"bug"* || "$type_norm" == *"error"* ]]; then
                if [[ " $critical_priorities " == *" $priority_norm "* ]]; then
                    prefix="hotfix"
                else
                    prefix="bugfix"
                fi
            elif [[ "$type_norm" == *"task"* ]]; then
                prefix="task"
            elif [[ "$type_norm" == *"soport"* ]]; then
                # any type containing "soport" (soporte/support) defaults to fix; hotfix if critical
                if [[ " $critical_priorities " == *" $priority_norm "* ]]; then
                    prefix="hotfix"
                else
                    prefix="fix"
                fi
            elif [[ "$type_norm" == *"mainten"* || "$type_norm" == *"oper"* || "$type_norm" == *"deuda"* ]]; then
                prefix="chore"
            else
                prefix="feature"
            fi
            ;;
    esac
    
    echo "${prefix:-feature}"
}

sanitize_text() {
    local text="$1"
    
    # Remove leading and trailing spaces
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    
    # Convert accented vowels
    text="${text//á/a}"; text="${text//à/a}"; text="${text//â/a}"; text="${text//ã/a}"; text="${text//ä/a}"; text="${text//å/a}"
    text="${text//é/e}"; text="${text//è/e}"; text="${text//ê/e}"; text="${text//ë/e}"
    text="${text//í/i}"; text="${text//ì/i}"; text="${text//î/i}"; text="${text//ï/i}"
    text="${text//ó/o}"; text="${text//ò/o}"; text="${text//ô/o}"; text="${text//õ/o}"; text="${text//ö/o}"
    text="${text//ú/u}"; text="${text//ù/u}"; text="${text//û/u}"; text="${text//ü/u}"
    text="${text//ñ/n}"; text="${text//ç/c}"
    text="${text//Á/A}"; text="${text//À/A}"; text="${text//Â/A}"; text="${text//Ã/A}"; text="${text//Ä/A}"; text="${text//Å/A}"
    text="${text//É/E}"; text="${text//È/E}"; text="${text//Ê/E}"; text="${text//Ë/E}"
    text="${text//Í/I}"; text="${text//Ì/I}"; text="${text//Î/I}"; text="${text//Ï/I}"
    text="${text//Ó/O}"; text="${text//Ò/O}"; text="${text//Ô/O}"; text="${text//Õ/O}"; text="${text//Ö/O}"
    text="${text//Ú/U}"; text="${text//Ù/U}"; text="${text//Û/U}"; text="${text//Ü/U}"
    text="${text//Ñ/N}"; text="${text//Ç/C}"
    
    # Remove quotes, parentheses, brackets, braces and other special characters
    text="${text//\"/}"; text="${text//\'/}"; text="${text//\`/}"     # Quotes
    text="${text//\(/}"; text="${text//\)/}"                          # Parentheses
    text="${text//\[/}"; text="${text//\]/}"                          # Brackets
    text="${text//\{/}"; text="${text//\}/}"                          # Braces
    text="${text//\</}"; text="${text//\>/}"                          # Less/greater than
    text="${text//\&/and}"; text="${text//\@/at}"                     # Ampersand and at
    text="${text//\#/}"; text="${text//\$/}"; text="${text//\%/}"     # Hash, dollar, percent
    text="${text//\!/}"; text="${text//\?/}"                          # Exclamation, question
    text="${text//\*/}"; text="${text//\+/}"; text="${text//\=/}"     # Asterisk, plus, equal
    text="${text//\|/}"; text="${text//\\/}"; text="${text//\;/}"     # Pipe, backslash, semicolon
    text="${text//\:/}"; text="${text//\,/}"; text="${text//\./}"     # Colon, comma, period
    text="${text//\^/}"; text="${text//\~/}"                          # Circumflex, tilde
    
    echo "$text"
}

generate_branch_slug() {
    local summary="$1"
    
    # Sanitize special characters
    summary=$(sanitize_text "$summary")
    
    # Convert to lowercase
    summary=$(echo "$summary" | tr '[:upper:]' '[:lower:]')
    
    # Replace spaces with hyphens
    summary="${summary// /-}"
    
    # Remove invalid characters (only keep a-z, 0-9, and hyphens)
    local slug=""
    local i
    for (( i=0; i<${#summary}; i++ )); do
        local char="${summary:$i:1}"
        if [[ "$char" =~ ^[a-z0-9-]$ ]]; then
            slug="${slug}${char}"
        else
            slug="${slug}-"
        fi
    done
    
    # Compress multiple consecutive hyphens into one
    while [[ "$slug" == *"--"* ]]; do
        slug="${slug//--/-}"
    done
    
    # Remove leading and trailing hyphens
    slug="${slug#-}"
    slug="${slug%-}"
    
    [ -z "$slug" ] && slug="no-description"
    echo "$slug"
}

build_branch_name() {
    local prefix="$1"
    local key="$2"
    local summary="$3"
    local max_len=63
    
    local base_prefix="$prefix/$key"
    local base_prefix_with_dash="$base_prefix-"
    local allowed_slug_len=$((max_len - ${#base_prefix_with_dash}))
    local slug=$(generate_branch_slug "$summary")
    local branch_name=""
    
    # If there's no space for the slug, only use the prefix and key
    if (( allowed_slug_len <= 0 )); then
        branch_name="$base_prefix"
    else
        # Truncate the slug to available space
        slug="${slug:0:allowed_slug_len}"
        # Remove trailing hyphens after truncation
        slug="${slug%-}"
        
        # If the slug is empty, use a default value
        if [ -z "$slug" ]; then
            slug="no-description"
            slug="${slug:0:allowed_slug_len}"
            slug="${slug%-}"
            [ -z "$slug" ] && slug="x"
        fi
        
        branch_name="$base_prefix-$slug"
    fi
    
    # Final verification: ensure it doesn't exceed the limit
    if (( ${#branch_name} > max_len )); then
        branch_name="${branch_name:0:max_len}"
        # Clean unwanted trailing characters
        branch_name="${branch_name%-}"
        branch_name="${branch_name%/}"
        # If empty (very unlikely), use only the prefix
        if [ -z "$branch_name" ]; then
            branch_name="$prefix"
            branch_name="${branch_name:0:max_len}"
        fi
    fi
    
    # Final sanitization: remove any invalid characters using pure bash
    local clean_name=""
    local i
    for (( i=0; i<${#branch_name}; i++ )); do
        local char="${branch_name:$i:1}"
        if [[ "$char" =~ ^[a-zA-Z0-9/_-]$ ]]; then
            clean_name="${clean_name}${char}"
        fi
    done
    branch_name="$clean_name"
    
    echo "$branch_name"
}

# ==================== BRANCH PROTECTION ====================

is_protected_branch() {
    local branch="$1"
    local protected_branches=("master" "main" "develop" "development" "production" "prod" "staging" "stage" "release")
    
    for protected in "${protected_branches[@]}"; do
        if [ "$branch" = "$protected" ]; then
            return 0
        fi
    done
    
    if [[ "$branch" =~ ^release/ ]] || [[ "$branch" =~ ^hotfix/ ]]; then
        return 0
    fi
    
    return 1
}

get_default_branch() {
    local default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    
    if [ -z "$default_branch" ]; then
        default_branch=$(git config --get init.defaultBranch 2>/dev/null)
        if [ -z "$default_branch" ]; then
            if git rev-parse --verify main >/dev/null 2>&1; then
                default_branch="main"
            elif git rev-parse --verify master >/dev/null 2>&1; then
                default_branch="master"
            fi
        fi
    fi
    
    echo "$default_branch"
}

check_if_default_branch() {
    local current_branch="$1"
    local default_branch=$(get_default_branch)
    
    if [ -n "$default_branch" ] && [ "$current_branch" = "$default_branch" ]; then
        error "Cannot rename the repository's default branch"
        error "Current branch: $current_branch (default branch)"
        error ""
        error "The repository's default branch should not be renamed."
        error "Please switch to another branch first."
        exit 1
    fi
}

# ==================== RENAME MODE ====================

prompt_rename_confirmations() {
    local current_branch="$1"
    local new_branch_name="$2"
    
    info "Current branch: $current_branch"
    info "New name: $new_branch_name"
    info ""
    
    # Check protected branch
    if is_protected_branch "$current_branch"; then
        warning "Branch '$current_branch' is protected"
        info ""
        if ! confirm "Are you SURE you want to rename this protected branch?"; then
            info "Operation cancelled"
            exit 1
        fi
    fi
    
    # Check upstream
    local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
    local rename_remote=false
    
    if [ -n "$upstream" ]; then
        info ""
        info "The current branch has an upstream configured: $upstream"
        if confirm "Do you want to rename the remote branch as well?"; then
            rename_remote=true
        fi
    fi
    
    # Final confirmation
    info ""
    info "Operation summary:"
    info "  - Rename local branch: $current_branch -> $new_branch_name"
    if [ "$rename_remote" = true ]; then
        info "  - Delete remote branch: $upstream"
        info "  - Create new remote branch: $new_branch_name"
    fi
    info ""
    
    if ! confirm "Proceed with the rename?"; then
        info "Operation cancelled"
        exit 1
    fi
    
    echo "$rename_remote|$upstream"
}

execute_rename() {
    local new_branch_name="$1"
    local rename_remote="$2"
    local upstream="$3"
    local current_branch="$4"
    
    info ""
    info "Renaming local branch..."
    if ! git branch -m "$new_branch_name"; then
        error "Failed to rename local branch"
        exit 1
    fi
    
    success "Local branch renamed successfully"
    
    if [ "$rename_remote" = "true" ]; then
        local remote=$(echo "$upstream" | cut -d'/' -f1)
        
        info ""
        info "Deleting old remote branch..."
        if ! git push "$remote" --delete "$current_branch"; then
            warning "Failed to delete old remote branch"
            warning "You can delete it manually with: git push $remote --delete $current_branch"
        else
            success "Old remote branch deleted"
        fi
        
        info ""
        info "Creating new remote branch..."
        if ! git push -u "$remote" "$new_branch_name"; then
            error "Failed to create new remote branch"
            error "Local branch was renamed but remote failed"
            exit 1
        fi
        
        success "New remote branch created and set as upstream"
    fi
    
    info ""
    success "Rename completed successfully"
    info "Current branch: $new_branch_name"
}

rename_branch() {
    local new_branch_name="$1"
    
    local current_branch=$(git branch --show-current)
    
    if [ -z "$current_branch" ]; then
        error "Failed to determine current branch"
        exit 1
    fi
    
    check_if_default_branch "$current_branch"
    
    local result=$(prompt_rename_confirmations "$current_branch" "$new_branch_name")
    local rename_remote=$(echo "$result" | cut -d'|' -f1)
    local upstream=$(echo "$result" | cut -d'|' -f2)
    
    execute_rename "$new_branch_name" "$rename_remote" "$upstream" "$current_branch"
}

# ==================== CREATE MODE ====================

create_branch() {
    local branch_name="$1"
    git checkout -b "$branch_name"
}

# ==================== MAIN EXECUTION ====================

main() {
    parse_arguments "$@"

    local issue=""
    local issue_key="$ISSUE_KEY"
    local issue_summary=""
    local issue_type=""
    local issue_priority=""

    if [ -z "$BRANCH_SUMMARY" ] || [ -z "$BRANCH_PREFIX" ]; then
        issue=$(fetch_jira_issue "$ISSUE_KEY")
        # In case any informational logs leaked to stdout, keep only the JSON payload
        issue=$(printf '%s\n' "$issue" | sed -n '/^{/,$p')
        parse_issue_data "$issue"
    fi

    # If user passed --summary/-t, use it, otherwise use the ticket's
    if [ -n "$BRANCH_SUMMARY" ]; then
        issue_summary="$BRANCH_SUMMARY"
    fi
    # If user passed --prefix, use it, otherwise use the calculated one
    if [ -n "$BRANCH_PREFIX" ]; then
        branch_prefix="$BRANCH_PREFIX"
    else
        branch_prefix=$(determine_branch_prefix "$issue_type" "$issue_priority")
    fi
    branch_name=$(build_branch_name "$branch_prefix" "$issue_key" "$issue_summary")

    if [ "$RENAME_MODE" = true ]; then
        rename_branch "$branch_name"
    else
        create_branch "$branch_name"
    fi
}

main "$@"
