
#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

source $DIR/../lib/helpers.sh

usage() {
    cat <<EOF
Uso: $(basename "$0") <issue_key> [options]

Descripción:
  Transiciona un issue a través de múltiples estados hasta llegar a Done.

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
    error "Debes especificar un issue key"
    usage
fi

function next_transition() {
    local issue="$1"
    local transition="$2"
    x=$($DIR/jira.sh issue "$issue" --transitions 2>/dev/null)
    if [[ -z "$x" ]]; then        
        return 1
    fi
    tx=$(echo "$x" | jq --arg id "$transition" '.transitions[]|select(.id==$id)')
    [ -n "$tx" ] && info "transition to $transition" && $DIR/jira.sh issue "$issue" --transitions --to "$transition";
}

next_transition "$1" 21 && next_transition "$1" 31  && next_transition "$1" 41 && next_transition "$1" 51  &&  next_transition "$1" 71 && next_transition "$1" 81 && next_transition "$1" 61

$DIR/jira-issue.sh "$1"