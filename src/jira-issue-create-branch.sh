#!/bin/bash

DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";
source $DIR/../lib/helpers.sh

if ! issue=$($DIR/jira-issue.sh --fields '{"key": .key,"summary": .fields.summary,"type": (.fields.issuetype.name // ""),"priority": (.fields.priority.name // "")}' "$1"); then
    echo "No se pudo recuperar el issue $1"
    exit 1
fi

if [ -z "$issue" ] || [ "$issue" = "null" ]; then
    echo "No se encontró el issue $1"
    exit 1
fi
issue_key=$(echo $issue | jq -r '.key')
issue_summary=$(echo $issue | jq -r '.summary')
issue_type=$(echo $issue | jq -r '.type // empty')
issue_priority=$(echo $issue | jq -r '.priority // empty')

if [ -z "$issue_key" ] || [ "$issue_key" = "null" ]; then
    echo "No se encontró el issue $1"
    exit 1
fi

normalize_for_match() {
    printf '%s' "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT | tr '[:upper:]' '[:lower:]'
}

issue_type_norm=$(normalize_for_match "$issue_type")
issue_priority_norm=$(normalize_for_match "$issue_priority")

critical_priorities="blocker critical highest high p0 p1 urgente sev-1 sev1 severidad-1"
case "$issue_type_norm" in
    bug|defect|error|bugfix)
        if [[ " $critical_priorities " == *" $issue_priority_norm "* ]]; then
            branch_prefix="hotfix"
        else
            branch_prefix="bugfix"
        fi
        ;;
    incident|incidente|production-incident|major-incident|problema-produccion)
        branch_prefix="hotfix"
        ;;
    task|tarea|sub-task|subtask|story-task|technical-task)
        branch_prefix="task"
        ;;
    chore|maintenance|maintenance-task|mantenimiento|support-task|operacion)
        branch_prefix="chore"
        ;;
    story|user-story|feature|improvement|enhancement|epic|historia|mejora|feature-request)
        branch_prefix="feature"
        ;;
    *)
        if [[ "$issue_type_norm" == *"bug"* || "$issue_type_norm" == *"error"* ]]; then
            if [[ " $critical_priorities " == *" $issue_priority_norm "* ]]; then
                branch_prefix="hotfix"
            else
                branch_prefix="bugfix"
            fi
        elif [[ "$issue_type_norm" == *"task"* ]]; then
            branch_prefix="task"
        elif [[ "$issue_type_norm" == *"mainten"* || "$issue_type_norm" == *"oper"* ]]; then
            branch_prefix="chore"
        else
            branch_prefix="feature"
        fi
        ;;
esac

branch_prefix=${branch_prefix:-feature}

branch_slug=$(
    printf '%s' "$issue_summary" \
    | iconv -f UTF-8 -t ASCII//TRANSLIT \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | tr ' ' '-' \
    | tr -cd '[:alnum:]-' \
    | tr -s '-' \
    | sed 's/^-//;s/-$//'
)

[ -z "$branch_slug" ] && branch_slug="sin-descripcion"

max_branch_len=63
base_prefix="$branch_prefix/$issue_key"
base_prefix_with_dash="$base_prefix-"
allowed_slug_len=$((max_branch_len - ${#base_prefix_with_dash}))

if (( allowed_slug_len <= 0 )); then
    branch_name="$base_prefix"
else
    branch_slug="${branch_slug:0:allowed_slug_len}"
    branch_slug="${branch_slug%-}"
    if [ -z "$branch_slug" ]; then
        branch_slug="sin-descripcion"
        branch_slug="${branch_slug:0:allowed_slug_len}"
        branch_slug="${branch_slug%-}"
        [ -z "$branch_slug" ] && branch_slug="x"
    fi
    branch_name="$base_prefix-$branch_slug"
fi

if (( ${#branch_name} > max_branch_len )); then
    branch_name="${branch_name:0:max_branch_len}"
    branch_name="${branch_name%-}"
    branch_name="${branch_name%/}"
    [ -z "$branch_name" ] && branch_name="${branch_prefix:0:max_branch_len}"
fi

git checkout -b "$branch_name"
