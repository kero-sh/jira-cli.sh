#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

COMMENT_MESSAGE=""
DISCARD_MODE=false

usage() {
    cat <<EOF
Uso: $(basename "$0") <issue_key> [options]

Descripción:
  Transiciona un issue a través de múltiples estados hasta llegar a Done.
  Determina automáticamente el workflow del proyecto y calcula el camino
  de transiciones necesarias sin usar IDs hardcoded.

Opciones:
  -h, --help         Muestra esta ayuda
    --tickets LIST     Lista de issues separados por comas (ej: ANDES-1,ANDES-2)
  -m, --message "txt"  Agrega comentario al finalizar (si queda en Done)
  --discard           Descarta el ticket en lugar de llevarlo a Done

Ejemplos:
  $(basename "$0") ABC-123
EOF
    exit 0
}

# Parse args: support --tickets, -m and positional issue key
TICKETS=""
ISSUE_KEY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --tickets=*)
            TICKETS="${1#*=}"
            shift
            ;;
        --tickets)
            TICKETS="$2"
            shift 2
            ;;
        -m|--message)
            COMMENT_MESSAGE="$2"
            shift 2
            ;;
        --discard)
            DISCARD_MODE=true
            shift
            ;;
        *)
            if [[ -z "$ISSUE_KEY" ]]; then
                ISSUE_KEY="$1"
                shift
            else
                error "Unknown argument: $1"
                usage
            fi
            ;;
    esac
done

if [[ -z "$TICKETS" && -z "$ISSUE_KEY" ]]; then
    error "You must specify an issue key or use --tickets"
    usage
fi

# Regex to identify discard states
DISCARD_REGEX='(?i)(discard|descart|cancel|rechaz|reject|wont[[:space:]]*fix|won'\''t[[:space:]]*fix|invalid|duplicate|obsolete|not[[:space:]]*do|no[[:space:]]se[[:space:]]hara|no[[:space:]]se[[:space:]]har[aá])'

# Deduction of the next step using only available transitions of the issue
# Rule:
#   1) If there are transitions to Done category that do not match discard, take the first.
#   2) If there are no Done, check transitions In Progress / Indeterminate without discard.
#      - If there is exactly one, use it.
#      - If there are 0 or more than one, do not force and return empty.
select_next_transition() {
    local transitions_json="$1"

    # Select Done transitions that do not match discard
    local done_pick
    done_pick=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
        (.transitions // [])
        | map(select(
            (.to.statusCategory.key // "" | ascii_downcase) == "done"
            and ((.name // "" | test($re;"i")) | not)
            and ((.to.name // "" | test($re;"i")) | not)
        ))
        | (.[0] // empty)
        | if . == null then "" else "\(.id)|\(.to.name)|done" end
    ')
    [[ -n "$done_pick" ]] && { echo "$done_pick"; return 0; }

    # Select In Progress / Indeterminate (or any other non-discard if no better option)
    local inprog_pick
    inprog_pick=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
        (.transitions // [])
        | map(select(
            ((.to.statusCategory.key // "" | ascii_downcase) | test("inprogress|indeterminate";"i"))
            and ((.name // "" | test($re;"i")) | not)
            and ((.to.name // "" | test($re;"i")) | not)
        ))
        | if length >= 1 then "\(.[] .id)|\(.[] .to.name)|\(.[] .to.statusCategory.key)" else "" end
    ')
    [[ -n "$inprog_pick" ]] && { echo "$inprog_pick"; return 0; }

    # Select any transition not discarded (e.g. To Do category) if it is the only option
    local any_pick
    any_pick=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
        (.transitions // [])
        | map(select(
            ((.name // "" | test($re;"i")) | not)
            and ((.to.name // "" | test($re;"i")) | not)
        )) as $clean
        | if ($clean | length) == 0 then "" 
          elif ($clean | length) == 1 then ($clean[0] | "\(.id)|\(.to.name)|\(.to.statusCategory.key)")
          else (
              ($clean
               | map(select((.to.statusCategory.key // "" | ascii_downcase) | test("inprogress|indeterminate";"i")))
               | .[0]?) as $pref
              | if $pref != null then "\($pref.id)|\($pref.to.name)|\($pref.to.statusCategory.key)"
                else ($clean[0] | "\(.id)|\(.to.name)|\(.to.statusCategory.key)")
                end
            )
          end
    ')
    [[ -n "$any_pick" ]] && { echo "$any_pick"; return 0; }

    # No applicable transition
    return 1
}

# Add final comment if requested
add_comment_if_requested() {
    local issue="$1"
    if [[ -n "$COMMENT_MESSAGE" ]]; then
        info "Adding final comment..."
        if ! printf '%s' "$COMMENT_MESSAGE" | $DIR/jira.sh issue comment "$issue" -m - >/dev/null 2>&1; then
            warn "Could not add comment to issue $issue"
        fi
    fi
}

# Execute transition to a specific status
execute_transition_to_status() {
    local issue="$1"
    local target_status="$2"
    
    local transitions=$($DIR/jira.sh issue "$issue" --transitions 2>/dev/null)
    if [[ -z "$transitions" ]]; then
        warn "Could not get available transitions"
        return 1
    fi
    
    local transition_id=$(echo "$transitions" | jq -r --arg status "$target_status" \
        '.transitions[] | select(.to.name == $status) | .id' | head -1)
    
    if [[ -n "$transition_id" && "$transition_id" != "null" ]]; then
        info "Transitioning to: $target_status (ID: $transition_id)"
        $DIR/jira.sh issue "$issue" --transitions --to "$transition_id" >/dev/null 2>&1
        return $?
    fi
    
    return 1
}

# Process a single ticket: wrapper to reuse the same logic for multiple tickets
process_issue() {
    local ISSUE_KEY_LOCAL="$1"

    # 1. Get issue information
    info "Getting information for issue $ISSUE_KEY_LOCAL..."
    local issue_data
    issue_data=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" 2>/dev/null)
    if [[ -z "$issue_data" ]]; then
        error "Could not get information for issue $ISSUE_KEY_LOCAL"
        return 1
    fi

    # Verify if issue exists
    local error_msg
    error_msg=$(echo "$issue_data" | jq -r '.errorMessages[]? // empty' 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
        echo -e "\033[1;31m[ERROR] Issue $ISSUE_KEY_LOCAL does not exist in Jira\033[0m" >&2
        return 1
    fi

    local project_key
    local issue_type
    local current_status
    local current_category
    project_key=$(echo "$issue_data" | jq -r '.fields.project.key')
    issue_type=$(echo "$issue_data" | jq -r '.fields.issuetype.name')
    current_status=$(echo "$issue_data" | jq -r '.fields.status.name')
    current_category=$(echo "$issue_data" | jq -r '.fields.status.statusCategory.name')

    # Verify if fields are null (another indicator of issue inexistence)
    if [[ "$project_key" == "null" || -z "$project_key" ]]; then
        echo -e "\033[1;31m[ERROR] Issue $ISSUE_KEY_LOCAL does not exist or is not accessible\033[0m" >&2
        return 1
    fi

    info "Project: $project_key, Type: $issue_type, Current status: $current_status"

    # 2. Verify if already in Done or discard was requested
    if [[ "$DISCARD_MODE" == "true" ]]; then
        if [[ "$current_category" == "Done" ]]; then
            success "Issue is already in Done status: $current_status"
            add_comment_if_requested "$ISSUE_KEY_LOCAL"
            $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"
            return 0
        fi
        # Search for discard transition
        local transitions_json
        transitions_json=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions 2>/dev/null)
        local discard_transitions
        discard_transitions=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
            (.transitions // [])
            | map(select(
                (.to.statusCategory.key // "" | ascii_downcase) == "done"
                and ((.name // "" | test($re;"i")) or ((.to.name // "" | test($re;"i"))))
            ))
            | (.[0] // empty)
            | if . == null then "" else "\(.id)|\(.to.name)|done" end
        ')
        if [[ -n "$discard_transitions" ]]; then
            IFS='|' read -r discard_id discard_name discard_cat <<< "$discard_transitions"
            info "Discarding ticket: $discard_name (id: $discard_id)"
            if $DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions --to "$discard_id" >/dev/null 2>&1; then
                success "Ticket discarded successfully: $discard_name"
                add_comment_if_requested "$ISSUE_KEY_LOCAL"
                $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"
                return 0
            else
                error "Failed to discard ticket"
                return 1
            fi
        else
            warn "No discard transition available"
            return 1
        fi
    fi

    if [[ "$current_category" == "Done" ]]; then
        success "Issue is already in Done status: $current_status"
        add_comment_if_requested "$ISSUE_KEY_LOCAL"
        $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"
        return 0
    fi

    # 3. Resolve by available transitions, without forcing states outside the flow
    local max_steps=10
    local step=1
    while [[ $step -le $max_steps ]]; do
        local transitions_json
        transitions_json=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions 2>/dev/null)
        if [[ -z "$transitions_json" ]]; then
            warn "Could not get transitions at step $step"
            break
        fi

        local pick
        pick=$(select_next_transition "$transitions_json")
        if [[ -z "$pick" ]]; then
            warn "No allowed transitions (Done or single In Progress) at step $step"
            break
        fi

        IFS='|' read -r tr_id tr_name tr_cat <<< "$pick"
        info "Step $step: applying transition $tr_name (id: $tr_id, cat: $tr_cat)"
        if ! $DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions --to "$tr_id" >/dev/null 2>&1; then
            warn "Transition failed $tr_id -> $tr_name"
            break
        fi

        sleep 1
        issue_data=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" 2>/dev/null)
        current_status=$(echo "$issue_data" | jq -r '.fields.status.name')
        current_category=$(echo "$issue_data" | jq -r '.fields.status.statusCategory.name')
        info "Status after step $step: $current_status ($current_category)"
        if [[ "$current_category" == "Done" ]]; then
            success "Issue successfully transitioned to Done status: $current_status"
            add_comment_if_requested "$ISSUE_KEY_LOCAL"
            return 0
        fi
        ((step++))
    done

    # 4. Verify final result
    echo ""
    info "Final issue status:"
    $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"

    # Verify if we reached the Done state
    final_data=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" 2>/dev/null)
    final_category=$(echo "$final_data" | jq -r '.fields.status.statusCategory.name')
    final_status=$(echo "$final_data" | jq -r '.fields.status.name')

    if [[ "$final_category" == "Done" ]]; then
        success "Issue successfully transitioned to Done status: $final_status"
        return 0
    else
        warn "Issue did not reach Done status. Current status: $final_status ($final_category)"
        return 1
    fi
}

# If multiple tickets provided, process them sequentially
if [[ -n "$TICKETS" ]]; then
    IFS=',' read -ra arr <<< "$TICKETS"
    overall_status=0
    for t in "${arr[@]}"; do
        # Trim whitespace
        ticket=$(printf '%s' "$t" | sed -e 's/^ *//' -e 's/ *$//')
        info "--- Processing $ticket ---"
        if ! process_issue "$ticket"; then
            warn "Failed to process $ticket"
            overall_status=1
        fi
        echo ""
    done
    if [[ $overall_status -eq 0 ]]; then
        success "All transitions completed (or were already in Done)."
        exit 0
    else
        warn "Some transitions failed. Review the output above."
        exit 1
    fi
else
    # Single issue mode
    if process_issue "$ISSUE_KEY"; then
        exit 0
    else
        exit 1
    fi
fi