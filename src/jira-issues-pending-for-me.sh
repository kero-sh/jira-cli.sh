#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

usage() {
    cat <<EOF
Uso: $(basename "$0") [options]

Descripción:
  Busca todos los issues asignados al usuario actual que no están en estado Done.

Opciones:
  -h, --help         Muestra esta ayuda

Ejemplos:
  $(basename "$0")
EOF
    exit 0
}

# Check for help flag
if [[ "$1" =~ ^(-h|--help)$ ]]; then
    usage
fi

$DIR/jira GET "/search?jql=assignee=currentUser()%20AND%20statusCategory!=Done&fields=key,summary,status"