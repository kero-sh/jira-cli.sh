#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Source required libraries
source "$LIB_DIR/helpers.sh"
source "$LIB_DIR/markdown.sh"
source "$LIB_DIR/markdown_to_adf.sh"

# Variables
format=""
input_file=""

# Detect Jira type from JIRA_HOST
detect_jira_type() {
    if [ -z "$JIRA_HOST" ]; then
        echo "wiki"  # Default to wiki if no JIRA_HOST
        return
    fi
    
    # Check if it's Jira Cloud (contains atlassian.net)
    if [[ "$JIRA_HOST" =~ atlassian\.net ]]; then
        echo "adf"
    else
        echo "wiki"
    fi
}

# Show help message
show_help() {
    local detected_format=$(detect_jira_type)
    local jira_info=""
    
    if [ -n "$JIRA_HOST" ]; then
        jira_info=" (detected: $detected_format from $JIRA_HOST)"
    fi
    
    cat << EOF
md2jira - Convert Markdown to Jira format

USAGE:
    md2jira [OPTIONS] [FILE]
    cat file.md | md2jira
    md2jira < file.md

OPTIONS:
    --adf               Output in ADF format (Atlassian Document Format for Jira Cloud)
    --wiki              Output in Wiki Markup format (for Jira Server/Data Center)
    -h, --help          Show this help message

DESCRIPTION:
    Converts Markdown formatted text to Jira format.
    Auto-detects format based on \$JIRA_HOST environment variable$jira_info.
    Can read from a file, stdin, or pipe.

EXAMPLES:
    # Auto-detect format and convert from file
    md2jira README.md

    # Force ADF format (Jira Cloud)
    md2jira --adf document.md

    # Force Wiki Markup format (Jira Server)
    md2jira --wiki document.md

    # Convert from pipe
    cat document.md | md2jira --adf

    # Convert from stdin redirect
    md2jira --wiki < notes.md

FORMATS:
    --adf (Jira Cloud):
        Outputs JSON in Atlassian Document Format
        Use this for Jira Cloud instances (*.atlassian.net)
    
    --wiki (Jira Server):
        Outputs text in Wiki Markup format
        Use this for Jira Server/Data Center instances

WIKI MARKUP CONVERSIONS:
    # Heading 1           ->  h1. Heading 1
    ## Heading 2          ->  h2. Heading 2
    **bold** or __bold__  ->  *bold*
    \`code\`                ->  {{code}}
    [text](url)           ->  [text|url]
    ![alt](img.png)       ->  !img.png!
    - list item           ->  * list item
    - [x] task done       ->  * task done
    - [ ] task todo       ->  * task todo
    1. numbered item      ->  # numbered item
    > quote               ->  bq. quote
    \`\`\`code block\`\`\`      ->  {code}code block{code}

EOF
}

# Main function
main() {
    local input=""
    
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --adf)
                format="adf"
                shift
                ;;
            --wiki)
                format="wiki"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$input_file" ]; then
                    input_file="$1"
                else
                    error "Multiple files not supported: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Auto-detect format if not specified
    if [ -z "$format" ]; then
        format=$(detect_jira_type)
        if [ -n "$JIRA_HOST" ]; then
            info "Auto-detected format: $format (from JIRA_HOST: $JIRA_HOST)" >&2
        fi
    fi
    
    # Get input
    if [ -n "$input_file" ]; then
        # File argument provided
        if [ ! -f "$input_file" ]; then
            error "File not found: $input_file"
            exit 1
        fi
        input=$(cat "$input_file")
    elif [ -t 0 ]; then
        # stdin is a terminal (no pipe or redirect)
        error "No input provided. Use -h for help."
        exit 1
    else
        # stdin has data (pipe or redirect)
        input=$(cat)
    fi
    
    # Convert based on format
    case "$format" in
        adf)
            markdown_to_adf "$input"
            ;;
        wiki)
            markdown_to_jira "$input"
            ;;
        *)
            error "Unknown format: $format"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
