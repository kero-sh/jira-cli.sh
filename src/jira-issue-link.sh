#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

usage() {
    cat <<EOF
Uso: $(basename "$0") <inward_issue> <outward_issue> [options]

Descripción:
  Crea un enlace entre dos issues en Jira.

Opciones:
  --type <type>      Tipo de enlace (por defecto: "Relates")
  -h, --help         Muestra esta ayuda

Ejemplos:
  $(basename "$0") ABC-123 ABC-456
  $(basename "$0") ABC-123 ABC-456 --type Blocks
EOF
    exit 0
}

[ -z "$in" ] && in="$1"
[ -z "$out" ] && out="$2"
shift 2

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      usage
      ;;
    --type)
      type=$2
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

function update_payload() {
  local payload="$1"
  local key="$2"
  local value="$3"
  if [ -n "$value" ]; then
    jq --arg value "$value" "$key = \$value" $payload > $payload.tmp && mv $payload.tmp $payload
  fi
}

payload=$(mktemp)
cat cat <<< "
"issuelinks": [
  {
    "type": {
      "name": "Relates"
    },
    "outwardIssue": {
      "key": "ABC-123"
    }
  }
]" > $payload

[ -n "$type" ]  && update_payload $payload ".issuelinks[0].type.name" "$type"
[ -n "$in" ]    && update_payload $payload ".issuelinks[0].inwardIssue.key" "$in"
[ -n "$out" ]   && update_payload $payload ".issuelinks[0].outwardIssue.key" "$out"


"$DIR/jira" POST /issueLink --data "$payload"
