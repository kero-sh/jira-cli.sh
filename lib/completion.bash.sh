#!/bin/bash
# Bash completion for jira CLI
# Source this file to enable tab completion in bash

_jira_completion() {
    local cur prev opts resources
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Available resources
    resources="project projects issue issues search create priority priorities status statuses user users issuetype issuetypes field fields resolution resolutions component components version versions"

    # HTTP methods
    methods="GET POST PUT"

    # Options
    opts="--data --token --host --output --csv-export --transitions --to --help --shell --project --summary --description --type --assignee --reporter --priority --epic --link-issue --template --dry-run"

    # Output formats
    formats="json csv table yaml md"

    # If we're at the first position, suggest resources or HTTP methods
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${resources} ${methods} ${opts}" -- ${cur}) )
        return 0
    fi

    # Completion based on previous word
    case "${prev}" in
        --output)
            COMPREPLY=( $(compgen -W "${formats}" -- ${cur}) )
            return 0
            ;;
        user|users)
            local user_subs="get search activity -h --help"
            COMPREPLY=( $(compgen -W "${user_subs}" -- ${cur}) )
            return 0
            ;;
        create)
            # Suggest creation flags
            local create_flags="--project --summary --description --type --assignee --reporter --priority --epic --link-issue --template --data --output"
            COMPREPLY=( $(compgen -W "${create_flags}" -- ${cur}) )
            return 0
            ;;
        --shell)
            COMPREPLY=( $(compgen -W "bash zsh" -- ${cur}) )
            return 0
            ;;
        --token|--host|--data|--to)
            # No autocomplete for these (free-form values)
            return 0
            ;;
        search)
            # Suggest some common JQL examples
            local jql_examples="'assignee=currentUser()' 'project=' 'status=Open' 'priority=High'"
            COMPREPLY=( $(compgen -W "${jql_examples}" -- ${cur}) )
            return 0
            ;;
        *)
            # If previous word is a resource, suggest options
            if [[ " ${resources} " =~ " ${prev} " ]]; then
                COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
                return 0
            fi
            ;;
    esac

    # Default completion with options
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
}

# Register completion function
complete -F _jira_completion jira

# Installation instructions:
# 1. Save this script as ~/.jira-completion.bash
# 2. Add this line to your ~/.bashrc:
#    source ~/.jira-completion.bash
# 3. Reload your shell: source ~/.bashrc
