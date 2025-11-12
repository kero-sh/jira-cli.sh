#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

JIRA_FIELDS='{"key": .key,"summary": .fields.summary,"description": .fields.description,"status": .fields.status.name}'

function usage() {
    cat <<EOF
Uso: $(basename "$0") [options] [issue_key]

Descripción:
  Obtiene información detallada de un issue de JIRA.

Opciones:
  --ticket <issue_key>    Especifica la clave del issue de JIRA
  --fields <jsonpath>     Especifica los campos a mostrar en formato JSON
  --jsonpath=<jsonpath>   Alias para --fields
  --full                  Muestra todos los campos disponibles
  -h, --help              Muestra esta ayuda

Ejemplos:
  $(basename "$0") ABC-123
  $(basename "$0") --ticket ABC-123 --fields '.key, .summary'
  $(basename "$0") ABC-123 --full
EOF
    exit 0
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --ticket)
            ISSUE_KEY="$2"
            shift 2
            ;;
        --fields)
            JIRA_FIELDS="$2"
            shift 2
            ;;
        --jsonpath=*)
            JIRA_FIELDS="${1#*=}"
            shift
            ;;
        --full)
            JIRA_FIELDS=''
            shift
            ;;

        *)
            if [[ -z "$ISSUE_KEY" ]]; then
                ISSUE_KEY="$1";
                shift
            else
                echo "Opción desconocida: $1"
                exit 1
            fi
            
            ;;
    esac
done

JIRA_TOKEN="${JIRA_TOKEN:-$JIRA_API_TOKEN}"
JIRA_HOST="${JIRA_HOST:-$JIRA_API_HOST}"


# Variables de entorno requeridas: JIRA_TOKEN y JIRA_HOST
if [[ -z "$JIRA_TOKEN" || -z "$JIRA_HOST" ]]; then
    echo "Debes definir las variables de entorno JIRA_TOKEN y JIRA_HOST"
    exit 1
fi

if [[ -z "$ISSUE_KEY" ]]; then
    echo "Debes especificar la clave del issue de JIRA"
    usage
    exit 0
fi


temp=$(mktemp)

$DIR/jira.sh issue ${ISSUE_KEY} > $temp

#cat $temp

[ -n "$JIRA_FIELDS" ] && jq -r "$JIRA_FIELDS" < $temp || jq < $temp