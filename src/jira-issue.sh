#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

JIRA_FIELDS='{"key": .key,"summary": .fields.summary,"description": .fields.description,"status": .fields.status.name}'
RESUME_MODE=false
FORMAT_OUTPUT="friendly"

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
  --resume               Muestra un resumen del issue con campos clave
  --format <format>       Formato de salida para --resume (friendly|json)
  -h, --help              Muestra esta ayuda

Ejemplos:
  $(basename "$0") ABC-123
  $(basename "$0") --ticket ABC-123 --fields '.key, .summary'
  $(basename "$0") ABC-123 --full
  $(basename "$0") ABC-123 --resume
  $(basename "$0") ABC-123 --resume --format json
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
        --resume)
            RESUME_MODE=true
            shift
            ;;
        --format)
            FORMAT_OUTPUT="$2"
            shift 2
            ;;
        --format=*)
            FORMAT_OUTPUT="${1#*=}"
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

# Handle resume mode
if [[ "$RESUME_MODE" == "true" ]]; then
    # Validate format option
    if [[ "$FORMAT_OUTPUT" != "friendly" && "$FORMAT_OUTPUT" != "json" ]]; then
        echo "Error: Formato no válido. Use 'friendly' o 'json'."
        exit 1
    fi
    
    # Extract the required fields using jq
    resume_data=$(jq -r '
    {
        titulo: .fields.summary // "N/A",
        desc: .fields.description // "N/A",
        reporter: .fields.reporter.displayName // "N/A",
        asignee: (.fields.assignee.displayName // "No asignado"),
        "fecha-creacion": .fields.created // "N/A",
        comentarios: (.fields.comment.comments | length // 0)
    }
    ' < "$temp")
    
    if [[ "$FORMAT_OUTPUT" == "json" ]]; then
        # Output JSON format
        echo "$resume_data" | jq .
    else
        # Output friendly format
        echo "=== Resumen del Issue ==="
        echo "Título: $(echo "$resume_data" | jq -r '.titulo')"
        echo "Descripción: $(echo "$resume_data" | jq -r '.desc' | head -c 100)$(if [ $(echo "$resume_data" | jq -r '.desc' | wc -c) -gt 100 ]; then echo "..."; fi)"
        echo "Reporter: $(echo "$resume_data" | jq -r '.reporter')"
        echo "Asignado a: $(echo "$resume_data" | jq -r '.asignee')"
        echo "Fecha de creación: $(echo "$resume_data" | jq -r '.\"fecha-creacion\"')"
        echo "Comentarios: $(echo "$resume_data" | jq -r '.comentarios')"
        echo "========================"
    fi
else
    # Original behavior for non-resume mode
    [ -n "$JIRA_FIELDS" ] && jq -r "$JIRA_FIELDS" < $temp || jq < $temp
fi

# Cleanup
rm -f "$temp"