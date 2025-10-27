#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

query="$1"
if [[ -z "$query" ]]; then
    echo "Uso: $0 '<jql_query>'"
    echo "Ejemplo: $0 'project=PROY AND status=Open'"
    exit 1
fi

# Simple URL encoding for spaces and special characters
query=$(echo "$query" | sed 's/ /%20/g' | sed 's/=/%3D/g' | sed 's/&/%26/g')

$DIR/jira.sh GET "search?jql=$query" | jq '
    .issues[] | {
        key: .key,
        summary: .fields.summary,
        status: .fields.status.name,
        assignee: (.fields.assignee | if . then .displayName else "Unassigned" end),
        created: .fields.created,
        updated: .fields.updated
    }
' | jq -s '.'