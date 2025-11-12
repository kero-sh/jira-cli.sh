#!/bin/bash
# Output formatting functions for jira CLI
# Handles json, csv, table, yaml, and markdown output formats

# Format and output the API response based on the specified output format
# Arguments:
#   $1 - RESPONSE: The JSON response from the API
#   $2 - OUTPUT: The output format (json|csv|table|yaml|md)
#   $3 - ENDPOINT: The API endpoint (used for format detection)
#   $4 - IS_SINGLE_OBJECT: true/false indicating if response is a single object
#   $5 - JIRA_HOST: Jira host URL (for CSV export)
#   $6 - CSV_EXPORT_MODE: CSV export mode (all|current)
#   $7 - AUTH_HEADER: Authorization header (for CSV export)
format_output() {
    local RESPONSE="$1"
    local OUTPUT="$2"
    local ENDPOINT="$3"
    local IS_SINGLE_OBJECT="$4"
    local JIRA_HOST="$5"
    local CSV_EXPORT_MODE="$6"
    local AUTH_HEADER="$7"

    case "$OUTPUT" in
        json)
            echo "$RESPONSE" | jq
            ;;
        csv)
            format_csv "$RESPONSE" "$ENDPOINT" "$IS_SINGLE_OBJECT" "$JIRA_HOST" "$CSV_EXPORT_MODE" "$AUTH_HEADER"
            ;;
        table)
            format_table "$RESPONSE" "$ENDPOINT" "$IS_SINGLE_OBJECT"
            ;;
        yaml)
            echo "$RESPONSE" | yq -P
            ;;
        md)
            format_markdown "$RESPONSE" "$ENDPOINT" "$IS_SINGLE_OBJECT"
            ;;
        *)
            echo "$RESPONSE"
            ;;
    esac
}

# Format response as CSV
format_csv() {
    local RESPONSE="$1"
    local ENDPOINT="$2"
    local IS_SINGLE_OBJECT="$3"
    local JIRA_HOST="$4"
    local CSV_EXPORT_MODE="$5"
    local AUTH_HEADER="$6"

    # Special format for transitions
    if echo "$RESPONSE" | jq -e 'has("transitions")' > /dev/null 2>&1; then
        echo "ID,Name,To Status,Status Category"
        echo "$RESPONSE" | jq -r '.transitions[] | [.id, .name, .to.name, .to.statusCategory.name] | @csv'
        return 0
    fi
    
    # CSV export identical to Jira Cloud if it's a search (/search?jql=...)
    if [[ "$ENDPOINT" =~ ^/search\? ]]; then
        export_jira_cloud_csv "$ENDPOINT" "$JIRA_HOST" "$CSV_EXPORT_MODE" "$AUTH_HEADER"
        return 0
    fi

    # Generic CSV format based on endpoint pattern
    if [[ "$IS_SINGLE_OBJECT" == "true" ]]; then
        # Single object
        echo "$RESPONSE" | jq -r '((keys_unsorted) as $k | $k, (map(.))) | @csv'
    else
        # List of objects - detect if there's a wrapper (like .issues)
        if echo "$RESPONSE" | jq -e 'has("issues")' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r 'if .issues | length > 0 then ((.issues[0] | keys_unsorted) as $h | $h, (.issues[] | [.[]])) | @csv else empty end'
        elif echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r 'if length > 0 then ((.[0] | keys_unsorted) as $h | $h, (.[ ] | [.[]])) | @csv else empty end'
        else
            echo "$RESPONSE" | jq -r '((keys_unsorted) as $k | $k, (map(.))) | @csv'
        fi
    fi
}

# Export CSV in Jira Cloud format
export_jira_cloud_csv() {
    local ENDPOINT="$1"
    local JIRA_HOST="$2"
    local CSV_EXPORT_MODE="$3"
    local AUTH_HEADER="$4"

    # Extract the jql= value from the endpoint
    JQL_RAW="${ENDPOINT#*jql=}"
    JQL_RAW="${JQL_RAW%%&*}"
    # URL-encode with jq
    JQL_ENC=$(jq -rn --arg s "$JQL_RAW" '$s|@uri')

    case "$CSV_EXPORT_MODE" in
        all|ALL)
            EXPORT_KIND="searchrequest-csv-all-fields"
            ;;
        current|CURRENT)
            EXPORT_KIND="searchrequest-csv-current-fields"
            ;;
        *)
            echo "Invalid csv-export type: $CSV_EXPORT_MODE (use: all|current)" >&2
            exit 1
            ;;
    esac

    # Use high tempMax to get as much as possible (server may apply limits)
    EXPORT_URL="$JIRA_HOST/sr/jira.issueviews:$EXPORT_KIND/temp/SearchRequest.csv?jqlQuery=$JQL_ENC&tempMax=10000"
    
    # Use execute_curl if available, otherwise fall back to curl directly
    if type execute_curl >/dev/null 2>&1; then
        execute_curl --request GET -H "Accept: text/csv" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$EXPORT_URL"
    else
        curl --compressed --silent --location --request GET -H "Accept: text/csv" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$EXPORT_URL"
    fi
}

# Format response as table
format_table() {
    local RESPONSE="$1"
    local ENDPOINT="$2"
    local IS_SINGLE_OBJECT="$3"

    # Special format for transitions
    if echo "$RESPONSE" | jq -e 'has("transitions")' > /dev/null 2>&1; then
        {
            echo -e "ID\tName\tTo Status\tStatus Category";
            echo "$RESPONSE" | jq -r '.transitions[] | [.id, .name, .to.name, .to.statusCategory.name] | @tsv' ;
        } | column -t -s $'\t'
        return 0
    fi
    
    # Generic table format based on endpoint pattern
    if [[ "$IS_SINGLE_OBJECT" == "true" ]]; then
        # Single object
        echo "$RESPONSE" | jq -r '(keys_unsorted | join("\t")), (to_entries | map(.value | tostring) | join("\t"))'
    else
        # List of objects - detect if there's a wrapper (like .issues)
        if echo "$RESPONSE" | jq -e 'has("issues")' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r 'if .issues | length > 0 then (.issues[0] | keys_unsorted | join("\t")), (.issues[] | to_entries | map(.value | tostring) | join("\t")) else empty end'
        elif echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r 'if length > 0 then (.[0] | keys_unsorted | join("\t")), (.[] | to_entries | map(.value | tostring) | join("\t")) else empty end'
        else
            echo "$RESPONSE" | jq -r '(keys_unsorted | join("\t")), (to_entries | map(.value | tostring) | join("\t"))'
        fi
    fi
}

# Format response as markdown
format_markdown() {
    local RESPONSE="$1"
    local ENDPOINT="$2"
    local IS_SINGLE_OBJECT="$3"

    # Special format for transitions
    if echo "$RESPONSE" | jq -e 'has("transitions")' > /dev/null 2>&1; then
        echo "| ID | Name | To Status | Status Category |"
        echo "|---|---|---|---|"
        echo "$RESPONSE" | jq -r '.transitions[] | "|" + .id + "|" + .name + "|" + .to.name + "|" + .to.statusCategory.name + "|"'
        return 0
    fi

    # Generic markdown format based on endpoint pattern
    if [[ "$IS_SINGLE_OBJECT" == "true" ]]; then
        # Single object
        echo "$RESPONSE" | jq -r '"| Key | Value |", "|---|---|", (to_entries | map("| " + .key + " | " + (.value | tostring) + " |") | join("\n"))'
    else
        # List of objects - detect if there's a wrapper (like .issues)
        if echo "$RESPONSE" | jq -e 'has("issues")' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r 'if .issues | length > 0 then "| " + (.issues[0] | keys_unsorted | join(" | ")) + " |", "|" + (.issues[0] | keys_unsorted | map("---") | join("|")) + "|", (.issues[] | "| " + (to_entries | map(.value | tostring) | join(" | ")) + " |") else "No data" end'
        elif echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
            echo "$RESPONSE" | jq -r 'if length > 0 then "| " + (.[0] | keys_unsorted | join(" | ")) + " |", "|" + (.[0] | keys_unsorted | map("---") | join("|")) + "|", (.[] | "| " + (to_entries | map(.value | tostring) | join(" | ")) + " |") else "No data" end'
        else
            echo "$RESPONSE" | jq -r '"| Key | Value |", "|---|---|", (to_entries | map("| " + .key + " | " + (.value | tostring) + " |") | join("\n"))'
        fi
    fi
}

# Detect if the endpoint should return a list or a single object
# Common patterns in REST APIs:
# - /resource -> list
# - /resource/{id} -> single object
# - /resource?query -> list (search)
# - /resource/{id}/subresource -> list
# - /resource/{id}/subresource/{id} -> single object
detect_single_object() {
    local ENDPOINT="$1"
    local TRANSITION_TARGET_SET="$2"
    
    local IS_SINGLE_OBJECT=false

    # If the endpoint ends with a specific ID (numbers, codes like ABC-123, etc.)
    if [[ "$ENDPOINT" =~ /[A-Z]+-[0-9]+$ ]] || [[ "$ENDPOINT" =~ /[0-9]+$ ]]; then
        IS_SINGLE_OBJECT=true
    # If the endpoint is for a specific resource without query parameters
    elif [[ "$ENDPOINT" =~ ^/[^/]+/[^/?]+$ ]] && [[ ! "$ENDPOINT" =~ \? ]]; then
        IS_SINGLE_OBJECT=true
    fi

    if [[ "$TRANSITION_TARGET_SET" == "true" ]]; then
        IS_SINGLE_OBJECT=true
    fi

    echo "$IS_SINGLE_OBJECT"
}
