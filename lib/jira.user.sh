#!/bin/bash
# User management and search functions for jira CLI
# Handles user search, profile retrieval, and activity tracking

# Build endpoint for user-related operations
# Arguments: $1 - USER_MODE (get|search|activity)
#            $2 - identifier (email/username/accountId/search term)
#            $3 - JIRA_API_VERSION
build_user_endpoint() {
    local USER_MODE="$1"
    local identifier="$2"
    local JIRA_API_VERSION="$3"
    local param_user
    
    if [[ "$JIRA_API_VERSION" == "2" ]]; then
        param_user="username"
    else
        param_user="query"
    fi

    case "$USER_MODE" in
        get)
            # Always resolve via search to support email/username/accountId
            echo "/user/search?${param_user}=${identifier}"
            ;;
        search)
            if [[ -n "$identifier" ]]; then
                echo "/user/search?${param_user}=${identifier}"
            else
                echo "ERROR: 'jira user search' requires a search term" >&2
                return 1
            fi
            ;;
        activity)
            # Will be handled separately with multi-step logic
            echo "/user"
            ;;
        *)
            # Compatibility: 'jira user <text>' => search
            if [[ -n "$identifier" ]]; then
                echo "/user/search?${param_user}=${identifier}"
            else
                echo "/user/search?${param_user}="
            fi
            ;;
    esac
}

# Resolve user by search term (email/username/accountId)
# Returns the chosen user ID or name based on API version
resolve_user() {
    local search_term="$1"
    local search_response="$2"
    local JIRA_API_VERSION="$3"
    
    if [[ "$JIRA_API_VERSION" == "2" ]]; then
        printf '%s' "$search_response" | jq -r --arg term "$search_term" '
            if (type=="array" and length>0) then
                ( (map(select(((.emailAddress? // "")|ascii_downcase) == ($term|ascii_downcase)
                            or ((.name? // "")|ascii_downcase) == ($term|ascii_downcase)
                            or ((.displayName? // "")|ascii_downcase) == ($term|ascii_downcase))) | .[0].name)
                  // .[0].name )
            else empty end'
    else
        printf '%s' "$search_response" | jq -r --arg term "$search_term" '
            if (type=="array" and length>0) then
                ( (map(select(((.emailAddress? // "")|ascii_downcase) == ($term|ascii_downcase)
                            or ((.name? // "")|ascii_downcase) == ($term|ascii_downcase)
                            or ((.displayName? // "")|ascii_downcase) == ($term|ascii_downcase)
                            or ((.accountId? // "")|ascii_downcase) == ($term|ascii_downcase))) | .[0].accountId)
                  // .[0].accountId )
            else empty end'
    fi
}

# Build JQL expression for user field
# Arguments: $1 - field name (reporter, assignee, etc.)
#            $2 - use_current_user (true/false)
#            $3 - chosen_id (accountId for v3)
#            $4 - chosen_name (username for v2)
#            $5 - JIRA_API_VERSION
build_user_jql() {
    local field="$1"
    local use_current_user="$2"
    local chosen_id="$3"
    local chosen_name="$4"
    local JIRA_API_VERSION="$5"
    
    if [[ "$use_current_user" == "true" ]]; then
        printf "%s = currentUser()" "$field"
    else
        if [[ "$JIRA_API_VERSION" == "2" ]]; then
            printf "%s = \"%s\"" "$field" "$chosen_name"
        else
            printf "%s in (accountId(\"%s\"))" "$field" "$chosen_id"
        fi
    fi
}

# Get total count for a JQL query
# Arguments: $1 - JQL query
#            $2 - JIRA_HOST
#            $3 - JIRA_API_VERSION
#            $4 - AUTH_HEADER
get_jql_total() {
    local jql="$1"
    local JIRA_HOST="$2"
    local JIRA_API_VERSION="$3"
    local AUTH_HEADER="$4"
    
    local jql_encoded
    jql_encoded=$(jq -rn --arg s "$jql" '$s|@uri')
    local url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$jql_encoded&maxResults=0&fields=none"
    
    local response
    if type execute_curl >/dev/null 2>&1; then
        response=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url")
    else
        response=$(curl --compressed --silent --location --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url")
    fi
    
    printf '%s' "$response" | jq -r '.total // 0'
}

# Fetch issue list for a JQL query with minimal fields
# Arguments: $1 - JQL query
#            $2 - scope (created/assigned)
#            $3 - category (ToDo/InProgress/Done)
#            $4 - JIRA_HOST
#            $5 - JIRA_API_VERSION
#            $6 - AUTH_HEADER
#            $7 - limit
#            $8 - epic_field_name
fetch_jql_list() {
    local jql="$1"
    local scope="$2"
    local category="$3"
    local JIRA_HOST="$4"
    local JIRA_API_VERSION="$5"
    local AUTH_HEADER="$6"
    local limit="$7"
    local epic_field="${8:-customfield_10014}"
    
    local jql_encoded
    jql_encoded=$(jq -rn --arg s "$jql" '$s|@uri')
    local url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$jql_encoded&maxResults=$limit&fields=key,summary,project,status,labels,components,${epic_field}"
    
    local response
    if type execute_curl >/dev/null 2>&1; then
        response=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url")
    else
        response=$(curl --compressed --silent --location --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url")
    fi
    
    printf '%s' "$response" | jq --arg scope "$scope" --arg cat "$category" --arg epic "$epic_field" '
        (.issues // []) | map({
            scope: $scope,
            category: $cat,
            key: .key,
            project: (.fields.project.key // ""),
            statusCategory: (.fields.status.statusCategory.name // ""),
            status: (.fields.status.name // ""),
            summary: (.fields.summary // ""),
            epic: (.fields[$epic] // ""),
            labels: ((.fields.labels // []) | join(",")),
            components: ((.fields.components // []) | map(.name) | join(","))
        })'
}

# Build date filters for activity queries
# Arguments: $1 - from_date (YYYY-MM-DD or empty)
#            $2 - to_date (YYYY-MM-DD or empty)
#            $3 - lookback (Nd format, e.g., 30d)
build_date_filters() {
    local from_date="$1"
    local to_date="$2"
    local lookback="${3:-30d}"
    
    local date_filter_created=""
    local date_filter_updated=""
    local date_filter_resolved=""
    
    if [[ -n "$from_date" || -n "$to_date" ]]; then
        if [[ -n "$from_date" ]]; then
            date_filter_created="created >= '$from_date'"
            date_filter_updated="updated >= '$from_date'"
            date_filter_resolved="resolutiondate >= '$from_date'"
        fi
        if [[ -n "$to_date" ]]; then
            date_filter_created+="${date_filter_created:+ AND }created <= '$to_date'"
            date_filter_updated+="${date_filter_updated:+ AND }updated <= '$to_date'"
            date_filter_resolved+="${date_filter_resolved:+ AND }resolutiondate <= '$to_date'"
        fi
    else
        date_filter_created="created >= -$lookback"
        date_filter_updated="updated >= -$lookback"
        date_filter_resolved="resolutiondate >= -$lookback"
    fi
    
    # Return as JSON for easy parsing
    jq -n \
        --arg created "$date_filter_created" \
        --arg updated "$date_filter_updated" \
        --arg resolved "$date_filter_resolved" \
        '{created: $created, updated: $updated, resolved: $resolved}'
}
