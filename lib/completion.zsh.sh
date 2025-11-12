#!/bin/zsh
#compdef jira
# Zsh completion for jira CLI

_jira() {
    local context curcontext="$curcontext" state line
    typeset -A opt_args

    # Available resources
    local resources=(
        'project:Get project(s)'
        'projects:Get project(s)'
        'issue:Get issue(s)'
        'issues:Get issue(s)'
        'search:Search with JQL'
        'create:Create an issue'
        'priority:List priorities'
        'priorities:List priorities'
        'status:List statuses'
        'statuses:List statuses'
        'user:Search user(s)'
        'users:Search user(s)'
        'issuetype:List issue types'
        'issuetypes:List issue types'
        'field:List fields'
        'fields:List fields'
        'resolution:List resolutions'
        'resolutions:List resolutions'
        'component:Get component'
        'components:Get component'
        'version:Get version'
        'versions:Get version'
    )

    # HTTP methods
    local methods=(
        'GET:GET method'
        'POST:POST method'
        'PUT:PUT method'
    )

    # Output formats
    local formats=(
        'json:Formatted JSON'
        'csv:Comma-separated values'
        'table:Tabular format'
        'yaml:YAML format'
        'md:Markdown table'
    )

    _arguments -C \
        '1: :->command' \
        '2: :->identifier' \
        '--data[JSON data or file for POST/PUT]:json data:_files' \
        '--token[Authentication token]:token' \
        '--host[Jira URL]:host url' \
        '--output[Output format]:format:->formats' \
        '--csv-export[CSV export for search]:type:(all current)' \
        '--transitions[Show available transitions]' \
        '--to[Apply transition with ID]:transition id' \
        '--shell[Generate autocompletion]:shell:(bash zsh)' \
        '--project[Project key]:project key' \
        '--summary[Issue summary]:summary' \
        '--description[Issue description]:description' \
        '--type[Issue type]:issuetype' \
        '--assignee[Assigned to (username)]:username' \
        '--reporter[Reported by (username)]:username' \
        '--priority[Priority by name]:priority' \
        '--epic[Epic link key]:epic key' \
        '--link-issue[Issue key to link]:issue key' \
        '--template[Base JSON template]:file:_files' \
        '--dry-run[Print curl command without executing]' \
        '--help[Show help]' \
        '*: :->args'

    case $state in
        command)
            local all_commands=($resources $methods)
            _describe 'commands' all_commands 
            ;;
        identifier)
            case ${words[2]} in
                search)
                    local jql_examples=(
                        "'assignee=currentUser()':Issues assigned to you"
                        "'project=':Project issues"
                        "'status=Open':Open issues"
                        "'priority=High':High priority issues"
                    )
                    _describe 'jql examples' jql_examples
                    ;;
                project|projects)
                    _message "Project ID or name"
                    ;;
                issue|issues)
                    _message "Issue key (e.g. ABC-123)"
                    ;;
                user|users)
                    _values "user subcommands" \
                      'get:Full profile by email/username/accountId' \
                      'search:Search users by text' \
                      'activity:User activity summary'
                    ;;
                component|components|version|versions)
                    _message "Resource ID"
                    ;;
            esac
            ;;
        formats)
            _describe 'output formats' formats
            ;;
        args)
            _arguments \
                '--data[JSON data]:json data:_files' \
                '--token[Token]:token' \
                '--host[Host]:host url' \
                '--output[Format]:format:->formats' \
                '--csv-export[CSV export for search]:type:(all current)' \
                '--transitions[Show available transitions]' \
                '--to[Apply transition with ID]:transition id' \
                '--project[Project key]:project key' \
                '--summary[Issue summary]:summary' \
                '--description[Issue description]:description' \
                '--type[Issue type]:issuetype' \
                '--assignee[Assigned to (username)]:username' \
                '--reporter[Reported by (username)]:username' \
                '--priority[Priority by name]:priority' \
                '--epic[Epic link key]:epic key' \
                '--link-issue[Issue key to link]:issue key' \
                '--template[Base JSON template]:file:_files' \
                '--shell[Shell]:shell:(bash zsh)' \
                '--dry-run[Print curl command without executing]' \
                '--help[Help]'
            ;;
    esac
}

_jira "$@"

# Installation instructions:
# 1. Save this script as ~/.jira-completion.zsh
# 2. Add this line to your ~/.zshrc:
#    source ~/.jira-completion.zsh
# 3. Reload your shell: source ~/.zshrc
#
# Or alternatively, place the file in your completions directory:
# mkdir -p ~/.zsh/completions
# mv ~/.jira-completion.zsh ~/.zsh/completions/_jira
# echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
# echo 'autoload -U compinit && compinit' >> ~/.zshrc
