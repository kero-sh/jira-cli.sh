#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Optional helpers: allow standalone usage if helpers.sh is missing
if [[ -f "$DIR/../lib/helpers.sh" ]]; then
  # shellcheck source=/dev/null
  source "$DIR/../lib/helpers.sh"
else
  error() { echo "[ERROR] $*"; }
  info()  { echo "[INFO]  $*"; }
  warn()  { echo "[WARN]  $*"; }
  success(){ echo "[OK]    $*"; }
fi

# Uso:
# jira [GET|POST|PUT] /endpoint [--data '{json}'|/ruta/a/payload.json] [--token TOKEN] [--host HOST] [--output csv|json|table|yaml|md] [--csv-export all|current]
# O con sintaxis simplificada:
# jira project [id]
# jira issue [key]
# jira search [jql]
# jira create [--data '{json}'|/ruta/a/payload.json]
# jira priority
# jira status
# jira user [username]

set -e

DRY_RUN=false
# Default values
JIRA_HOST="${JIRA_HOST:-}"
JIRA_TOKEN="${JIRA_TOKEN:-}"
# Jira Cloud uses v3. Allow override with JIRA_API_VERSION=2 for on-prem.
JIRA_API_VERSION="${JIRA_API_VERSION:-3}"
# Auth support: basic (email+api token) or oauth bearer.
# Auto-detection: if JIRA_EMAIL and JIRA_API_TOKEN exist => basic; else if JIRA_TOKEN => bearer
JIRA_AUTH="${JIRA_AUTH:-}"
JIRA_EMAIL="${JIRA_EMAIL:-}"
JIRA_API_TOKEN="${JIRA_API_TOKEN:-}"
JIRA_PROJECT="${JIRA_PROJECT:-}"
METHOD="GET"
ENDPOINT=""
DATA=""
OUTPUT="json"
CSV_EXPORT_MODE="all" # all|current para exportador oficial de Jira Cloud (solo /search)
SHOW_TRANSITIONS=false
TRANSITION_TARGET=""
TRANSITION_TARGET_SET=false
CREATE_MODE=false
# Flags para crear issues (se aplican si create/POST /issue)
CREATE_PROJECT=""
CREATE_SUMMARY=""
CREATE_DESCRIPTION=""
CREATE_TYPE=""
CREATE_ASSIGNEE=""
CREATE_REPORTER=""
CREATE_PRIORITY=""
CREATE_EPIC=""
CREATE_LINK_ISSUE=""
CREATE_TEMPLATE=""

# Subcommands/state for 'user'
USER_MODE=""
USER_SEARCH_TERM=""
MULTI_STEP_USER_GET=false
MULTI_STEP_USER_ACTIVITY=false
USER_ACTIVITY_FROM=""
USER_ACTIVITY_TO=""
USER_ACTIVITY_LOOKBACK=""
USER_ACTIVITY_JQL_ONLY=false
USER_ACTIVITY_STATES=false
USER_ACTIVITY_LIST=false
USER_ACTIVITY_LIST_ONLY=false
USER_ACTIVITY_LIMIT=100

# Dependency checks (minimal, only when needed)
require_cmd() { command -v "$1" >/dev/null 2>&1 || { error "Required command not found: $1"; exit 127; }; }

# Curl wrapper function to centralize all HTTP calls
# Supports --dry-run mode to print the command instead of executing it
# Usage: execute_curl [curl options...] URL
execute_curl() {
  local curl_cmd=(curl --compressed --silent --location)
  curl_cmd+=("$@")
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] curl" "${curl_cmd[@]:1}" >&2
    # In dry-run, return empty JSON to not break the flow
    echo "{}"
    return 0
  fi
  
  "${curl_cmd[@]}"
}

# Function to display help
show_help() {
  cat << EOF
JIRA API Client - Script para interactuar con la API de Jira

SINTAXIS:
  Sintaxis tradicional:
    jira [GET|POST|PUT] /endpoint [opciones]

  Sintaxis simplificada:
    jira <recurso> [identificador] [opciones]

RECURSOS DISPONIBLES:
  project [id]       - Obtiene proyecto(s). Sin ID lista todos
  issue [key]        - Obtiene issue(s). Sin key lista los asignados
                       Con --transitions muestra transiciones disponibles
  search [jql]       - Busca con JQL. Sin JQL busca asignados a ti
  create             - Crea un issue (usa --data)
  priority           - Lista todas las prioridades
  status             - Lista todos los estados
  user [username]    - Busca usuario(s)
  user get <term>    - Obtiene el perfil completo del usuario
  user search <term> - Busca usuarios por texto/email/username
  issuetype          - Lista todos los tipos de issue
  field              - Lista todos los campos
  resolution         - Lista todas las resoluciones
  component <id>     - Obtiene componente específico (requiere ID)
  version <id>       - Obtiene versión específica (requiere ID)

OPCIONES:
  --data '{json}'    - Datos JSON para POST/PUT
                       También acepta ruta a archivo JSON (leerá el archivo)
  --token TOKEN      - Token de autenticación (o usar \$JIRA_TOKEN)
  --host HOST        - URL de Jira (o usar \$JIRA_HOST)
  --output FORMAT    - Formato de salida: json, csv, table, yaml, md
  --csv-export TYPE  - Para search+csv: csv de Jira Cloud (all|current)
  --transitions      - Para issue: muestra transiciones disponibles; con --to ID ejecuta transición
  --to ID            - ID de transición a aplicar cuando se usa --transitions
  --shell SHELL      - Genera script de autocompletado: bash, zsh
  --dry-run          - Imprime el comando curl en lugar de ejecutarlo
  --help             - Muestra esta ayuda

FLAGS PARA CREATE (se combinan con --data si se provee):
  --project KEY      - Clave de proyecto (ej: ABC)
  --summary TEXT     - Resumen/título del issue
  --description TXT  - Descripción del issue
  --type NAME        - Tipo de issue (ej: Task, Bug)
  --assignee NAME    - Usuario asignado (username)
  --reporter NAME    - Usuario reportero (username)
  --priority NAME    - Prioridad por nombre (ej: High)
  --epic KEY         - Epic Link (customfield_10100)
  --link-issue KEY   - Vincula outwardIssue.key a otro issue
  --template FILE    - Plantilla JSON base a combinar
  Nota: Si no usas --project, se toma \$JIRA_PROJECT cuando el payload no define proyecto.

FORMATOS DE SALIDA:
  json               - JSON formateado (por defecto)
  csv                - Valores separados por comas
  table              - Tabla con columnas separadas por tabs
  yaml               - Formato YAML
  md                 - Tabla en formato Markdown

VARIABLES DE ENTORNO:
  JIRA_HOST          - URL base de Jira (ej: https://jira.ejemplo.com)
  JIRA_TOKEN         - Token OAuth Bearer (si usas OAuth/3LO)
  JIRA_EMAIL         - Email de tu cuenta (para Jira Cloud API token)
  JIRA_API_TOKEN     - API token de Atlassian (para Basic)
  JIRA_API_VERSION   - 3 (Cloud, por defecto) o 2 (Server/DC)
  JIRA_AUTH          - basic|bearer (opcional; si no, autodetecta)
  JIRA_PROJECT       - Clave de proyecto por defecto para 'create'

EJEMPLOS:
  # Sintaxis simplificada
  jira priority --output table
  jira project andes --output json
  jira issue ABC-123
  jira issue ABC-123 --transitions
  jira issue ABC-123 --transitions --to 611
  jira search 'project=ABC AND status=Open'
  jira create --data '{"fields":{"project":{"key":"ABC"},"summary":"Nuevo ticket","issuetype":{"name":"Task"}}}'
  jira create --data ./payload.json
  jira create --data ./payload.json --priority High --assignee user1
  jira create --project ABC --summary "Titulo" --description "Desc" --type Task
  jira user carlos.herrera

  # Sintaxis tradicional
  jira GET /priority --output table
  jira GET /project/andes
  jira GET '/search?jql=assignee=currentUser()'
  jira POST /issue --data '{"fields":{"summary":"Test"}}'

  # Con opciones personalizadas
  jira priority --token abc123 --host https://mi-jira.com
  jira project --output yaml
  jira search 'assignee=currentUser()' --output md

  # Autocompletado (instalar una vez)
  jira --shell bash > ~/.jira-completion.bash
  jira --shell zsh > ~/.jira-completion.zsh

NOTAS:
  - Usa comillas simples para URLs con caracteres especiales
  - El formato table es útil para pipes con cut, awk, etc.
  - El formato md es perfecto para documentación
  - Sin autenticación algunas APIs pueden requerir login

EOF
}

# Specific help for 'jira user'
show_help_user() {
  cat << EOF
Uso: jira user [comando] [opciones]

Comandos:
  get <email|username|accountId>   Devuelve el perfil JSON del usuario
  search <texto>                   Lista usuarios que coinciden
  activity <term>                  Resumen de actividad del usuario

Opciones de activity:
  --jql                            Imprime los JQL por categoría en lugar de contar
  --from-date YYYY-MM-DD           Fecha inicial (rango); por defecto últimos 30d
  --to-date YYYY-MM-DD             Fecha final (rango); por defecto últimos 30d
  --lookback Nd                    Alternativa a --from-date/--to-date; p.ej. 30d
  --states                         Agrupa solo estados por creados/asignados (To Do, In Progress, Done)
  --list                           Además de contar, devuelve listas por categoría (campos clave)
  --list-only                      Devuelve solo una lista plana (para --output table)
  --limit N                        Máximo de issues por lista (por defecto 100)

Alias/compatibilidad:
  jira user <texto>                Equivale a 'jira user search <texto>'

Ejemplos:
  jira user get carlos.herrera
  jira user get carlos@example.com
  jira user get 5f3a1b2c3d4e5f6789012345
  jira user search jimy
  jira user activity jimy

Notas:
  - En API v3 (Cloud) se usa accountId; para 'get' con email/username se
    hace una búsqueda previa para resolver el accountId.
  - En API v2 (Server/DC) se usa username. 'get' resuelve username vía search.
  - Para 'activity', el rango por defecto es últimos 30 días (configurable
    con --lookback o --from-date/--to-date).
  - 'activity' sin término usa tu usuario actual (endpoint /myself).
  - Con --jql se imprimen las consultas JQL por grupo (reportados y
    asignados) y por categoría de estado (To Do, In Progress, Done),
    incluyendo el rango de fechas.
  - Con --states / --list la agrupación es por statusCategory (gris/azul/verde).
    Las listas incluyen: key, project, summary, statusCategory, labels, components y epic (si está en customfield_10014).
EOF
}

# Function to generate autocompletion script
generate_completion() {
  local shell="$1"

  case "$shell" in
    bash)
      cat << 'EOF'
# Bash completion for jira script
_jira_completion() {
    local cur prev opts resources
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Recursos disponibles
    resources="project projects issue issues search create priority priorities status statuses user users issuetype issuetypes field fields resolution resolutions component components version versions"

    # Métodos HTTP
    methods="GET POST PUT"

    # Opciones
    opts="--data --token --host --output --csv-export --transitions --to --help --shell --project --summary --description --type --assignee --reporter --priority --epic --link-issue --template --dry-run"

    # Formatos de salida
    formats="json csv table yaml md"

    # Si estamos en la primera posición, sugerir recursos o métodos HTTP
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${resources} ${methods} ${opts}" -- ${cur}) )
        return 0
    fi

    # Completado basado en la palabra anterior
    case "${prev}" in
        --output)
            COMPREPLY=( $(compgen -W "${formats}" -- ${cur}) )
            return 0
            ;;
        user|users)
            local user_subs="get search activity -h --help"
            COMPREPLY=( $(compgen -W "${user_subs}" -- ${cur}) )
            return 0
            ;;
        create)
            # Sugerir flags de creación
            local create_flags="--project --summary --description --type --assignee --reporter --priority --epic --link-issue --template --data --output"
            COMPREPLY=( $(compgen -W "${create_flags}" -- ${cur}) )
            return 0
            ;;
        --shell)
            COMPREPLY=( $(compgen -W "bash zsh" -- ${cur}) )
            return 0
            ;;
        --token|--host|--data|--to)
            # No autocompletar para estos (valores libres)
            return 0
            ;;
        search)
            # Sugerir algunos JQL comunes
            local jql_examples="'assignee=currentUser()' 'project=' 'status=Open' 'priority=High'"
            COMPREPLY=( $(compgen -W "${jql_examples}" -- ${cur}) )
            return 0
            ;;
        *)
            # Si la palabra anterior es un recurso, sugerir opciones
            if [[ " ${resources} " =~ " ${prev} " ]]; then
                COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
                return 0
            fi
            ;;
    esac

    # Completado por defecto con opciones
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
}

# Registrar la función de completado
complete -F _jira_completion jira

# Instrucciones de instalación:
# 1. Guarda este script como ~/.jira-completion.bash
# 2. Agrega esta línea a tu ~/.bashrc:
#    source ~/.jira-completion.bash
# 3. Recarga tu shell: source ~/.bashrc
EOF
      ;;
    zsh)
      cat << 'EOF'
#compdef jira
# Zsh completion for jira script

_jira() {
    local context curcontext="$curcontext" state line
    typeset -A opt_args

    # Recursos disponibles
    local resources=(
        'project:Obtiene proyecto(s)'
        'projects:Obtiene proyecto(s)'
        'issue:Obtiene issue(s)'
        'issues:Obtiene issue(s)'
        'search:Busca con JQL'
        'create:Crea un issue'
        'priority:Lista prioridades'
        'priorities:Lista prioridades'
        'status:Lista estados'
        'statuses:Lista estados'
        'user:Busca usuario(s)'
        'users:Busca usuario(s)'
        'issuetype:Lista tipos de issue'
        'issuetypes:Lista tipos de issue'
        'field:Lista campos'
        'fields:Lista campos'
        'resolution:Lista resoluciones'
        'resolutions:Lista resoluciones'
        'component:Obtiene componente'
        'components:Obtiene componente'
        'version:Obtiene versión'
        'versions:Obtiene versión'
    )

    # Métodos HTTP
    local methods=(
        'GET:Método GET'
        'POST:Método POST'
        'PUT:Método PUT'
    )

    # Formatos de salida
    local formats=(
        'json:JSON formateado'
        'csv:Valores separados por comas'
        'table:Tabla con tabs'
        'yaml:Formato YAML'
        'md:Tabla Markdown'
    )

    _arguments -C \
        '1: :->command' \
        '2: :->identifier' \
        '--data[Datos JSON o archivo para POST/PUT]:json data:_files' \
        '--token[Token de autenticación]:token' \
        '--host[URL de Jira]:host url' \
        '--output[Formato de salida]:format:->formats' \
        '--csv-export[Export CSV para search]:type:(all current)' \
        '--transitions[Mostrar transiciones disponibles]' \
        '--to[Aplicar transición con ID]:transition id' \
        '--shell[Generar autocompletado]:shell:(bash zsh)' \
        '--project[Clave de proyecto (key)]:project key' \
        '--summary[Resumen del issue]:summary' \
        '--description[Descripción del issue]:description' \
        '--type[Tipo de issue]:issuetype' \
        '--assignee[Asignado a (username)]:username' \
        '--reporter[Reportado por (username)]:username' \
        '--priority[Prioridad por nombre]:priority' \
        '--epic[Clave del Epic link]:epic key' \
        '--link-issue[Clave de issue a vincular]:issue key' \
        '--template[Plantilla JSON base]:file:_files' \
        '--dry-run[Imprimir comando curl sin ejecutar]' \
        '--help[Mostrar ayuda]' \
        '*: :->args'

    case $state in
        command)
            local all_commands=($resources $methods)
            _describe 'commands' all_commands 
            ;;
        identifier)
            case ${words[2]} in
                search)
                    local jql_examples=(
                        "'assignee=currentUser()':Issues asignados a ti"
                        "'project=':Issues de proyecto"
                        "'status=Open':Issues abiertos"
                        "'priority=High':Issues de alta prioridad"
                    )
                    _describe 'jql examples' jql_examples
                    ;;
                project|projects)
                    _message "ID o nombre del proyecto"
                    ;;
                issue|issues)
                    _message "Clave del issue (ej: ABC-123)"
                    ;;
                user|users)
                    _values "user subcommands" \
                      'get:Perfil completo por email/username/accountId' \
                      'search:Buscar usuarios por texto' \
                      'activity:Resumen de actividad del usuario'
                    ;;
                component|components|version|versions)
                    _message "ID del recurso"
                    ;;
            esac
            ;;
        formats)
            _describe 'output formats' formats
            ;;
        args)
            _arguments \
                '--data[Datos JSON]:json data:_files' \
                '--token[Token]:token' \
                '--host[Host]:host url' \
                '--output[Formato]:format:->formats' \
                '--csv-export[Export CSV para search]:type:(all current)' \
                '--transitions[Mostrar transiciones disponibles]' \
                '--to[Aplicar transición con ID]:transition id' \
                '--project[Clave de proyecto (key)]:project key' \
                '--summary[Resumen del issue]:summary' \
                '--description[Descripción del issue]:description' \
                '--type[Tipo de issue]:issuetype' \
                '--assignee[Asignado a (username)]:username' \
                '--reporter[Reportado por (username)]:username' \
                '--priority[Prioridad por nombre]:priority' \
                '--epic[Clave del Epic link]:epic key' \
                '--link-issue[Clave de issue a vincular]:issue key' \
                '--template[Plantilla JSON base]:file:_files' \
                '--shell[Shell]:shell:(bash zsh)' \
                '--dry-run[Imprimir comando curl sin ejecutar]' \
                '--help[Ayuda]'
            ;;
    esac
}

_jira "$@"

# Instrucciones de instalación:
# 1. Guarda este script como ~/.jira-completion.zsh
# 2. Agrega esta línea a tu ~/.zshrc:
#    source ~/.jira-completion.zsh
# 3. Recarga tu shell: source ~/.zshrc
#
# O alternativamente, coloca el archivo en tu directorio de completions:
# mkdir -p ~/.zsh/completions
# mv ~/.jira-completion.zsh ~/.zsh/completions/_jira
# echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
# echo 'autoload -U compinit && compinit' >> ~/.zshrc
EOF
      ;;
    *)
      echo "Shell no soportado: $shell" >&2
      echo "Shells soportados: bash, zsh" >&2
      exit 1
      ;;
  esac
}

# Function to build endpoint from simplified command
build_endpoint() {
  local resource="$1"
  local identifier="$2"
  local param_user
  if [[ "$JIRA_API_VERSION" == "2" ]]; then
    param_user="username"
  else
    param_user="query"
  fi

  case "$resource" in
    project|projects)
      if [[ -n "$identifier" ]]; then
        ENDPOINT="/project/$identifier"
      else
        ENDPOINT="/project"
      fi
      ;;
    issue|issues)
      if [[ -n "$identifier" ]]; then
        if [[ "$SHOW_TRANSITIONS" == "true" ]]; then
          ENDPOINT="/issue/$identifier/transitions"
        else
          ENDPOINT="/issue/$identifier"
        fi
      else
        ENDPOINT="/search?jql=assignee=currentUser()"
      fi
      ;;
    search)
      if [[ -n "$identifier" ]]; then
        # Si el identificador ya contiene JQL, usarlo directamente
        if [[ "$identifier" =~ ^jql= ]]; then
          ENDPOINT="/search?$identifier"
        else
          ENDPOINT="/search?jql=$identifier"
        fi
      else
        ENDPOINT="/search?jql=assignee=currentUser()"
      fi
      ;;
    create)
      # Creación de issues
      ENDPOINT="/issue"
      METHOD="POST"
      CREATE_MODE=true
      ;;
    priority|priorities)
      ENDPOINT="/priority"
      ;;
    status|statuses)
      ENDPOINT="/status"
      ;;
    user|users)
      # Subcomandos: get | search | activity
      if [[ "$USER_MODE" == "get" ]]; then
        # Siempre resolver vía search para soportar email/username/accountId
        USER_SEARCH_TERM="$identifier"
        MULTI_STEP_USER_GET=true
        # ENDPOINT será establecido luego de resolver el usuario
        ENDPOINT="/user" # marcador temporal; será reemplazado
      elif [[ "$USER_MODE" == "activity" ]]; then
        USER_SEARCH_TERM="$identifier"
        MULTI_STEP_USER_ACTIVITY=true
        ENDPOINT="/user" # marcador temporal; no se usará (respuesta se arma localmente)
      elif [[ "$USER_MODE" == "search" ]]; then
        if [[ -n "$identifier" ]]; then
          ENDPOINT="/user/search?$param_user=$identifier"
        else
          echo "Error: 'jira user search' requiere un término de búsqueda" >&2
          exit 1
        fi
      else
        # Compatibilidad: 'jira user <texto>' => search
        if [[ -n "$identifier" ]]; then
          ENDPOINT="/user/search?$param_user=$identifier"
        else
          ENDPOINT="/user/search?$param_user="
        fi
      fi
      ;;
    issuetype|issuetypes)
      ENDPOINT="/issuetype"
      ;;
    field|fields)
      ENDPOINT="/field"
      ;;
    resolution|resolutions)
      ENDPOINT="/resolution"
      ;;
    component|components)
      if [[ -n "$identifier" ]]; then
        ENDPOINT="/component/$identifier"
      else
        echo "Error: component requiere un ID" >&2
        exit 1
      fi
      ;;
    version|versions)
      if [[ -n "$identifier" ]]; then
        ENDPOINT="/version/$identifier"
      else
        echo "Error: version requiere un ID" >&2
        exit 1
      fi
      ;;
    *)
      echo "Recurso no reconocido: $resource" >&2
      echo "Recursos disponibles: project, issue, search, priority, status, user, issuetype, field, resolution, component, version" >&2
      exit 1
      ;;
  esac
}

# Argument parsing
USING_SIMPLIFIED_SYNTAX=false
resource=""
identifier=""

# First pass: process all options to get the flags
temp_args=("$@")
for ((i=0; i<${#temp_args[@]}; i++)); do
  case "${temp_args[i]}" in
    --transitions)
      SHOW_TRANSITIONS=true
      ;;
    --to)
      TRANSITION_TARGET="${temp_args[i+1]}"
      SHOW_TRANSITIONS=true
      TRANSITION_TARGET_SET=true
      ((i++))
      ;;
    --output)
      OUTPUT="${temp_args[i+1]}"
      ((i++))
      ;;
    --csv-export)
      CSV_EXPORT_MODE="${temp_args[i+1]}"
      ((i++))
      ;;
    --token)
      JIRA_TOKEN="${temp_args[i+1]}"
      ((i++))
      ;;
    --host)
      JIRA_HOST="${temp_args[i+1]}"
      ((i++))
      ;;
    --data)
      DATA="${temp_args[i+1]}"
      ((i++))
      ;;
    --project)
      CREATE_PROJECT="${temp_args[i+1]}"; ((i++)) ;;
    --summary)
      CREATE_SUMMARY="${temp_args[i+1]}"; ((i++)) ;;
    --description)
      CREATE_DESCRIPTION="${temp_args[i+1]}"; ((i++)) ;;
    --type)
      CREATE_TYPE="${temp_args[i+1]}"; ((i++)) ;;
    --assignee)
      CREATE_ASSIGNEE="${temp_args[i+1]}"; ((i++)) ;;
    --reporter)
      CREATE_REPORTER="${temp_args[i+1]}"; ((i++)) ;;
    --priority)
      CREATE_PRIORITY="${temp_args[i+1]}"; ((i++)) ;;
    --epic)
      CREATE_EPIC="${temp_args[i+1]}"; ((i++)) ;;
    --link-issue)
      CREATE_LINK_ISSUE="${temp_args[i+1]}"; ((i++)) ;;
    --template)
      CREATE_TEMPLATE="${temp_args[i+1]}"; ((i++)) ;;
    # Opciones para 'user activity'
    --from-date)
      USER_ACTIVITY_FROM="${temp_args[i+1]}"; ((i++)) ;;
    --to-date)
      USER_ACTIVITY_TO="${temp_args[i+1]}"; ((i++)) ;;
    --lookback)
      USER_ACTIVITY_LOOKBACK="${temp_args[i+1]}"; ((i++)) ;;
    --jql)
      USER_ACTIVITY_JQL_ONLY=true ;;
    --states)
      USER_ACTIVITY_STATES=true ;;
    --list)
      USER_ACTIVITY_LIST=true ;;
    --list-only)
      USER_ACTIVITY_LIST_ONLY=true ;;
    --limit)
      USER_ACTIVITY_LIMIT="${temp_args[i+1]}"; ((i++)) ;;
    --dry-run)
      DRY_RUN=true ;;
    --help)
      show_help; exit 0 ;;
    --shell)
      generate_completion "${temp_args[i+1]}"; exit 0 ;;
  esac
done

# Help shortcuts: 'jira help <resource>' or 'jira <resource> -h/--help'
if [[ $# -gt 0 ]] && [[ "$1" == "help" ]]; then
  if [[ $# -gt 1 ]] && [[ "$2" =~ ^(user|users)$ ]]; then
    show_help_user; exit 0
  else
    show_help; exit 0
  fi
fi

# Check if the first argument is an HTTP method or a resource
if [[ $# -gt 0 ]] && [[ "$1" =~ ^(GET|POST|PUT)$ ]]; then
  # Traditional syntax with HTTP method
  METHOD="$1"
  shift

  # El siguiente argumento puede ser un endpoint directo (/algo)
  # o un recurso simplificado (issue, project, create, etc.)
  if [[ $# -gt 0 ]]; then
    if [[ "$1" =~ ^/ ]]; then
      ENDPOINT="$1"
      shift
    elif [[ ! "$1" =~ ^- ]]; then
      # Interpretar como recurso simplificado con identificador opcional
      resource="$1"; shift

      # Soporte de ayuda específica por recurso
      if [[ "$resource" =~ ^(user|users)$ ]] && [[ $# -gt 0 ]] && [[ "$1" =~ ^(-h|--help|help)$ ]]; then
        show_help_user; exit 0
      fi

      # Subcomandos para 'user'
      identifier=""
      if [[ "$resource" =~ ^(user|users)$ ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        case "$1" in
          get|search|activity)
            USER_MODE="$1"; shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
              identifier="$1"; shift
            else
              identifier=""
            fi
            ;;
          *)
            # Compatibilidad: 'jira user <texto>' => search
            identifier="$1"; shift ;;
        esac
      else
        # Recurso genérico con identificador opcional
        if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
          identifier="$1"; shift
        fi
      fi

      build_endpoint "$resource" "$identifier"
    fi
  fi
elif [[ $# -gt 0 ]] && [[ "$1" =~ ^/ ]]; then
  # Sintaxis tradicional sin método HTTP explícito (asume GET)
  ENDPOINT="$1"
  shift
elif [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
  # Sintaxis simplificada (recurso como primer argumento)
  USING_SIMPLIFIED_SYNTAX=true
  resource="$1"
  shift

  # El siguiente argumento podría ser el identificador
  identifier=""
  # Ayuda por recurso
  if [[ "$resource" =~ ^(user|users)$ ]] && [[ $# -gt 0 ]] && [[ "$1" =~ ^(-h|--help|help)$ ]]; then
    show_help_user; exit 0
  fi

  if [[ "$resource" =~ ^(user|users)$ ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
    case "$1" in
      get|search|activity)
        USER_MODE="$1"; shift
        if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
          identifier="$1"; shift
        fi
        ;;
      *)
        identifier="$1"; shift ;;
    esac
  else
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
      identifier="$1"; shift
    fi
  fi

  build_endpoint "$resource" "$identifier"
fi

# Continuar con el parseo de argumentos restantes (solo para argumentos que no procesamos en el primer pase)
while [[ $# -gt 0 ]]; do
  case "$1" in
    GET|POST|PUT)
      if [[ "$USING_SIMPLIFIED_SYNTAX" == "true" ]]; then
        echo "Error: No puedes especificar método HTTP con sintaxis simplificada" >&2
        exit 1
      fi
      METHOD="$1"
      shift
      ;;
    --jql)
      # Flag sin valor
      shift
      ;;
    --states)
      # Flag sin valor
      shift
      ;;
    --list)
      # Flag sin valor
      shift
      ;;
    --list-only)
      # Flag sin valor
      shift
      ;;
    --dry-run)
      # Flag sin valor
      shift
      ;;
    --data|--token|--host|--output|--csv-export|--transitions|--to|--project|--summary|--description|--type|--assignee|--reporter|--priority|--epic|--link-issue|--template|--from-date|--to-date|--lookback|--limit)
      # Ya procesados en el primer pase, saltarlos
      if [[ "$1" =~ ^--(data|token|host|output|csv-export|to|project|summary|description|type|assignee|reporter|priority|epic|link-issue|template|from-date|to-date|lookback|limit)$ ]]; then
        shift 2
      else
        shift
      fi
      ;;
    --help|--shell)
      # Ya procesados en el primer pase
      shift 2
      ;;
    /*)
      if [[ "$USING_SIMPLIFIED_SYNTAX" == "true" ]]; then
        echo "Error: No puedes especificar endpoint directo con sintaxis simplificada" >&2
        exit 1
      fi
      ENDPOINT="$1"
      shift
      ;;
    *)
      echo "Argumento desconocido: $1" >&2
      exit 1
      ;;
  esac
done

# Validaciones específicas para argumentos de transición
if [[ "$TRANSITION_TARGET_SET" == "true" ]]; then
  if [[ -z "$TRANSITION_TARGET" || "$TRANSITION_TARGET" == -* ]]; then
    echo "Error: --to requiere un ID de transición válido" >&2
    exit 1
  fi
fi

# Validaciones
if [[ -z "$JIRA_HOST" ]]; then
  error "Debes especificar la URL de Jira con --host o la variable de entorno JIRA_HOST" >&2
  exit 1
fi


if [[ -z "$ENDPOINT" ]]; then
  echo "Debes especificar el endpoint o recurso" >&2
  echo "Ejemplos:" >&2
  echo "  jira project andes" >&2
  echo "  jira issue ABC-123" >&2
  echo "  jira search 'assignee=currentUser()'" >&2
  echo "  jira create --data ./payload.json" >&2
  echo "  jira priority" >&2
  echo "  jira GET /search?jql=project=ABC" >&2
  exit 1
fi

# Default: en 'user activity' usa 'states' (solo JQL; sin escaneo por issue)
if [[ "$resource" =~ ^(user|users)$ ]] && [[ "$USER_MODE" == "activity" ]] && [[ "$USER_ACTIVITY_STATES" != true ]]; then
  USER_ACTIVITY_STATES=true
fi

# Default: en 'user activity --states' con salida table, activar list-only
if [[ "$resource" =~ ^(user|users)$ ]] && [[ "$USER_MODE" == "activity" ]] && [[ "$USER_ACTIVITY_STATES" == true ]] && [[ "$OUTPUT" == "table" ]] && [[ "$USER_ACTIVITY_LIST" != true ]] && [[ "$USER_ACTIVITY_LIST_ONLY" != true ]]; then
  USER_ACTIVITY_LIST_ONLY=true
fi

# Si se solicita una transición con --to, preparar POST automático
if [[ "$SHOW_TRANSITIONS" == "true" && "$ENDPOINT" != */transitions ]]; then
  if [[ -n "$resource" && "$resource" =~ ^(issue|issues)$ && -n "$identifier" ]]; then
    ENDPOINT="/issue/$identifier/transitions"
  fi
fi

if [[ "$TRANSITION_TARGET_SET" == "true" ]]; then
  if [[ "$ENDPOINT" != */transitions ]]; then
    echo "Error: --to solo puede usarse al consultar un issue específico" >&2
    exit 1
  fi
  METHOD="POST"
  if [[ -z "$DATA" ]]; then
    DATA="{\"transition\":{\"id\":\"$TRANSITION_TARGET\"}}"
  fi
fi

# Requisitos de dependencias mínimas
require_cmd curl
require_cmd jq
if [[ "$OUTPUT" == "yaml" ]]; then require_cmd yq; fi
if [[ "$OUTPUT" == "table" ]]; then require_cmd column; fi

# Determina encabezado de autenticación
AUTH_HEADER=""
if [[ -z "$JIRA_AUTH" ]]; then
  if [[ -n "$JIRA_EMAIL" && -n "$JIRA_API_TOKEN" ]]; then
    JIRA_AUTH="basic"
  elif [[ -n "$JIRA_TOKEN" ]]; then
    JIRA_AUTH="bearer"
  fi
fi

case "$JIRA_AUTH" in
  basic)
    if [[ -n "$JIRA_EMAIL" && -n "$JIRA_API_TOKEN" ]]; then
      BASIC_TOKEN=$(printf "%s:%s" "$JIRA_EMAIL" "$JIRA_API_TOKEN" | base64)
      AUTH_HEADER="Authorization: Basic $BASIC_TOKEN"
    fi
    ;;
  bearer)
    if [[ -n "$JIRA_TOKEN" ]]; then
      AUTH_HEADER="Authorization: Bearer $JIRA_TOKEN"
    fi
    ;;
esac

# Resolución previa para 'jira user get <term>'
EARLY_RESPONSE=""
if [[ "$MULTI_STEP_USER_GET" == "true" ]]; then
  # Determinar parámetro de búsqueda según versión de API
  if [[ "$JIRA_API_VERSION" == "2" ]]; then
    _user_param="username"
  else
    _user_param="query"
  fi

  if [[ -z "$USER_SEARCH_TERM" ]]; then
    echo "Error: 'jira user get' requiere un término (email/username/accountId)" >&2
    exit 1
  fi

  # Armar URL de búsqueda y ejecutar
  _search_url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/user/search?${_user_param}=$USER_SEARCH_TERM"
  _search_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$_search_url")

  # Elegir mejor coincidencia y construir ENDPOINT final
  if [[ "$JIRA_API_VERSION" == "2" ]]; then
    _chosen_name=$(printf '%s' "$_search_resp" | jq -r --arg term "$USER_SEARCH_TERM" '
      if (type=="array" and length>0) then
        ( (map(select(((.emailAddress? // "")|ascii_downcase) == ($term|ascii_downcase)
                    or ((.name? // "")|ascii_downcase) == ($term|ascii_downcase)
                    or ((.displayName? // "")|ascii_downcase) == ($term|ascii_downcase))) | .[0].name)
          // .[0].name )
      else empty end')
    if [[ -n "$_chosen_name" && "$_chosen_name" != "null" ]]; then
      ENDPOINT="/user?username=$_chosen_name"
      METHOD="GET"
    else
      EARLY_RESPONSE="[]"
    fi
  else
    _chosen_id=$(printf '%s' "$_search_resp" | jq -r --arg term "$USER_SEARCH_TERM" '
      if (type=="array" and length>0) then
        ( (map(select(((.emailAddress? // "")|ascii_downcase) == ($term|ascii_downcase)
                    or ((.name? // "")|ascii_downcase) == ($term|ascii_downcase)
                    or ((.displayName? // "")|ascii_downcase) == ($term|ascii_downcase)
                    or ((.accountId? // "")|ascii_downcase) == ($term|ascii_downcase))) | .[0].accountId)
          // .[0].accountId )
      else empty end')
    if [[ -n "$_chosen_id" && "$_chosen_id" != "null" ]]; then
      ENDPOINT="/user?accountId=$_chosen_id"
      METHOD="GET"
    else
      EARLY_RESPONSE="[]"
    fi
  fi
fi

if [[ "$MULTI_STEP_USER_ACTIVITY" == "true" ]]; then
  # Resolver usuario
  if [[ "$JIRA_API_VERSION" == "2" ]]; then
    _user_param="username"
  else
    _user_param="query"
  fi

  _user_found=false
  _use_current_user_jql=false
  _chosen_id=""; _chosen_name=""; _displayName=""; _email=""

  if [[ -z "$USER_SEARCH_TERM" ]]; then
    # Usar /myself cuando no se provee término
    _me_url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/myself"
    _me_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$_me_url")
    if [[ "$JIRA_API_VERSION" == "2" ]]; then
      _chosen_name=$(printf '%s' "$_me_resp" | jq -r '.name // empty')
      _displayName=$(printf '%s' "$_me_resp" | jq -r '.displayName // ""')
      _email=$(printf '%s' "$_me_resp" | jq -r '.emailAddress // ""')
      if [[ -n "$_chosen_name" ]]; then _user_found=true; _use_current_user_jql=true; fi
    else
      _chosen_id=$(printf '%s' "$_me_resp" | jq -r '.accountId // empty')
      _displayName=$(printf '%s' "$_me_resp" | jq -r '.displayName // ""')
      _email=$(printf '%s' "$_me_resp" | jq -r '.emailAddress // ""')
      if [[ -n "$_chosen_id" ]]; then _user_found=true; _use_current_user_jql=true; fi
    fi
  else
    _search_url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/user/search?${_user_param}=$USER_SEARCH_TERM"
    _search_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$_search_url")
  fi

  if [[ "$_user_found" != true ]]; then
    if [[ -n "$USER_SEARCH_TERM" ]]; then
      if [[ "$JIRA_API_VERSION" == "2" ]]; then
        _chosen_name=$(printf '%s' "$_search_resp" | jq -r --arg term "$USER_SEARCH_TERM" '
          if (type=="array" and length>0) then
            ( (map(select(((.emailAddress? // "")|ascii_downcase) == ($term|ascii_downcase)
                        or ((.name? // "")|ascii_downcase) == ($term|ascii_downcase)
                        or ((.displayName? // "")|ascii_downcase) == ($term|ascii_downcase))) | .[0].name)
              // .[0].name )
          else empty end')
        _displayName=$(printf '%s' "$_search_resp" | jq -r '.[0].displayName // ""')
        _email=$(printf '%s' "$_search_resp" | jq -r '.[0].emailAddress // ""')
        if [[ -n "$_chosen_name" && "$_chosen_name" != "null" ]]; then _user_found=true; fi
      else
        _chosen_id=$(printf '%s' "$_search_resp" | jq -r --arg term "$USER_SEARCH_TERM" '
          if (type=="array" and length>0) then
            ( (map(select(((.emailAddress? // "")|ascii_downcase) == ($term|ascii_downcase)
                        or ((.name? // "")|ascii_downcase) == ($term|ascii_downcase)
                        or ((.displayName? // "")|ascii_downcase) == ($term|ascii_downcase)
                        or ((.accountId? // "")|ascii_downcase) == ($term|ascii_downcase))) | .[0].accountId)
              // .[0].accountId )
          else empty end')
        _displayName=$(printf '%s' "$_search_resp" | jq -r '.[0].displayName // ""')
        _email=$(printf '%s' "$_search_resp" | jq -r '.[0].emailAddress // ""')
        if [[ -n "$_chosen_id" && "$_chosen_id" != "null" ]]; then _user_found=true; fi
      fi
    fi
  fi

  # Preparar filtros de fecha
  LOOKBACK="${USER_ACTIVITY_LOOKBACK:-${JIRA_ACTIVITY_LOOKBACK:-30d}}"
  date_filter_created=""
  date_filter_updated=""
  date_filter_resolved=""
  if [[ -n "$USER_ACTIVITY_FROM" || -n "$USER_ACTIVITY_TO" ]]; then
    if [[ -n "$USER_ACTIVITY_FROM" ]]; then
      date_filter_created="created >= '$USER_ACTIVITY_FROM'"
      date_filter_updated="updated >= '$USER_ACTIVITY_FROM'"
      date_filter_resolved="resolutiondate >= '$USER_ACTIVITY_FROM'"
    fi
    if [[ -n "$USER_ACTIVITY_TO" ]]; then
      date_filter_created+="${date_filter_created:+ AND }created <= '$USER_ACTIVITY_TO'"
      date_filter_updated+="${date_filter_updated:+ AND }updated <= '$USER_ACTIVITY_TO'"
      date_filter_resolved+="${date_filter_resolved:+ AND }resolutiondate <= '$USER_ACTIVITY_TO'"
    fi
  else
    date_filter_created="created >= -$LOOKBACK"
    date_filter_updated="updated >= -$LOOKBACK"
    date_filter_resolved="resolutiondate >= -$LOOKBACK"
  fi

  if [[ "$_user_found" != true ]]; then
    if [[ "$USER_ACTIVITY_JQL_ONLY" == true ]]; then
      EARLY_RESPONSE=$(jq -n --arg term "$USER_SEARCH_TERM" '{user:{query:$term,found:false}, jql:{}}')
    else
      EARLY_RESPONSE=$(jq -n --arg term "$USER_SEARCH_TERM" '{user:{query:$term,found:false}, summary:{created:0,assigned:0,resolved:0,in_progress:0,not_started:0,commented:0}}')
    fi
  else
    # Construir expresiones JQL por usuario/campo
    jql_expr_for_field() {
      local field="$1"
      if [[ "$_use_current_user_jql" == true ]]; then
        printf "%s = currentUser()" "$field"
      else
        if [[ "$JIRA_API_VERSION" == "2" ]]; then
          printf "%s = \"%s\"" "$field" "$_chosen_name"
        else
          printf "%s in (accountId(\"%s\"))" "$field" "$_chosen_id"
        fi
      fi
    }

    # Si se solicita 'solo estados', construir grupos por creados/asignados
    if [[ "$USER_ACTIVITY_STATES" == true ]]; then
      # Agrupación por categorías de estado (gris/azul/verde)
      JQL_CREATED_BASE="$(jql_expr_for_field reporter) AND $date_filter_created"
      JQL_ASSIGNED_BASE="$(jql_expr_for_field assignee) AND $date_filter_updated"

      JQL_CREATED_TODO="$JQL_CREATED_BASE AND statusCategory = \"To Do\""
      JQL_CREATED_INPROG="$JQL_CREATED_BASE AND statusCategory = \"In Progress\""
      JQL_CREATED_DONE="$JQL_CREATED_BASE AND statusCategory = Done"

      JQL_ASSIGNED_TODO="$JQL_ASSIGNED_BASE AND statusCategory = \"To Do\""
      JQL_ASSIGNED_INPROG="$JQL_ASSIGNED_BASE AND statusCategory = \"In Progress\""
      # Para 'done' de asignados, usar rango por fecha de resolución
      JQL_ASSIGNED_DONE="$(jql_expr_for_field assignee) AND statusCategory = Done AND $date_filter_resolved"

      if [[ "$USER_ACTIVITY_JQL_ONLY" == true ]]; then
        EARLY_RESPONSE=$(jq -n \
          --arg accountId "$_chosen_id" \
          --arg username "$_chosen_name" \
          --arg displayName "$_displayName" \
          --arg email "$_email" \
          --arg c_todo "$JQL_CREATED_TODO" \
          --arg c_prog "$JQL_CREATED_INPROG" \
          --arg c_done "$JQL_CREATED_DONE" \
          --arg a_todo "$JQL_ASSIGNED_TODO" \
          --arg a_prog "$JQL_ASSIGNED_INPROG" \
          --arg a_done "$JQL_ASSIGNED_DONE" \
          '{user:{found:true,accountId:$accountId,username:$username,displayName:$displayName,email:$email}, jql:{created:{todo:$c_todo,in_progress:$c_prog,done:$c_done}, assigned:{todo:$a_todo,in_progress:$a_prog,done:$a_done}}}')
      else
        get_total_by_jql() {
          local jql="$1"; local enc; enc=$(jq -rn --arg s "$jql" '$s|@uri');
          local url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$enc&maxResults=0&fields=none";
          local resp; resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url"); printf '%s' "$resp" | jq -r '.total // 0'
        }

        _c_todo=$(get_total_by_jql "$JQL_CREATED_TODO")
        _c_prog=$(get_total_by_jql "$JQL_CREATED_INPROG")
        _c_done=$(get_total_by_jql "$JQL_CREATED_DONE")
        _a_todo=$(get_total_by_jql "$JQL_ASSIGNED_TODO")
        _a_prog=$(get_total_by_jql "$JQL_ASSIGNED_INPROG")
        _a_done=$(get_total_by_jql "$JQL_ASSIGNED_DONE")

        if [[ "$USER_ACTIVITY_LIST_ONLY" == true || "$USER_ACTIVITY_LIST" == true ]]; then
          # Helper: obtener lista para un JQL con campos mínimos
          fetch_list_for_jql() {
            local jql="$1"; local scope="$2"; local category="$3"; local enc; enc=$(jq -rn --arg s "$jql" '$s|@uri');
            local epic_field_name
            epic_field_name="${JIRA_EPIC_FIELD:-customfield_10014}"
            local url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$enc&maxResults=$USER_ACTIVITY_LIMIT&fields=key,summary,project,status,labels,components,${epic_field_name}";
            local resp; resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url");
            printf '%s' "$resp" | jq --arg scope "$scope" --arg cat "$category" --arg epic "$epic_field_name" '
              (.issues // []) | map({
                scope: $scope,
                category: $cat,
                key: .key,
                project: (.fields.project.key // ""),
                statusCategory: (.fields.status.statusCategory.name // ""),
                status: (.fields.status.name // ""),
                summary: (.fields.summary // ""),
                epic: (.fields[$epic] // ""),
                labels: ((.fields.labels // []) | join(",")),
                components: ((.fields.components // []) | map(.name) | join(","))
              })'
          }

          lists_created=$(jq -n '[]')
          lists_assigned=$(jq -n '[]')
          lists_created=$(jq -s 'add' <(printf '%s' "$lists_created") <(fetch_list_for_jql "$JQL_CREATED_TODO" created ToDo) <(fetch_list_for_jql "$JQL_CREATED_INPROG" created InProgress) <(fetch_list_for_jql "$JQL_CREATED_DONE" created Done))
          lists_assigned=$(jq -s 'add' <(printf '%s' "$lists_assigned") <(fetch_list_for_jql "$JQL_ASSIGNED_TODO" assigned ToDo) <(fetch_list_for_jql "$JQL_ASSIGNED_INPROG" assigned InProgress) <(fetch_list_for_jql "$JQL_ASSIGNED_DONE" assigned Done))
        fi

        if [[ "$USER_ACTIVITY_LIST_ONLY" == true ]]; then
          EARLY_RESPONSE=$(jq -s 'add' <(printf '%s' "$lists_created") <(printf '%s' "$lists_assigned"))
        else
          if [[ "$USER_ACTIVITY_LIST" == true ]]; then
            EARLY_RESPONSE=$(jq -n \
              --arg accountId "$_chosen_id" \
              --arg username "$_chosen_name" \
              --arg displayName "$_displayName" \
              --arg email "$_email" \
              --argjson c_todo "${_c_todo:-0}" \
              --argjson c_prog "${_c_prog:-0}" \
              --argjson c_done "${_c_done:-0}" \
              --argjson a_todo "${_a_todo:-0}" \
              --argjson a_prog "${_a_prog:-0}" \
              --argjson a_done "${_a_done:-0}" \
              --argjson list_created "$lists_created" \
              --argjson list_assigned "$lists_assigned" \
              '{user:{found:true,accountId:$accountId,username:$username,displayName:$displayName,email:$email}, states:{created:{todo:$c_todo,in_progress:$c_prog,done:$c_done}, assigned:{todo:$a_todo,in_progress:$a_prog,done:$a_done}}, lists:{created:$list_created, assigned:$list_assigned}}')
          else
            EARLY_RESPONSE=$(jq -n \
              --arg accountId "$_chosen_id" \
              --arg username "$_chosen_name" \
              --arg displayName "$_displayName" \
              --arg email "$_email" \
              --argjson c_todo "${_c_todo:-0}" \
              --argjson c_prog "${_c_prog:-0}" \
              --argjson c_done "${_c_done:-0}" \
              --argjson a_todo "${_a_todo:-0}" \
              --argjson a_prog "${_a_prog:-0}" \
              --argjson a_done "${_a_done:-0}" \
              '{user:{found:true,accountId:$accountId,username:$username,displayName:$displayName,email:$email}, states:{created:{todo:$c_todo,in_progress:$c_prog,done:$c_done}, assigned:{todo:$a_todo,in_progress:$a_prog,done:$a_done}}')
          fi
        fi
      fi
    else
      # Modo anterior (resumen y comentados)
      JQL_CREATED="$(jql_expr_for_field creator) AND $date_filter_created"
      JQL_ASSIGNED="$(jql_expr_for_field assignee) AND $date_filter_updated"
      JQL_RESOLVED="$(jql_expr_for_field assignee) AND statusCategory = Done AND $date_filter_resolved"
      JQL_INPROGRESS="$(jql_expr_for_field assignee) AND statusCategory = \"In Progress\" AND $date_filter_updated"
      JQL_TODO="$(jql_expr_for_field assignee) AND statusCategory = \"To Do\" AND $date_filter_updated"
      # Comentados (aproximado)
      if [[ "$_use_current_user_jql" == true ]]; then
        JQL_COMMENTED="comment ~ \"\" AND $date_filter_updated"
      else
        if [[ "$JIRA_API_VERSION" == "2" ]]; then _comment_token="$_chosen_name"; else _comment_token="$_email"; fi
        JQL_COMMENTED="comment ~ \"${_comment_token}\" AND $date_filter_updated"
      fi

      if [[ "$USER_ACTIVITY_JQL_ONLY" == true ]]; then
        EARLY_RESPONSE=$(jq -n \
          --arg accountId "$_chosen_id" \
          --arg username "$_chosen_name" \
          --arg displayName "$_displayName" \
          --arg email "$_email" \
          --arg created "$JQL_CREATED" \
          --arg assigned "$JQL_ASSIGNED" \
          --arg resolved "$JQL_RESOLVED" \
          --arg in_progress "$JQL_INPROGRESS" \
          --arg not_started "$JQL_TODO" \
          --arg commented "$JQL_COMMENTED" \
          '{user:{found:true,accountId:$accountId,username:$username,displayName:$displayName,email:$email}, jql:{created:$created,assigned:$assigned,resolved:$resolved,in_progress:$in_progress,not_started:$not_started,commented:$commented}}')
      else
        get_total_by_jql() {
          local jql="$1"; local enc; enc=$(jq -rn --arg s "$jql" '$s|@uri');
          local url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$enc&maxResults=0&fields=none";
          local resp; resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url"); printf '%s' "$resp" | jq -r '.total // 0'
        }
        _tot_created=$(get_total_by_jql "$JQL_CREATED")
        _tot_assigned=$(get_total_by_jql "$JQL_ASSIGNED")
        _tot_resolved=$(get_total_by_jql "$JQL_RESOLVED")
        _tot_in_progress=$(get_total_by_jql "$JQL_INPROGRESS")
        _tot_not_started=$(get_total_by_jql "$JQL_TODO")

        # Comentados: escanear issues recientes
        SCAN_MAX="${JIRA_ACTIVITY_COMMENT_SCAN_MAX:-100}"; PAGE=50
        _jql_recent="$date_filter_updated ORDER BY updated DESC"; _processed=0; _commented=0; _startAt=0
        while [[ $_processed -lt $SCAN_MAX ]]; do
          _enc=$(jq -rn --arg s "$_jql_recent" '$s|@uri')
          _url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$_enc&startAt=$_startAt&maxResults=$PAGE&fields=key"
          _resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$_url")
          _count_keys=$(printf '%s' "$_resp" | jq -r '.issues | length'); [[ "$_count_keys" -eq 0 ]] && break
          while IFS= read -r _key; do
            [[ $_processed -ge $SCAN_MAX ]] && break
            _processed=$(( _processed + 1 ))
            _c_url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/issue/${_key}/comment?maxResults=100"
            _c_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$_c_url")
            if [[ "$JIRA_API_VERSION" == "2" ]]; then
              if printf '%s' "$_c_resp" | jq -e --arg u "$_chosen_name" 'any(.comments[]?; (.author.name // "") == $u)' > /dev/null; then _commented=$(( _commented + 1 )); fi
            else
              if printf '%s' "$_c_resp" | jq -e --arg u "$_chosen_id" 'any(.comments[]?; (.author.accountId // "") == $u)' > /dev/null; then _commented=$(( _commented + 1 )); fi
            fi
          done < <(printf '%s' "$_resp" | jq -r '.issues[].key')
          _startAt=$(( _startAt + PAGE ))
        done

        EARLY_RESPONSE=$(jq -n \
          --arg accountId "$_chosen_id" \
          --arg username "$_chosen_name" \
          --arg displayName "$_displayName" \
          --arg email "$_email" \
          --argjson created "${_tot_created:-0}" \
          --argjson assigned "${_tot_assigned:-0}" \
          --argjson resolved "${_tot_resolved:-0}" \
          --argjson in_progress "${_tot_in_progress:-0}" \
          --argjson not_started "${_tot_not_started:-0}" \
          --argjson commented "${_commented:-0}" \
          '{user:{found:true,accountId:$accountId,username:$username,displayName:$displayName,email:$email}, summary:{created:$created,assigned:$assigned,resolved:$resolved,in_progress:$in_progress,not_started:$not_started,commented:$commented}}')
      fi
    fi
  fi
fi

prepare_create_payload() {
  local base_file
  base_file=$(mktemp)

  # Determinar base: --data (archivo o inline) > --template > esqueleto
  if [[ -n "$DATA" ]]; then
    if [[ -f "$DATA" ]]; then
      cat "$DATA" > "$base_file"
    elif [[ "$DATA" == @* ]] && [[ -f "${DATA#@}" ]]; then
      cat "${DATA#@}" > "$base_file"
    else
      printf '%s' "$DATA" > "$base_file"
    fi
  elif [[ -n "$CREATE_TEMPLATE" && -f "$CREATE_TEMPLATE" ]]; then
    cat "$CREATE_TEMPLATE" > "$base_file"
  else
    printf '%s' '{"fields":{}}' > "$base_file"
  fi

  local final_file
  final_file=$(mktemp)

  # Preparar prioridad de proyecto: flag > JSON > env
  # Pasamos flag y env por separado para que flag sobrescriba y env solo complete si falta en el payload
  jq \
    --arg p_flag "$CREATE_PROJECT" \
    --arg p_env "$JIRA_PROJECT" \
    --arg s "$CREATE_SUMMARY" \
    --arg d "$CREATE_DESCRIPTION" \
    --arg t "$CREATE_TYPE" \
    --arg a "$CREATE_ASSIGNEE" \
    --arg r "$CREATE_REPORTER" \
    --arg pr "$CREATE_PRIORITY" \
    --arg e "$CREATE_EPIC" \
    --arg link "$CREATE_LINK_ISSUE" \
    --arg api_ver "$JIRA_API_VERSION" \
    '
    . as $o
    | .fields = (.fields // {})
    | (if $p_flag != "" then .fields.project.key = $p_flag
       elif (.fields.project.key // "") == "" and $p_env != "" then .fields.project.key = $p_env
       else . end)
    | (if $s   != "" then .fields.summary     = $s else . end)
    | (if $d   != "" then .fields.description = $d else . end)
    | (if $t   != "" then .fields.issuetype.name = $t else . end)
    | (if $a   != "" then .fields.assignee.name  = $a else . end)
    | (if $r   != "" then .fields.reporter.name  = $r else . end)
    | (if $pr  != "" then .fields.priority.name  = $pr else . end)
    | (if $e   != "" then .fields.customfield_10100 = $e else . end)
    | (if $link!= "" then .fields.issuelinks = (.fields.issuelinks // [])
                        | .fields.issuelinks[0].outwardIssue.key = $link else . end)
    # Si usamos API v3 (Jira Cloud) y description es string, envolver en ADF automáticamente
    | (if ($api_ver == "3") and (.fields | has("description")) and ((.fields.description | type) == "string")
       then .fields.description = {
              "type": "doc",
              "version": 1,
              "content": [
                {"type": "paragraph", "content": [ {"type": "text", "text": .fields.description } ]}
              ]
            }
       else . end)
    ' "$base_file" > "$final_file"

  echo "$final_file"
}

# API version configurable (v3 recomendado para Cloud)
# Construcción robusta de URL: si el endpoint ya incluye /rest/api o es una URL completa,
# no anteponer nuevamente /rest/api/${JIRA_API_VERSION}
REQUEST_URL=""
if [[ "$ENDPOINT" =~ ^https?:// ]]; then
  # Endpoint completo (incluye protocolo y host)
  REQUEST_URL="$ENDPOINT"
elif [[ "$ENDPOINT" =~ ^/rest/ ]]; then
  # Endpoint ya incluye prefijo /rest/... (p.ej. /rest/api/2/...)
  REQUEST_URL="$JIRA_HOST$ENDPOINT"
else
  # Endpoint corto (p.ej. /user/search, /issue/ABC-123, /search?...)
  REQUEST_URL="$JIRA_HOST/rest/api/${JIRA_API_VERSION}$ENDPOINT"
fi

# Ejecuta la consulta
if [[ -n "$EARLY_RESPONSE" ]]; then
  RESPONSE="$EARLY_RESPONSE"
else
  # Construir argumentos para execute_curl
  curl_args=(--request "$METHOD" -H "Content-Type: application/json")
  if [[ -n "$AUTH_HEADER" ]]; then
    curl_args+=(-H "$AUTH_HEADER")
  fi
  
  if [[ "$CREATE_MODE" == "true" || ( "$METHOD" == "POST" && "$ENDPOINT" == "/issue" ) ]]; then
    FINAL_DATA_FILE=$(prepare_create_payload)
    curl_args+=(--data @"$FINAL_DATA_FILE")
  else
    if [[ -n "$DATA" ]]; then
      if [[ -f "$DATA" ]]; then
        curl_args+=(--data @"$DATA")
      else
        curl_args+=(--data "$DATA")
      fi
    fi
  fi
  
  curl_args+=("$REQUEST_URL")
  RESPONSE=$( execute_curl "${curl_args[@]}" )
fi

# Para transiciones que responden 204 (sin cuerpo), generar mensaje útil
if [[ "$TRANSITION_TARGET_SET" == "true" ]]; then
  TRANSITION_ISSUE_KEY="${identifier:-}"
  if [[ -z "$TRANSITION_ISSUE_KEY" ]]; then
    if [[ "$ENDPOINT" =~ /issue/([^/]+)/transitions$ ]]; then
      TRANSITION_ISSUE_KEY="${BASH_REMATCH[1]}"
    fi
  fi

  if [[ -z "$RESPONSE" ]]; then
    RESPONSE="{\"issue\":\"$TRANSITION_ISSUE_KEY\",\"transitionId\":\"$TRANSITION_TARGET\",\"status\":\"applied\"}"
  fi
fi

# Detectar si el endpoint debería devolver una lista o un objeto individual
# Patrones comunes en APIs REST:
# - /resource -> lista
# - /resource/{id} -> objeto individual
# - /resource?query -> lista (search)
# - /resource/{id}/subresource -> lista
# - /resource/{id}/subresource/{id} -> objeto individual

IS_SINGLE_OBJECT=false

# Si el endpoint termina con un ID específico (números, códigos como ABC-123, etc.)
if [[ "$ENDPOINT" =~ /[A-Z]+-[0-9]+$ ]] || [[ "$ENDPOINT" =~ /[0-9]+$ ]]; then
  IS_SINGLE_OBJECT=true
# Si el endpoint es para un recurso específico sin query parameters
elif [[ "$ENDPOINT" =~ ^/[^/]+/[^/?]+$ ]] && [[ ! "$ENDPOINT" =~ \? ]]; then
  IS_SINGLE_OBJECT=true
fi

if [[ "$TRANSITION_TARGET_SET" == "true" ]]; then
  IS_SINGLE_OBJECT=true
fi

# Formato de salida
case "$OUTPUT" in
  json)
    echo "$RESPONSE" | jq
    ;;
  csv)
    # Formato específico para transiciones
    if echo "$RESPONSE" | jq -e 'has("transitions")' > /dev/null 2>&1; then
      echo "ID,Name,To Status,Status Category"
      echo "$RESPONSE" | jq -r '.transitions[] | [.id, .name, .to.name, .to.statusCategory.name] | @csv'
      exit 0
    fi
    
    # CSV export idéntico al de Jira Cloud si es una búsqueda (/search?jql=...)
    if [[ "$ENDPOINT" =~ ^/search\? ]]; then
      # Extraer el valor de jql= del endpoint
      JQL_RAW="${ENDPOINT#*jql=}"
      JQL_RAW="${JQL_RAW%%&*}"
      # URL-encode con jq
      JQL_ENC=$(jq -rn --arg s "$JQL_RAW" '$s|@uri')

      case "$CSV_EXPORT_MODE" in
        all|ALL)
          EXPORT_KIND="searchrequest-csv-all-fields"
          ;;
        current|CURRENT)
          EXPORT_KIND="searchrequest-csv-current-fields"
          ;;
        *)
          echo "Tipo de csv-export inválido: $CSV_EXPORT_MODE (usa: all|current)" >&2
          exit 1
          ;;
      esac

      # Usa tempMax alto para obtener la mayor cantidad posible (el servidor puede aplicar límites)
      EXPORT_URL="$JIRA_HOST/sr/jira.issueviews:$EXPORT_KIND/temp/SearchRequest.csv?jqlQuery=$JQL_ENC&tempMax=10000"
      execute_curl --request GET -H "Accept: text/csv" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$EXPORT_URL"
      exit 0
    fi

    # Formato genérico para CSV basado en el patrón del endpoint
    if [[ "$IS_SINGLE_OBJECT" == "true" ]]; then
      # Objeto individual
      echo "$RESPONSE" | jq -r '((keys_unsorted) as $k | $k, (map(.))) | @csv'
    else
      # Lista de objetos - detectar si hay wrapper (como .issues)
      if echo "$RESPONSE" | jq -e 'has("issues")' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r 'if .issues | length > 0 then ((.issues[0] | keys_unsorted) as $h | $h, (.issues[] | [.[]])) | @csv else empty end'
      elif echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r 'if length > 0 then ((.[0] | keys_unsorted) as $h | $h, (.[ ] | [.[]])) | @csv else empty end'
      else
        echo "$RESPONSE" | jq -r '((keys_unsorted) as $k | $k, (map(.))) | @csv'
      fi
    fi
    ;;
  table)
    # Formato específico para transiciones
    if echo "$RESPONSE" | jq -e 'has("transitions")' > /dev/null 2>&1; then
      {
        echo -e "ID\tName\tTo Status\tStatus Category";
        echo "$RESPONSE" | jq -r '.transitions[] | [.id, .name, .to.name, .to.statusCategory.name] | @tsv' ;
      } | column -t -s $'\t'
      exit 0
    fi
    
    # Formato genérico para tablas basado en el patrón del endpoint
    if [[ "$IS_SINGLE_OBJECT" == "true" ]]; then
      # Objeto individual
      echo "$RESPONSE" | jq -r '(keys_unsorted | join("\t")), (to_entries | map(.value | tostring) | join("\t"))'
    else
      # Lista de objetos - detectar si hay wrapper (como .issues)
      if echo "$RESPONSE" | jq -e 'has("issues")' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r 'if .issues | length > 0 then (.issues[0] | keys_unsorted | join("\t")), (.issues[] | to_entries | map(.value | tostring) | join("\t")) else empty end'
      elif echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r 'if length > 0 then (.[0] | keys_unsorted | join("\t")), (.[] | to_entries | map(.value | tostring) | join("\t")) else empty end'
      else
        echo "$RESPONSE" | jq -r '(keys_unsorted | join("\t")), (to_entries | map(.value | tostring) | join("\t"))'
      fi
    fi
    ;;
  yaml)
    echo "$RESPONSE" | yq -P
    ;;
  md)
    # Formato específico para transiciones
    if echo "$RESPONSE" | jq -e 'has("transitions")' > /dev/null 2>&1; then
      echo "| ID | Name | To Status | Status Category |"
      echo "|---|---|---|---|"
      echo "$RESPONSE" | jq -r '.transitions[] | "|" + .id + "|" + .name + "|" + .to.name + "|" + .to.statusCategory.name + "|"'
      exit 0
    fi
    # Formato genérico para markdown basado en el patrón del endpoint
    if [[ "$IS_SINGLE_OBJECT" == "true" ]]; then
      # Objeto individual
      echo "$RESPONSE" | jq -r '"| Key | Value |", "|---|---|", (to_entries | map("| " + .key + " | " + (.value | tostring) + " |") | join("\n"))'
    else
      # Lista de objetos - detectar si hay wrapper (como .issues)
      if echo "$RESPONSE" | jq -e 'has("issues")' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r 'if .issues | length > 0 then "| " + (.issues[0] | keys_unsorted | join(" | ")) + " |", "|" + (.issues[0] | keys_unsorted | map("---") | join("|")) + "|", (.issues[] | "| " + (to_entries | map(.value | tostring) | join(" | ")) + " |") else "No data" end'
      elif echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r 'if length > 0 then "| " + (.[0] | keys_unsorted | join(" | ")) + " |", "|" + (.[0] | keys_unsorted | map("---") | join("|")) + "|", (.[] | "| " + (to_entries | map(.value | tostring) | join(" | ")) + " |") else "No data" end'
      else
        echo "$RESPONSE" | jq -r '"| Key | Value |", "|---|---|", (to_entries | map("| " + .key + " | " + (.value | tostring) + " |") | join("\n"))'
      fi
    fi
    ;;
  *)
    echo "$RESPONSE"
    ;;
esac
