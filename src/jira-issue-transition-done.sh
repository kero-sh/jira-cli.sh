#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

source $DIR/../lib/helpers.sh

usage() {
    cat <<EOF
Uso: $(basename "$0") <issue_key> [options]

Descripción:
  Transiciona un issue a través de múltiples estados hasta llegar a Done.
  Determina automáticamente el workflow del proyecto y calcula el camino
  de transiciones necesarias sin usar IDs hardcoded.

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

ISSUE_KEY="$1"

# Función para encontrar el estado Done objetivo
find_target_done_status() {
    local workflow="$1"
    local keywords=("done" "closed" "completado" "finalizado" "cerrado" "terminado")
    
    # Buscar por keywords en orden de prioridad
    for keyword in "${keywords[@]}"; do
        local found=$(echo "$workflow" | jq -r --arg kw "$keyword" \
            '.statuses[] | select(.statusCategory.key == "done" and (.name | ascii_downcase | contains($kw))) | .name' | head -1)
        [[ -n "$found" && "$found" != "null" ]] && echo "$found" && return 0
    done
    
    # Fallback: primer estado Done encontrado
    local fallback=$(echo "$workflow" | jq -r '.statuses[] | select(.statusCategory.key == "done") | .name' | head -1)
    [[ -n "$fallback" && "$fallback" != "null" ]] && echo "$fallback" && return 0
    
    return 1
}

# Función para obtener el camino de estados desde el actual hasta el objetivo
get_status_path() {
    local workflow="$1"
    local current="$2"
    local target="$3"
    
    echo "$workflow" | jq -r --arg curr "$current" --arg tgt "$target" '
        .statuses | map(.name) as $names |
        ($names | index($curr)) as $curr_idx |
        ($names | index($tgt)) as $tgt_idx |
        if $curr_idx == null or $tgt_idx == null then
            []
        elif $curr_idx >= $tgt_idx then
            []
        else
            $names[($curr_idx + 1):($tgt_idx + 1)]
        end | .[]
    '
}

# Función para ejecutar transición a un estado específico
execute_transition_to_status() {
    local issue="$1"
    local target_status="$2"
    
    local transitions=$($DIR/jira.sh issue "$issue" --transitions 2>/dev/null)
    if [[ -z "$transitions" ]]; then
        warn "No se pudieron obtener las transiciones disponibles"
        return 1
    fi
    
    local transition_id=$(echo "$transitions" | jq -r --arg status "$target_status" \
        '.transitions[] | select(.to.name == $status) | .id' | head -1)
    
    if [[ -n "$transition_id" && "$transition_id" != "null" ]]; then
        info "Transicionando a: $target_status (ID: $transition_id)"
        $DIR/jira.sh issue "$issue" --transitions --to "$transition_id" >/dev/null 2>&1
        return $?
    fi
    
    return 1
}

# 1. Obtener información del issue
info "Obteniendo información del issue $ISSUE_KEY..."
issue_data=$($DIR/jira.sh issue "$ISSUE_KEY" 2>/dev/null)
if [[ -z "$issue_data" ]]; then
    error "No se pudo obtener información del issue $ISSUE_KEY"
    exit 1
fi

project_key=$(echo "$issue_data" | jq -r '.fields.project.key')
issue_type=$(echo "$issue_data" | jq -r '.fields.issuetype.name')
current_status=$(echo "$issue_data" | jq -r '.fields.status.name')
current_category=$(echo "$issue_data" | jq -r '.fields.status.statusCategory.name')

info "Proyecto: $project_key, Tipo: $issue_type, Estado actual: $current_status"

# 2. Verificar si ya está en estado Done
if [[ "$current_category" == "Done" ]]; then
    success "El issue ya está en estado Done: $current_status"
    $DIR/jira-issue.sh "$ISSUE_KEY"
    exit 0
fi

# 3. Obtener workflow del proyecto
info "Obteniendo workflow del proyecto $project_key..."
workflow_data=$($DIR/jira.sh project statuses "$project_key" 2>/dev/null)
if [[ -z "$workflow_data" ]]; then
    error "No se pudo obtener el workflow del proyecto $project_key"
    exit 1
fi

issue_workflow=$(echo "$workflow_data" | jq --arg type "$issue_type" '.[] | select(.name == $type)')
if [[ -z "$issue_workflow" ]]; then
    error "No se encontró workflow para el tipo de issue: $issue_type"
    exit 1
fi

# 4. Identificar estado objetivo (Done)
info "Identificando estado final objetivo..."
target_status=$(find_target_done_status "$issue_workflow")
if [[ -z "$target_status" || "$target_status" == "null" ]]; then
    error "No se encontró ningún estado Done en el workflow"
    exit 1
fi

info "Estado objetivo: $target_status"

# 5. Calcular camino de estados
info "Calculando camino de transiciones..."
status_path=$(get_status_path "$issue_workflow" "$current_status" "$target_status")

if [[ -z "$status_path" ]]; then
    warn "No se encontró un camino directo desde $current_status hasta $target_status"
    warn "Intentando transición directa..."
    if execute_transition_to_status "$ISSUE_KEY" "$target_status"; then
        success "Transición directa exitosa"
    else
        error "No fue posible realizar la transición"
        exit 1
    fi
else
    # 6. Ejecutar transiciones iterativamente
    echo "$status_path" | while read -r next_status; do
        if [[ -n "$next_status" ]]; then
            if ! execute_transition_to_status "$ISSUE_KEY" "$next_status"; then
                warn "No se pudo transicionar a $next_status, intentando continuar..."
            else
                sleep 1  # Pequeña pausa entre transiciones
            fi
        fi
    done
fi

# 7. Verificar resultado final
echo ""
info "Estado final del issue:"
$DIR/jira-issue.sh "$ISSUE_KEY"

# Verificar si llegamos al estado Done
final_data=$($DIR/jira.sh issue "$ISSUE_KEY" 2>/dev/null)
final_category=$(echo "$final_data" | jq -r '.fields.status.statusCategory.name')
final_status=$(echo "$final_data" | jq -r '.fields.status.name')

if [[ "$final_category" == "Done" ]]; then
    success "Issue transicionado exitosamente a estado Done: $final_status"
    exit 0
else
    warn "El issue no llegó a estado Done. Estado actual: $final_status ($final_category)"
    exit 1
fi