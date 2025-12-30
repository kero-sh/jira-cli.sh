#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

COMMENT_MESSAGE=""
DISCARD_MODE=false

usage() {
    cat <<EOF
Uso: $(basename "$0") <issue_key> [options]

Descripción:
  Transiciona un issue a través de múltiples estados hasta llegar a Done.
  Determina automáticamente el workflow del proyecto y calcula el camino
  de transiciones necesarias sin usar IDs hardcoded.

Opciones:
  -h, --help         Muestra esta ayuda
    --tickets LIST     Lista de issues separados por comas (ej: ANDES-1,ANDES-2)
  -m, --message "txt"  Agrega comentario al finalizar (si queda en Done)
  --discard           Descarta el ticket en lugar de llevarlo a Done

Ejemplos:
  $(basename "$0") ABC-123
EOF
    exit 0
}

# Parse args: support --tickets, -m and positional issue key
TICKETS=""
ISSUE_KEY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --tickets=*)
            TICKETS="${1#*=}"
            shift
            ;;
        --tickets)
            TICKETS="$2"
            shift 2
            ;;
        -m|--message)
            COMMENT_MESSAGE="$2"
            shift 2
            ;;
        --discard)
            DISCARD_MODE=true
            shift
            ;;
        *)
            if [[ -z "$ISSUE_KEY" ]]; then
                ISSUE_KEY="$1"
                shift
            else
                error "Argumento desconocido: $1"
                usage
            fi
            ;;
    esac
done

if [[ -z "$TICKETS" && -z "$ISSUE_KEY" ]]; then
    error "Debes especificar un issue key o usar --tickets"
    usage
fi

# Regex de descarte de estados no ejecutables
DISCARD_REGEX='(?i)(discard|descart|cancel|rechaz|reject|wont[[:space:]]*fix|won'\''t[[:space:]]*fix|invalid|duplicate|obsolete|not[[:space:]]*do|no[[:space:]]se[[:space:]]hara|no[[:space:]]se[[:space:]]har[aá])'

# Deducción del siguiente paso usando solo las transiciones disponibles del issue
# Regla:
#   1) Si hay transiciones a categoría Done que no matcheen descarte, tomar la primera.
#   2) Si no hay Done, revisar transiciones In Progress / Indeterminate sin descarte.
#      - Si hay exactamente una, usarla.
#      - Si hay 0 o más de una, no forzar y retornar vacío.
select_next_transition() {
    local transitions_json="$1"

    # Intento Done permitido
    local done_pick
    done_pick=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
        (.transitions // [])
        | map(select(
            (.to.statusCategory.key // "" | ascii_downcase) == "done"
            and ((.name // "" | test($re;"i")) | not)
            and ((.to.name // "" | test($re;"i")) | not)
        ))
        | (.[0] // empty)
        | if . == null then "" else "\(.id)|\(.to.name)|done" end
    ')
    [[ -n "$done_pick" ]] && { echo "$done_pick"; return 0; }

    # Intento In Progress / Indeterminate (o cualquier otra no descartada si no hay mejor opción)
    local inprog_pick
    inprog_pick=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
        (.transitions // [])
        | map(select(
            ((.to.statusCategory.key // "" | ascii_downcase) | test("inprogress|indeterminate";"i"))
            and ((.name // "" | test($re;"i")) | not)
            and ((.to.name // "" | test($re;"i")) | not)
        ))
        | if length >= 1 then "\(.[] .id)|\(.[] .to.name)|\(.[] .to.statusCategory.key)" else "" end
    ')
    [[ -n "$inprog_pick" ]] && { echo "$inprog_pick"; return 0; }

    # Intento 3: cualquier transición no descartada (ej. categoría To Do) si es la única opción
    local any_pick
    any_pick=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
        (.transitions // [])
        | map(select(
            ((.name // "" | test($re;"i")) | not)
            and ((.to.name // "" | test($re;"i")) | not)
        )) as $clean
        | if ($clean | length) == 0 then "" 
          elif ($clean | length) == 1 then ($clean[0] | "\(.id)|\(.to.name)|\(.to.statusCategory.key)")
          else (
              ($clean
               | map(select((.to.statusCategory.key // "" | ascii_downcase) | test("inprogress|indeterminate";"i")))
               | .[0]?) as $pref
              | if $pref != null then "\($pref.id)|\($pref.to.name)|\($pref.to.statusCategory.key)"
                else ($clean[0] | "\(.id)|\(.to.name)|\(.to.statusCategory.key)")
                end
            )
          end
    ')
    [[ -n "$any_pick" ]] && { echo "$any_pick"; return 0; }

    # Nada aplicable
    return 1
}

# Agrega comentario final si se solicitó
add_comment_if_requested() {
    local issue="$1"
    if [[ -n "$COMMENT_MESSAGE" ]]; then
        info "Agregando comentario final..."
        if ! printf '%s' "$COMMENT_MESSAGE" | $DIR/jira.sh issue comment "$issue" -m - >/dev/null 2>&1; then
            warn "No se pudo agregar el comentario al issue $issue"
        fi
    fi
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

# Process a single ticket: wrapper to reuse the same logic for multiple tickets
process_issue() {
    local ISSUE_KEY_LOCAL="$1"

    # 1. Obtener información del issue
    info "Obteniendo información del issue $ISSUE_KEY_LOCAL..."
    local issue_data
    issue_data=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" 2>/dev/null)
    if [[ -z "$issue_data" ]]; then
        error "No se pudo obtener información del issue $ISSUE_KEY_LOCAL"
        return 1
    fi

    local project_key
    local issue_type
    local current_status
    local current_category
    project_key=$(echo "$issue_data" | jq -r '.fields.project.key')
    issue_type=$(echo "$issue_data" | jq -r '.fields.issuetype.name')
    current_status=$(echo "$issue_data" | jq -r '.fields.status.name')
    current_category=$(echo "$issue_data" | jq -r '.fields.status.statusCategory.name')

    info "Proyecto: $project_key, Tipo: $issue_type, Estado actual: $current_status"

    # 2. Verificar si ya está en estado Done o si se pidió descartar
    if [[ "$DISCARD_MODE" == "true" ]]; then
        if [[ "$current_category" == "Done" ]]; then
            success "El issue ya está en estado Done: $current_status"
            add_comment_if_requested "$ISSUE_KEY_LOCAL"
            $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"
            return 0
        fi
        # Buscar transición de descarte
        local transitions_json
        transitions_json=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions 2>/dev/null)
        local discard_transitions
        discard_transitions=$(echo "$transitions_json" | jq -r --arg re "$DISCARD_REGEX" '
            (.transitions // [])
            | map(select(
                (.to.statusCategory.key // "" | ascii_downcase) == "done"
                and ((.name // "" | test($re;"i")) or ((.to.name // "" | test($re;"i"))))
            ))
            | (.[0] // empty)
            | if . == null then "" else "\(.id)|\(.to.name)|done" end
        ')
        if [[ -n "$discard_transitions" ]]; then
            IFS='|' read -r discard_id discard_name discard_cat <<< "$discard_transitions"
            info "Descartando ticket: $discard_name (id: $discard_id)"
            if $DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions --to "$discard_id" >/dev/null 2>&1; then
                success "Ticket descartado exitosamente: $discard_name"
                add_comment_if_requested "$ISSUE_KEY_LOCAL"
                $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"
                return 0
            else
                error "Fallo al descartar el ticket"
                return 1
            fi
        else
            warn "No se encontró transición de descarte disponible"
            return 1
        fi
    fi

    if [[ "$current_category" == "Done" ]]; then
        success "El issue ya está en estado Done: $current_status"
        add_comment_if_requested "$ISSUE_KEY_LOCAL"
        $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"
        return 0
    fi

    # 3. Resolver por transiciones disponibles, sin forzar estados fuera del flujo
    local max_steps=10
    local step=1
    while [[ $step -le $max_steps ]]; do
        local transitions_json
        transitions_json=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions 2>/dev/null)
        if [[ -z "$transitions_json" ]]; then
            warn "No se pudieron obtener transiciones en el paso $step"
            break
        fi

        local pick
        pick=$(select_next_transition "$transitions_json")
        if [[ -z "$pick" ]]; then
            warn "No hay transiciones permitidas (Done o In Progress única) en el paso $step"
            break
        fi

        IFS='|' read -r tr_id tr_name tr_cat <<< "$pick"
        info "Paso $step: aplicando transición $tr_name (id: $tr_id, cat: $tr_cat)"
        if ! $DIR/jira.sh issue "$ISSUE_KEY_LOCAL" --transitions --to "$tr_id" >/dev/null 2>&1; then
            warn "Fallo la transición $tr_id -> $tr_name"
            break
        fi

        sleep 1
        issue_data=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" 2>/dev/null)
        current_status=$(echo "$issue_data" | jq -r '.fields.status.name')
        current_category=$(echo "$issue_data" | jq -r '.fields.status.statusCategory.name')
        info "Estado tras paso $step: $current_status ($current_category)"
        if [[ "$current_category" == "Done" ]]; then
            success "Issue transicionado exitosamente a estado Done: $current_status"
            add_comment_if_requested "$ISSUE_KEY_LOCAL"
            return 0
        fi
        ((step++))
    done

    # 7. Verificar resultado final
    echo ""
    info "Estado final del issue:"
    $DIR/jira-issue.sh "$ISSUE_KEY_LOCAL"

    # Verificar si llegamos al estado Done
    final_data=$($DIR/jira.sh issue "$ISSUE_KEY_LOCAL" 2>/dev/null)
    final_category=$(echo "$final_data" | jq -r '.fields.status.statusCategory.name')
    final_status=$(echo "$final_data" | jq -r '.fields.status.name')

    if [[ "$final_category" == "Done" ]]; then
        success "Issue transicionado exitosamente a estado Done: $final_status"
        return 0
    else
        warn "El issue no llegó a estado Done. Estado actual: $final_status ($final_category)"
        return 1
    fi
}

# If multiple tickets provided, process them sequentially
if [[ -n "$TICKETS" ]]; then
    IFS=',' read -ra arr <<< "$TICKETS"
    overall_status=0
    for t in "${arr[@]}"; do
        # Trim whitespace
        ticket=$(printf '%s' "$t" | sed -e 's/^ *//' -e 's/ *$//')
        info "--- Procesando $ticket ---"
        if ! process_issue "$ticket"; then
            warn "Fallo al procesar $ticket"
            overall_status=1
        fi
        echo ""
    done
    if [[ $overall_status -eq 0 ]]; then
        success "Todas las transiciones se completaron (o ya estaban en Done)."
        exit 0
    else
        warn "Algunas transiciones fallaron. Revisa el output arriba."
        exit 1
    fi
else
    # Single issue mode
    if process_issue "$ISSUE_KEY"; then
        exit 0
    else
        exit 1
    fi
fi