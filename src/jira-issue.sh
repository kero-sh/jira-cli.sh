#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

JIRA_FIELDS='{"key": .key,"summary": .fields.summary,"description": .fields.description,"status": .fields.status.name}'

function usage() {
    echo "Uso: $0 [--ticket <issue_key>] [--fields <jsonpath>] [--user <username>] [--jsonpath=<jsonpath>] [--full] <issue_key>"
    echo "  --ticket <issue_key>    Especifica la clave del issue de JIRA"
    echo "  --fields <jsonpath>     Especifica los campos a mostrar en formato JSON"
    echo "  --jsonpath=<jsonpath>   Alias para --fields"
    echo "  --full                  Muestra todos los campos disponibles"
    exit 1
}


while [[ $# -gt 0 ]]; do
    case "$1" in
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