#!/bin/bash

# Help loader for jira CLI - loads manual pages from man/ directory

show_help_from_manual() {
    local command="$1"
    local manual_file="$DIR/../man/jira-${command}.md"
    
    # Handle command aliases
    case "$command" in
        "user"|"users")
            manual_file="$DIR/../man/jira-user.md"
            ;;
        "project"|"projects")
            manual_file="$DIR/../man/jira-project.md"
            ;;
        "issue"|"issues")
            manual_file="$DIR/../man/jira-issue.md"
            ;;
        "create")
            manual_file="$DIR/../man/jira-create.md"
            ;;
        "search")
            manual_file="$DIR/../man/jira-search.md"
            ;;
        "api")
            manual_file="$DIR/../man/jira-api.md"
            ;;
        "priority")
            manual_file="$DIR/../man/jira-priority.md"
            ;;
        "status")
            manual_file="$DIR/../man/jira-status.md"
            ;;
        "workflow")
            manual_file="$DIR/../man/jira-workflow.md"
            ;;
        "profile"|"myself")
            manual_file="$DIR/../man/jira-profile.md"
            ;;
        "issuetype")
            manual_file="$DIR/../man/jira-issuetype.md"
            ;;
        *)
            echo "Unknown command: $command" >&2
            echo "Available commands: create, user, project, issue, search, api, priority, status, workflow, profile, issuetype" >&2
            return 1
            ;;
    esac
    
    # Check if manual file exists
    if [[ ! -f "$manual_file" ]]; then
        echo "Manual file not found: $manual_file" >&2
        return 1
    fi
    
    # Load color functions
    if [[ -f "$DIR/../vendor/helpers.sh" ]]; then
        source "$DIR/../vendor/helpers.sh"
    fi
    
    # Display the manual file
    if command -v bat >/dev/null 2>&1; then
        # Use bat if available for syntax highlighting
        bat --style=plain --language=markdown "$manual_file"
    else
        # Use cat as fallback
        cat "$manual_file"
    fi
    
    return 0
}
