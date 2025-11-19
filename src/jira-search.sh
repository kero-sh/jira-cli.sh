#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

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

# URL encoding completo usando jq para manejar todos los caracteres especiales
query=$(jq -rn --arg s "$query" '$s|@uri')

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