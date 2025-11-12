#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

usage() {
    cat <<EOF
Uso: $(basename "$0") [options] '<jql_query>'

Descripción:
  Busca issues en Jira usando una consulta JQL.

Opciones:
  -h, --help         Muestra esta ayuda

Ejemplos:
  $(basename "$0") 'project=PROY AND status=Open'
  $(basename "$0") 'assignee=currentUser() AND statusCategory!=Done'
EOF
    exit 0
}

# Check for help flag
if [[ "$1" =~ ^(-h|--help)$ ]]; then
    usage
fi

query="$1"
if [[ -z "$query" ]]; then
    echo "Uso: $0 '<jql_query>'"
    echo "Ejemplo: $0 'project=PROY AND status=Open'"
    exit 1
fi

# Simple URL encoding for spaces and special characters
query=$(echo "$query" | sed 's/ /%20/g' | sed 's/=/%3D/g' | sed 's/&/%26/g')

$DIR/jira GET "/search?jql=$query" | jq '
    .issues[] | {
        key: .key,
        summary: .fields.summary,
        status: .fields.status.name,
        assignee: (.fields.assignee | if . then .displayName else "Unassigned" end),
        created: .fields.created,
        updated: .fields.updated
    }
' | jq -s '.'