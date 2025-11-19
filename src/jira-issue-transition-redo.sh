#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

usage() {
    cat <<EOF
Uso: $(basename "$0") <issue_key> [options]

Descripción:
  Re-abre un issue (transición 71) y luego lo mueve a Done.

Opciones:
  -h, --help         Muestra esta ayuda

Ejemplos:
  $(basename "$0") ABC-123
EOF
    exit 0
}

# Check for help flag
if [[ "$1" =~ ^(-h|--help)$ ]]; then
    usage
fi

if [[ -z "$1" ]]; then
    echo "Error: Debes especificar un issue key"
    usage
fi

$DIR/jira.sh issue "$1" --transitions --to 71 > /dev/null
$DIR/jira-issue-transition-done.sh "$1"