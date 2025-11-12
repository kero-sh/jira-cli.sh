#!/bin/bash
# Issue management functions for jira CLI
# Handles issue creation, updates, and transitions

# Prepare payload for issue creation
# Uses flags, templates, and environment variables to build the payload
# Returns the path to a temporary file containing the final payload
prepare_create_payload() {
    local DATA="$1"
    local CREATE_TEMPLATE="$2"
    local CREATE_PROJECT="$3"
    local JIRA_PROJECT="$4"
    local CREATE_SUMMARY="$5"
    local CREATE_DESCRIPTION="$6"
    local CREATE_TYPE="$7"
    local CREATE_ASSIGNEE="$8"
    local CREATE_REPORTER="$9"
    local CREATE_PRIORITY="${10}"
    local CREATE_EPIC="${11}"
    local CREATE_LINK_ISSUE="${12}"
    local JIRA_API_VERSION="${13}"

    local base_file
    base_file=$(mktemp)

    # Determine base: --data (file or inline) > --template > skeleton
    if [[ -n "$DATA" ]]; then
        if [[ -f "$DATA" ]]; then
            cat "$DATA" > "$base_file"
        elif [[ "$DATA" == @* ]] && [[ -f "${DATA#@}" ]]; then
            cat "${DATA#@}" > "$base_file"
        else
            printf '%s' "$DATA" > "$base_file"
        fi
    elif [[ -n "$CREATE_TEMPLATE" && -f "$CREATE_TEMPLATE" ]]; then
        cat "$CREATE_TEMPLATE" > "$base_file"
    else
        printf '%s' '{"fields":{}}' > "$base_file"
    fi

    local final_file
    final_file=$(mktemp)

    # Prepare project priority: flag > JSON > env
    # We pass flag and env separately so flag overwrites and env only fills if missing in payload
    jq \
        --arg p_flag "$CREATE_PROJECT" \
        --arg p_env "$JIRA_PROJECT" \
        --arg s "$CREATE_SUMMARY" \
        --arg d "$CREATE_DESCRIPTION" \
        --arg t "$CREATE_TYPE" \
        --arg a "$CREATE_ASSIGNEE" \
        --arg r "$CREATE_REPORTER" \
        --arg pr "$CREATE_PRIORITY" \
        --arg e "$CREATE_EPIC" \
        --arg link "$CREATE_LINK_ISSUE" \
        --arg api_ver "$JIRA_API_VERSION" \
        '
        . as $o
        | .fields = (.fields // {})
        | (if $p_flag != "" then .fields.project.key = $p_flag
           elif (.fields.project.key // "") == "" and $p_env != "" then .fields.project.key = $p_env
           else . end)
        | (if $s   != "" then .fields.summary     = $s else . end)
        | (if $d   != "" then .fields.description = $d else . end)
        | (if $t   != "" then .fields.issuetype.name = $t else . end)
        | (if $a   != "" then .fields.assignee.name  = $a else . end)
        | (if $r   != "" then .fields.reporter.name  = $r else . end)
        | (if $pr  != "" then .fields.priority.name  = $pr else . end)
        | (if $e   != "" then .fields.customfield_10100 = $e else . end)
        | (if $link!= "" then .fields.issuelinks = (.fields.issuelinks // [])
                            | .fields.issuelinks[0].outwardIssue.key = $link else . end)
        # If using API v3 (Jira Cloud) and description is string, wrap in ADF automatically
        | (if ($api_ver == "3") and (.fields | has("description")) and ((.fields.description | type) == "string")
           then .fields.description = {
                  "type": "doc",
                  "version": 1,
                  "content": [
                    {"type": "paragraph", "content": [ {"type": "text", "text": .fields.description } ]}
                  ]
                }
           else . end)
        ' "$base_file" > "$final_file"

    echo "$final_file"
}

# Prepare payload for issue update (PUT)
# Converts plain text descriptions to ADF format for API v3
prepare_update_payload() {
    local DATA="$1"
    local JIRA_API_VERSION="$2"

    local _put_in_tmp=""
    local _put_src_file=""
    
    if [[ -f "$DATA" ]]; then
        _put_src_file="$DATA"
    else
        _put_in_tmp=$(mktemp)
        printf '%s' "$DATA" > "$_put_in_tmp"
        _put_src_file="$_put_in_tmp"
    fi
    
    local _put_final
    _put_final=$(mktemp)
    
    jq --arg api_ver "$JIRA_API_VERSION" '
        if ($api_ver == "3") and (.fields | has("description")) and ((.fields.description | type) == "string") then
            .fields.description = {
                "type": "doc",
                "version": 1,
                "content": [
                    {"type": "paragraph", "content": [ {"type": "text", "text": .fields.description } ]}
                ]
            }
        else . end' "$_put_src_file" > "$_put_final"
    
    echo "$_put_final"
}

# Handle transition response (204 no content)
# Generates a useful message when transition succeeds without response body
handle_transition_response() {
    local RESPONSE="$1"
    local TRANSITION_TARGET="$2"
    local ENDPOINT="$3"
    local identifier="$4"

    local TRANSITION_ISSUE_KEY="${identifier:-}"
    
    if [[ -z "$TRANSITION_ISSUE_KEY" ]]; then
        if [[ "$ENDPOINT" =~ /issue/([^/]+)/transitions$ ]]; then
            TRANSITION_ISSUE_KEY="${BASH_REMATCH[1]}"
        fi
    fi

    if [[ -z "$RESPONSE" ]]; then
        RESPONSE="{\"issue\":\"$TRANSITION_ISSUE_KEY\",\"transitionId\":\"$TRANSITION_TARGET\",\"status\":\"applied\"}"
    fi

    echo "$RESPONSE"
}
