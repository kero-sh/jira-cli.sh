#!/bin/bash
# Search and endpoint building functions for jira CLI
# Handles resource endpoint construction and JQL query building

# Build API endpoint from simplified command syntax
# Arguments: $1 - resource (project, issue, search, etc.)
#            $2 - identifier (optional resource ID or search term)
#            $3 - SHOW_TRANSITIONS (true/false)
build_endpoint() {
    local resource="$1"
    local identifier="$2"
    local SHOW_TRANSITIONS="${3:-false}"
    local ENDPOINT=""
    local METHOD="GET"
    local CREATE_MODE=false

    case "$resource" in
        project|projects)
            if [[ -n "$identifier" ]]; then
                ENDPOINT="/project/$identifier"
            else
                ENDPOINT="/project"
            fi
            ;;
        issue|issues)
            if [[ -n "$identifier" ]]; then
                if [[ "$SHOW_TRANSITIONS" == "true" ]]; then
                    ENDPOINT="/issue/$identifier/transitions"
                else
                    ENDPOINT="/issue/$identifier"
                fi
            else
                ENDPOINT="/search?jql=assignee=currentUser()"
            fi
            ;;
        search)
            if [[ -n "$identifier" ]]; then
                # If identifier already contains JQL, use it directly
                if [[ "$identifier" =~ ^jql= ]]; then
                    ENDPOINT="/search?$identifier"
                else
                    ENDPOINT="/search?jql=$identifier"
                fi
            else
                ENDPOINT="/search?jql=assignee=currentUser()"
            fi
            ;;
        create)
            # Issue creation
            ENDPOINT="/issue"
            METHOD="POST"
            CREATE_MODE=true
            ;;
        priority|priorities)
            ENDPOINT="/priority"
            ;;
        status|statuses)
            ENDPOINT="/status"
            ;;
        issuetype|issuetypes)
            ENDPOINT="/issuetype"
            ;;
        field|fields)
            ENDPOINT="/field"
            ;;
        resolution|resolutions)
            ENDPOINT="/resolution"
            ;;
        component|components)
            if [[ -n "$identifier" ]]; then
                ENDPOINT="/component/$identifier"
            else
                echo "Error: component requires an ID" >&2
                return 1
            fi
            ;;
        version|versions)
            if [[ -n "$identifier" ]]; then
                ENDPOINT="/version/$identifier"
            else
                echo "Error: version requires an ID" >&2
                return 1
            fi
            ;;
        *)
            echo "Unrecognized resource: $resource" >&2
            echo "Available resources: project, issue, search, priority, status, user, issuetype, field, resolution, component, version" >&2
            return 1
            ;;
    esac

    # Return as JSON for easy parsing
    jq -n \
        --arg endpoint "$ENDPOINT" \
        --arg method "$METHOD" \
        --argjson create_mode "$CREATE_MODE" \
        '{endpoint: $endpoint, method: $method, create_mode: $create_mode}'
}

# Build full request URL from endpoint
# Arguments: $1 - ENDPOINT
#            $2 - JIRA_HOST
#            $3 - JIRA_API_VERSION
build_request_url() {
    local ENDPOINT="$1"
    local JIRA_HOST="$2"
    local JIRA_API_VERSION="$3"
    local REQUEST_URL=""

    # Robust URL construction: if endpoint already includes /rest/api or is a complete URL,
    # don't prepend /rest/api/${JIRA_API_VERSION} again
    if [[ "$ENDPOINT" =~ ^https?:// ]]; then
        # Complete endpoint (includes protocol and host)
        REQUEST_URL="$ENDPOINT"
    elif [[ "$ENDPOINT" =~ ^/rest/ ]]; then
        # Endpoint already includes /rest/... prefix (e.g. /rest/api/2/...)
        REQUEST_URL="$JIRA_HOST$ENDPOINT"
    else
        # Short endpoint (e.g. /user/search, /issue/ABC-123, /search?...)
        REQUEST_URL="$JIRA_HOST/rest/api/${JIRA_API_VERSION}$ENDPOINT"
    fi

    echo "$REQUEST_URL"
}

# Encode JQL query for URL
encode_jql() {
    local jql="$1"
    jq -rn --arg s "$jql" '$s|@uri'
}

# Build JQL for common queries
# Arguments: $1 - query_type (assigned|created|resolved|status)
#            $2 - value (user, status value, etc.)
build_common_jql() {
    local query_type="$1"
    local value="$2"

    case "$query_type" in
        assigned)
            if [[ "$value" == "me" || "$value" == "current" ]]; then
                echo "assignee=currentUser()"
            else
                echo "assignee=\"$value\""
            fi
            ;;
        created)
            if [[ "$value" == "me" || "$value" == "current" ]]; then
                echo "reporter=currentUser()"
            else
                echo "reporter=\"$value\""
            fi
            ;;
        status)
            echo "status=\"$value\""
            ;;
        project)
            echo "project=\"$value\""
            ;;
        priority)
            echo "priority=\"$value\""
            ;;
        *)
            echo "$value"
            ;;
    esac
}
