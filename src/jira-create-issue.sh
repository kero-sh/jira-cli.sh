#!/bin/bash
DIR="$( cd "$( dirname $(realpath "${BASH_SOURCE[0]}" ))" && pwd )";

source "$DIR/../lib/helpers.sh"

# --- Variable Defaults ---
issue_key=""
issue_type=""
project="${JIRA_PROJECT}"
summary=""
description=""
description_file=""
assignee=""
reporter=""
priority=""
epic=""
link_issue=""
template=""
json_file=""
format_flag=""  # Can be "--adf", "--wiki", or empty for auto-detect
max_description_length=32767  # Jira's typical limit for description fields

# --- Function Definitions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [issue_key|json_file] [options]

Create or update a Jira issue.

If [issue_key] is provided, the script will update the existing issue.
If a JSON file is provided (e.g., issue.json), properties will be read from it.
Otherwise, it will create a new issue prompting for required fields.

Options:
  -p, --project <KEY>           Set the project key (defaults to \$JIRA_PROJECT).
  -t, --type <NAME>             Set the issue type (e.g., "Story", "Bug"). Defaults to "Task".
  -s, --summary <TEXT>          Set the issue summary (title).
  -d, --description <TEXT>      Set the issue description. Use '-' to read from stdin.
      --description-file <PATH> Path to a file containing the description.
      --adf                     Use ADF format (Jira Cloud). Auto-converts Markdown to ADF.
      --wiki                    Use Wiki Markup (Jira Server). Auto-converts Markdown to Wiki.
      --no-convert              Send description as-is without conversion.
  -e, --epic <KEY>              Link the issue to an Epic.
  -a, --assignee <NAME>         Assign the issue to a user.
  -r, --reporter <NAME>         Set the reporter of the issue.
  -P, --priority <NAME>         Set the issue priority.
  -l, --link-issue <KEY>        Create a "Relates to" link to another issue.
      --template <PATH>         Path to a custom JSON template file.
  -h, --help                    Show this help message.

Examples:
  $(basename "$0") --type=Bug --summary="Fix login" --description="Login issue"
  $(basename "$0") issue.json
  $(basename "$0") issue.json --type=Soporte
EOF
  exit 0
}

parse_description() {
  local desc_input="$1"
  if [ "$desc_input" == "-" ]; then
    description=$(cat -)
  else
    description="$desc_input"
  fi
  export description
}

load_from_json_file() {
  if [ -z "$json_file" ] || [ ! -f "$json_file" ]; then
    return
  fi

  info "Loading properties from $json_file..."
  
  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    error "jq is required to parse JSON files but not found. Please install jq."
    exit 1
  fi

  # Read properties from JSON file only if they haven't been set via command line
  [ -z "$project" ]     && project=$(jq -r '.project // .fields.project.key // empty' "$json_file" 2>/dev/null)
  [ -z "$issue_type" ]  && issue_type=$(jq -r '.type // .issuetype // .fields.issuetype.name // empty' "$json_file" 2>/dev/null)
  [ -z "$summary" ]     && summary=$(jq -r '.summary // .fields.summary // empty' "$json_file" 2>/dev/null)
  [ -z "$description" ] && description=$(jq -r '.description // .fields.description // empty' "$json_file" 2>/dev/null)
  [ -z "$assignee" ]    && assignee=$(jq -r '.assignee // .fields.assignee.name // empty' "$json_file" 2>/dev/null)
  [ -z "$reporter" ]    && reporter=$(jq -r '.reporter // .fields.reporter.name // empty' "$json_file" 2>/dev/null)
  [ -z "$priority" ]    && priority=$(jq -r '.priority // .fields.priority.name // empty' "$json_file" 2>/dev/null)
  [ -z "$epic" ]        && epic=$(jq -r '.epic // .fields.customfield_10100 // empty' "$json_file" 2>/dev/null)
  [ -z "$link_issue" ]  && link_issue=$(jq -r '.link // .linkIssue // empty' "$json_file" 2>/dev/null)
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--project)           project="$2";                shift 2 ;;
      --project=*)            project="${1#*=}";           shift 1 ;;
      -t|--type)              issue_type="$2";             shift 2 ;;
      --type=*)               issue_type="${1#*=}";        shift 1 ;;
      -s|--summary)           summary="$2";                shift 2 ;;
      --summary=*)            summary="${1#*=}";           shift 1 ;;
      -d|--description)       parse_description "$2";      shift 2 ;;
      --description=*)        parse_description "${1#*=}"; shift 1 ;;      
      --description-file)     description_file="$2";       shift 2 ;;
      --description-file=*)   description_file="${1#*=}";  shift 1 ;;
      --adf)                  format_flag="--adf";         shift 1 ;;
      --wiki)                 format_flag="--wiki";        shift 1 ;;
      --no-convert)           format_flag="--no-convert";  shift 1 ;;
      -e|--epic)              epic="$2";                   shift 2 ;;
      --epic=*)               epic="${1#*=}";              shift 1 ;;
      -a|--assignee)          assignee="$2";               shift 2 ;;
      --assignee=*)           assignee="${1#*=}";          shift 1 ;;
      -r|--reporter)          reporter="$2";               shift 2 ;;
      --reporter=*)           reporter="${1#*=}";          shift 1 ;;
      -P|--priority)          priority="$2";               shift 2 ;;
      --priority=*)           priority="${1#*=}";          shift 1 ;;
      -l|--link-issue)        link_issue="$2";             shift 2 ;;
      --link-issue=*)         link_issue="${1#*=}";        shift 1 ;;
      --template)             template="$2";               shift 2 ;;
      --template=*)           template="${1#*=}";          shift 1 ;;
      -h|--help) usage ;;
      -*)
        error "Unknown option: $1"
        usage
        ;;
      *)
        # Check if it's a JSON file or issue key
        if [ -f "$1" ] && [[ "$1" == *.json ]]; then
          json_file="$1"
          shift
        elif [ -z "$issue_key" ]; then
          issue_key="$1"
          shift
        else
          error "Unknown option: $1"
          usage
        fi
        ;;
    esac
  done
}

prompt_for_missing_fields() {
  # Prompt for Project if not set
  if [ -z "$project" ]; then
    info "Enter the Project Key:"
    read -r project
    if [ -z "$project" ]; then
      error "Project is a required field. Aborting."
      exit 1
    fi
  fi

  # Prompt for Issue Type if not set
  if [ -z "$issue_type" ]; then
    info "Enter the Issue Type (e.g., Story, Task, Bug) [default: Task]:"
    read -r issue_type
    if [ -z "$issue_type" ]; then
      issue_type="Task"
      info "Using default: Task"
    fi
  fi

  # Prompt for Summary if not set
  if [ -z "$summary" ]; then
    info "Enter the issue summary (title):"
    read -r summary
    if [ -z "$summary" ]; then
      error "Summary is a required field. Aborting."
      exit 1
    fi
  fi

  # Prompt for Description if not provided via any means
  if [ -z "$description" ] && [ -z "$description_file" ]; then
    info "Enter issue description (finish with Ctrl-D on a new line):"
    description=$(cat)
  fi
}

build_payload() {
  local is_update="$1"
  local payload_file
  payload_file=$(mktemp)

  # Handle description from file or argument
  local final_description=""
  local description_json_arg=""
  
  if [ -n "$description_file" ]; then
    final_description="$(cat "$description_file")"
  else
    final_description="$description"
  fi
  
  # Convert based on flags using md2jira script
  if [ -n "$final_description" ]; then
    if [ "$format_flag" = "--no-convert" ]; then
      # Send as-is without any conversion (as string)
      description_json_arg="--arg"
    elif [ "$format_flag" = "--adf" ]; then
      # Convert to ADF format for Jira Cloud using md2jira
      info "Converting Markdown to ADF format (Jira Cloud)..."
      final_description=$(echo "$final_description" | "$DIR/../bin/md2jira" --adf 2>/dev/null)
      description_json_arg="--argjson"
    elif [ "$format_flag" = "--wiki" ]; then
      # Convert to Wiki Markup for Jira Server using md2jira
      info "Converting Markdown to Wiki Markup (Jira Server)..."
      final_description=$(echo "$final_description" | "$DIR/../bin/md2jira" --wiki 2>/dev/null)
      description_json_arg="--arg"
    else
      # Auto-detect format based on JIRA_HOST
      if [[ "$JIRA_HOST" =~ atlassian\.net ]]; then
        info "Auto-detected: ADF format ( Jira Cloud)"
        final_description=$(echo "$final_description" | "$DIR/../bin/md2jira" --adf 2>/dev/null)
        description_json_arg="--argjson"
      else
        info "Auto-detected: Wiki Markup format (Jira Server)"
        final_description=$(echo "$final_description" | "$DIR/../bin/md2jira" --wiki 2>/dev/null)
        description_json_arg="--arg"
      fi
    fi
    
    # Check description length and warn if too long
    local desc_length
    if [ "$description_json_arg" = "--argjson" ]; then
      # For ADF JSON, the actual content is longer
      desc_length=$(echo "$final_description" | wc -c | tr -d ' ')
    else
      desc_length=${#final_description}
    fi
    
    if [ "$desc_length" -gt "$max_description_length" ]; then
      error "Description is too long ($desc_length characters). Jira limit is approximately $max_description_length characters."
      error "Please reduce the description length or consider using attachments for detailed content."
      exit 1
    fi
  fi

  # Build the payload using jq with proper argument types
  if [ "$is_update" = "true" ]; then
    # For updates, only include fields that were explicitly provided
    jq -n \
      --arg project "$project" \
      --arg issue_type "$issue_type" \
      --arg summary "$summary" \
      $description_json_arg description "$final_description" \
      --arg assignee "$assignee" \
      --arg reporter "$reporter" \
      --arg epic "$epic" \
      --arg priority "$priority" \
      --arg link_issue "$link_issue" \
      '
      { fields: {} }
      | if $project != "" then .fields.project = { key: $project } else . end
      | if $issue_type != "" then .fields.issuetype = { name: $issue_type } else . end
      | if $summary != "" then .fields.summary = $summary else . end
      | if $description != "" then .fields.description = $description else . end
      | if $assignee != "" then .fields.assignee = { name: $assignee } else . end
      | if $reporter != "" then .fields.reporter = { name: $reporter } else . end
      | if $epic != "" then .fields.customfield_10100 = $epic else . end
      | if $priority != "" then .fields.priority = { name: $priority } else . end
      | if $link_issue != "" then .update.issuelinks[0] = { add: { type: { name: "Relates" }, outwardIssue: { key: $link_issue } } } else . end
      ' > "$payload_file"
  else
    # For new issues, include all required fields
    jq -n \
      --arg project "$project" \
      --arg issue_type "$issue_type" \
      --arg summary "$summary" \
      $description_json_arg description "$final_description" \
      --arg assignee "$assignee" \
      --arg reporter "$reporter" \
      --arg epic "$epic" \
      --arg priority "$priority" \
      --arg link_issue "$link_issue" \
      '
      {
        fields: {
          project: { key: $project },
          issuetype: { name: $issue_type },
          summary: $summary,
          description: $description
        }
      }
      | if $assignee != "" then .fields.assignee = { name: $assignee } else . end
      | if $reporter != "" then .fields.reporter = { name: $reporter } else . end
      | if $epic != "" then .fields.customfield_10100 = $epic else . end
      | if $priority != "" then .fields.priority = { name: $priority } else . end
      | if $link_issue != "" then .update.issuelinks[0] = { add: { type: { name: "Relates" }, outwardIssue: { key: $link_issue } } } else . end
      ' > "$payload_file"
  fi
  
  echo "$payload_file"
}

main() {
  parse_args "$@"
  
  # Load properties from JSON file if provided
  load_from_json_file
  
  # For new issues, prompt for any missing required fields
  if [ -z "$issue_key" ]; then
    prompt_for_missing_fields
  fi

  local payload_file
  if [ -z "$issue_key" ]; then
    payload_file=$(build_payload "false")
    info "Creating new issue in project $project..."
    "$DIR/../bin/jira" POST /issue --data "$payload_file"
  else
    payload_file=$(build_payload "true")
    info "Updating issue $issue_key..."
    "$DIR/../bin/jira" PUT "/issue/$issue_key" --data "$payload_file"
  fi

  # Cleanup
  rm -f "$payload_file"
}

# --- Main Execution ---
main "$@"
