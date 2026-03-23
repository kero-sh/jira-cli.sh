#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

# Load common library (handles helpers.sh loading with fallbacks)
# shellcheck source=/dev/null
source "$DIR/../lib/common.sh"

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
# jira profile          - Obtiene información del perfil del usuario actual
# jira api <endpoint> [--method METHOD] [--field key=value] [--raw-field key=value] [--data FILE|JSON] [--header KEY:VALUE]

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
JIRA_USER="${JIRA_USER:-}"
JIRA_PASSWORD="${JIRA_PASSWORD:-}"
JIRA_PROJECT="${JIRA_PROJECT:-}"
METHOD="GET"
ENDPOINT=""
DATA=""
OUTPUT="json"
CSV_EXPORT_MODE="all" # all|current para exportador oficial de Jira Cloud (solo /search)
COMMENT_SCAN_MAX="" # Límite de comentarios a escanear (usa $JIRA_ACTIVITY_COMMENT_SCAN_MAX por defecto)
SHOW_TRANSITIONS=false
TRANSITION_TARGET=""
TRANSITION_TARGET_SET=false
TRANSITION_SPEC=""
CREATE_MODE=false
PAGINATE=false
API_MODE=false
ASSIGN_TARGET=""
ASSIGN_TARGET_SET=false
API_METHOD=""
API_FIELDS=()
API_RAW_FIELDS=()
API_HEADERS=()
API_INPUT=""
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

# Subcommands/state for 'project'
PROJECT_SUBCOMMAND=""
PROJECT_WORKFLOW_ISSUETYPE=""
# Export/import components
COMPONENTS_EXPORT=false
COMPONENTS_IMPORT=false
COMPONENTS_FORMAT=""

# Subcommands/state for 'issue'
ISSUE_SUBCOMMAND=""
COMMENT_MESSAGE=""
# Move issue to another project (jira [issue] KEY --move PROJ | jira move KEY --to-project PROJ)
ISSUE_MOVE_MODE=false
ISSUE_MOVE_TARGET_PROJECT=""
ISSUE_MOVE_COMPONENTS_OVERRIDE=""
ISSUE_MOVE_YES=false

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
  project components <project> - Lista los componentes de un proyecto
  project statuses <project>   - Obtiene workflows/estados por tipo de issue en un proyecto
  project <key> --workflow [issuetype] - Muestra workflow y transiciones para un tipo de issue
  issue [key]        - Obtiene issue(s). Sin key lista los asignados
                       Con --transitions muestra transiciones disponibles
                       Con --assign/--unassign gestiona la asignación del issue
                       Con --move PROJ clona el issue en otro proyecto (mover entre tableros)
  move [key]         - Atajo: jira move KEY --to-project PROJ (equivale a issue KEY --move PROJ)
  issue-for-branch [key] - Obtiene datos de un issue para crear una rama (campos limitados)
  open <key>         - Abre el issue en el navegador (usa \$JIRA_HOST/browse/<key>)
  search [jql]       - Busca con JQL. Sin JQL busca asignados a ti
  create             - Crea un issue (usa --data)
  priority           - Lista todas las prioridades
  status             - Lista todos los estados
  workflow           - Lista todos los workflows
  user [username]    - Busca usuario(s)
  user get <term>    - Obtiene el perfil completo del usuario
  user search <term> - Busca usuarios por texto/email/username
  profile            - Obtiene información del perfil del usuario actual
  api <endpoint>     - Realiza peticiones HTTP directas a la API de Jira
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
  --paginate         - Para search: recorre todas las páginas de resultados automáticamente
  --transitions      - Para issue: muestra transiciones disponibles; con --to ID ejecuta transición
  --to ID            - ID de transición a aplicar cuando se usa --transitions
  --transition SPEC  - Para issue: aplica transición por ID, nombre de transición o nombre de estado destino
  --assign [me|email|user|none] - Asigna el issue a un usuario (me=ti mismo, none=sin asignación)
  --unassign         - Alias para --assign none (deja el issue sin asignación)
  --move PROJ        - Para issue: clona el issue en el proyecto PROJ (mover entre tableros)
  --components A,B   - Con --move: lista de componentes destino (sobrescribe los del origen)
  --yes              - Con --move: no preguntar (tipo de issue, crear componentes)
  --shell SHELL      - Genera script de autocompletado: bash, zsh
  --dry-run          - Imprime el comando curl en lugar de ejecutarlo
  --help             - Muestra esta ayuda

PARA OPCIÓN ESPECÍFICAS DE CADA SUBCOMANDO: usa 'jira <subcomando> --help'

VARIABLES DE ENTORNO:
  --jira-host HOST    - URL base de Jira (default: $JIRA_HOST)
  --jira-token TOKEN - Token OAuth Bearer o Basic Auth pre-codificado en base64 (default: $JIRA_TOKEN)
  --jira-user USER   - Usuario para Basic Auth (default: $JIRA_USER)
  --jira-password PASS - Password para Basic Auth (default: $JIRA_PASSWORD)
  --jira-email EMAIL - Email de tu cuenta para Basic Auth (default: $JIRA_EMAIL)
  --jira-api-token TOKEN - API token de Atlassian para Basic Auth (default: $JIRA_API_TOKEN)
  --jira-api-version NUM - Versión API: 3 (Cloud) o 2 (Server/DC) (default: $JIRA_API_VERSION)
  --jira-auth TYPE   - Tipo autenticación: basic|bearer (default: $JIRA_AUTH o autodetecta)
  --jira-project KEY - Clave de proyecto por defecto para 'create' (default: $JIRA_PROJECT)

AUTENTICACIÓN:
  Basic Auth (3 formas):
    1. JIRA_AUTH=basic + JIRA_TOKEN=<base64_de_user:pass>
    2. JIRA_AUTH=basic + JIRA_USER=<user> + JIRA_PASSWORD=<pass>
    3. JIRA_AUTH=basic + JIRA_EMAIL=<email> + JIRA_API_TOKEN=<token>
  
  Bearer Auth:
    JIRA_AUTH=bearer + JIRA_TOKEN=<oauth_token>
  
  Auto-detección (sin JIRA_AUTH):
    - Si JIRA_TOKEN decodifica a user:pass → Basic Auth
    - Si JIRA_TOKEN no decodifica → Bearer Auth

FORMATOS DE SALIDA:
  json               - JSON formateado (por defecto)
  csv                - Valores separados por comas
  table              - Tabla con columnas separadas por tabs
  yaml               - Formato YAML
  md                 - Tabla en formato Markdown

EJEMPLOS:
  # Sintaxis simplificada
  jira priority --output table
  jira project CORE --output json
  jira project components PROJ
  jira project statuses PROJ
  jira workflow --output table
  jira issue ABC-123
  jira issue ABC-123 --transitions
  jira issue ABC-123 --transitions --to 611
  jira issue ABC-123 --assign me              # Asignar a mi usuario
  jira issue ABC-123 --assign user@dom.com    # Asignar a usuario específico
  jira issue ABC-123 --unassign               # Dejar sin asignación
  jira search 'project=ABC AND status=Open'
  jira create --data '{"fields":{"project":{"key":"ABC"},"summary":"Nuevo ticket","issuetype":{"name":"Task"}}}'
  jira create --data ./payload.json
  jira create --data ./payload.json --priority High --assignee user1
  jira create --project ABC --summary "Titulo" --description "Desc" --type Task
  jira user carlos.herrera

  # Sintaxis tradicional
  jira GET /priority --output table
  jira GET /project/CORE
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

# Help for 'jira project'
show_help_project() {
  cat << EOF
Uso: jira project [id|comando] [opciones]

Descripción:
  Obtiene información de proyecto(s). Sin ID lista todos los proyectos disponibles.

Comandos:
  components <project>  Lista los componentes de un proyecto
  statuses <project>    Obtiene workflows/estados por tipo de issue en un proyecto
  <project> --workflow [issuetype]  Muestra el workflow y transiciones de un tipo de issue específico

Opciones:
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  --workflow [issuetype]  Filtra el workflow por tipo de issue (ej: Task, Bug, Story)
  --export           (solo components) Exporta la lista de componentes a stdout
  --import           (solo components) Importa componentes desde stdin
  --format FORMAT    (con --export/--import) json, csv, yaml o tsv (por defecto: json)
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira project                    # Lista todos los proyectos
  jira project CORE               # Obtiene el proyecto CORE
  jira project --output table     # Lista en formato tabla
  jira project components PROJ    # Lista componentes del proyecto PROJ
  jira project components PROJ --export --format json > comps.json
  jira project components PROJ --import --format json < comps.json
  jira project statuses PROJ      # Obtiene workflows/estados del proyecto PROJ
  jira project PROJ --workflow Task   # Muestra el workflow para tipo Task en proyecto PROJ
  jira project PROJ --workflow Story  # Muestra el workflow para tipo Story en proyecto PROJ
EOF
}

# Help for 'jira issue'
show_help_issue() {
  cat << EOF
Uso: jira issue [key] [opciones]
     jira issue comment [key] -m "mensaje" [opciones]
     jira [key] --move PROJ   # Mover (clonar) issue a otro proyecto
     jira move [key] --to-project PROJ [opciones]

Descripción:
  Obtiene información de issue(s). Sin key lista los asignados a ti.
  Con --transitions muestra transiciones disponibles.
  Con 'comment' agrega un comentario al issue.
  Con --move PROJ clona el issue en el proyecto PROJ (crea components/labels si faltan, enlaza al original).

Comandos:
  comment [key]      Agrega un comentario al issue especificado

Opciones:
  --transitions      Muestra transiciones disponibles
  --to ID            ID de transición a aplicar (requiere --transitions)
  --transition SPEC  Aplica transición por ID, nombre de transición o nombre de estado destino
  --assign [me|email|user|none] Asigna el issue a un usuario
  --unassign         Deja el issue sin asignación (alias de --assign none)
  --move PROJ        Clona el issue en el proyecto PROJ (mover entre tableros/proyectos)
  --components A,B   Lista de componentes para el issue destino (sobrescribe los del origen)
  --yes              Modo no interactivo: no pregunta tipo ni creación de componentes
  -m, --message      Mensaje del comentario (requerido para comment)
  --comment-scan-max NUM - Límite de comentarios a escanear (default: $JIRA_ACTIVITY_COMMENT_SCAN_MAX o 100)
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira issue                      # Lista issues asignados a ti
  jira issue ABC-123              # Obtiene el issue ABC-123
  jira issue ABC-123 --move PROJ2 # Clona ABC-123 en el proyecto PROJ2
  jira ABC-123 --move PROJ2      # Mismo efecto (atajo)
  jira move ABC-123 --to-project PROJ2 --components Frontend,Backend --yes
  jira issue ABC-123 --transitions # Muestra transiciones disponibles
  jira issue ABC-123 --transitions --to 611  # Ejecuta transición
  jira issue ABC-123 --transition "Done"     # Cambia a estado Done (por nombre de estado)
  jira issue ABC-123 --assign me            # Asignar a mi usuario
  jira issue comment ABC-123 -m "Comentario aquí"  # Agrega comentario
  echo "mensaje" | jira issue comment ABC-123 -m -  # Comentario desde pipe
EOF
}

# Help for 'jira search'
show_help_search() {
  cat << EOF
Uso: jira search [jql] [opciones]

Descripción:
  Busca issues con JQL. Sin JQL busca issues asignados a ti.

Opciones:
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  --csv-export TYPE  Para csv: modo de exportación (all|current)
  --paginate         Recorre todas las páginas de resultados automáticamente
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira search                                    # Issues asignados a ti
  jira search 'project=ABC AND status=Open'     # Búsqueda con JQL
  jira search 'assignee=currentUser()' --output md
  jira search 'project=ABC' --paginate          # Obtiene todos los resultados paginando
EOF
}

# Help for 'jira create'
show_help_create() {
  cat << EOF
Uso: jira create [opciones]

Descripción:
  Crea un nuevo issue en Jira.

Opciones:
  --data '{json}'    Datos JSON para crear (también acepta ruta a archivo)
  --project KEY      Proyecto/tablero donde se crea el issue (obligatorio si no usas --data)
  --summary TEXT     Resumen/título del issue
  --description TXT  Descripción del issue
  --type NAME        Tipo de issue (ej: Task, Bug)
  --assignee NAME    Usuario asignado (username)
  --reporter NAME    Usuario reportero (username)
  --priority NAME    Prioridad por nombre (ej: High)
  --epic KEY         Epic Link (customfield_10100)
  --link-issue KEY   Vincula a otro issue
  --template FILE    Plantilla JSON base
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira create --data '{"fields":{"project":{"key":"ABC"},"summary":"Test","issuetype":{"name":"Task"}}}'
  jira create --data ./payload.json
  jira create --project ABC --summary "Title" --type Task
  jira api /search?jql=project=ABC
  jira api /issue --method POST --field summary='New Issue' --field project='ABC'
  jira api /issue/ABC-123 --method PUT --field summary='Updated Title'
  jira api /search --raw-field jql='status=Open' --header 'Accept: application/json'
EOF
}

# Help for 'jira profile'
show_help_profile() {
  cat << EOF
Uso: jira profile [opciones]

Descripción:
  Obtiene información del perfil del usuario actual autenticado.
  Utiliza el endpoint /myself de la API de Jira que devuelve los detalles
  del usuario basado en el token de autenticación proporcionado.

Opciones:
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  -h, --help         Muestra esta ayuda

Información devuelta:
  - accountId: ID único de la cuenta Atlassian
  - displayName: Nombre visible del usuario
  - emailAddress: Correo electrónico del usuario
  - active: Estado de la cuenta (true/false)
  - timeZone: Zona horaria configurada
  - avatarUrls: URLs de los avatares en diferentes tamaños
  - groups: Grupos a los que pertenece el usuario
  - applicationRoles: Roles de aplicación asignados

Ejemplos:
  # Obtener perfil en formato JSON (por defecto)
  jira profile
  
  # Obtener perfil en formato tabla
  jira profile --output table
  
  # Obtener perfil en formato CSV
  jira profile --output csv
  
  # Obtener perfil en formato Markdown
  jira profile --output md

Notas:
  - Requiere autenticación válida (token o email+API token)
  - La información devuelta está sujeta a la configuración de privacidad
    del usuario en su cuenta Atlassian
  - Funciona tanto con Jira Cloud (v3) como Jira Server/Data Center (v2)
EOF
}

# Help for 'jira api'
show_help_api() {
  cat << EOF
Uso: jira api <endpoint> [opciones]

Descripción:
  Realiza peticiones HTTP directas a la API de Jira, similar a glab api.
  Soporta métodos GET, POST, PUT y construcción automática de payload.

Opciones:
  --method METHOD    Método HTTP: GET, POST, PUT (por defecto: GET, cambia a POST si hay campos)
  --field key=value  Agrega parámetro con inferencia de tipo (true/false/null/number/@file)
  --raw-field key=value - Agrega parámetro como string (sin inferencia de tipo)
  --header KEY:VALUE - Agrega header HTTP adicional
  --input FILE|JSON  Archivo o JSON para el body de la petición (usa - para stdin)
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  -h, --help         Muestra esta ayuda

Inferencia de tipos para --field:
  true, false, null -> Se convierten a tipos JSON correspondientes
  números (123)      -> Se convierten a números JSON
  @archivo           -> Lee el contenido del archivo
  @-                 -> Lee desde stdin
  otro texto         -> Se mantiene como string

Ejemplos:
  # Búsqueda simple (GET por defecto)
  jira api /search?jql=project=ABC
  
  # Crear issue con campos (POST automático por --field)
  jira api /issue --field summary='New Issue' --field project='ABC' --field issuetype='Task'
  
  # Actualizar issue con método explícito
  jira api /issue/ABC-123 --method PUT --field summary='Updated Title'
  
  # Usar archivo como payload
  jira api /issue --method POST --input payload.json
  
  # Leer payload desde stdin
  echo '{"fields":{"summary":"From stdin"}}' | jira api /issue --input -
  
  # Agregar headers personalizados
  jira api /search --header 'Accept: application/json' --header 'X-Custom: value'
  
  # Campos con tipos especiales
  jira api /issue --field priority='High' --field customfield_10100='EPIC-123' --field flag=true

Notas:
  - El endpoint debe comenzar con / o ser una URL completa
  - Si especificas --field o --raw-field, el método cambia automáticamente a POST
  - Puedes combinar --field (con inferencia) y --raw-field (siempre string)
  - Los headers adicionales se agregan a los headers de autenticación por defecto
EOF
}

# Help for 'jira priority'
show_help_priority() {
  cat << EOF
Uso: jira priority [opciones]

Descripción:
  Lista todas las prioridades disponibles.

Opciones:
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira priority
  jira priority --output table
EOF
}

# Help for 'jira status'
show_help_status() {
  cat << EOF
Uso: jira status [opciones]

Descripción:
  Lista todos los estados disponibles.

Opciones:
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira status
  jira status --output table
EOF
}

# Help for 'jira workflow'
show_help_workflow() {
  cat << EOF
Uso: jira workflow [id] [opciones]

Descripción:
  Lista todos los workflows disponibles. Con ID obtiene un workflow específico.
  Para obtener workflows por proyecto y tipo de issue, usa: jira project statuses <PROJECT>

Opciones:
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira workflow                    # Lista todos los workflows
  jira workflow --output table     # Lista en formato tabla
  jira project statuses PROJ       # Obtiene workflows/estados por tipo de issue del proyecto PROJ
EOF
}

# Help for 'jira issuetype'
show_help_issuetype() {
  cat << EOF
Uso: jira issuetype [opciones]

Descripción:
  Lista todos los tipos de issue disponibles.

Opciones:
  --output FORMAT    Formato de salida: json, csv, table, yaml, md
  -h, --help         Muestra esta ayuda

Ejemplos:
  jira issuetype
  jira issuetype --output table
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
    resources="project projects issue issues move search create priority priorities status statuses user users issuetype issuetypes field fields resolution resolutions component components version versions"

    # Métodos HTTP
    methods="GET POST PUT"

    # Opciones
    opts="--data --token --host --output --csv-export --transitions --to --help --shell --project --summary --description --type --assignee --reporter --priority --epic --link-issue --template --dry-run --assign --unassign -m --message --export --import --format --move --components --yes"

    # Formatos de salida
    formats="json csv table yaml md"
    export_formats="json csv yaml tsv"

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
        project|projects)
            local project_subs="components statuses -h --help"
            COMPREPLY=( $(compgen -W "${project_subs}" -- ${cur}) )
            return 0
            ;;
        components)
            local component_opts="--export --import --format --output -h --help"
            COMPREPLY=( $(compgen -W "${component_opts}" -- ${cur}) )
            return 0
            ;;
        --format)
            COMPREPLY=( $(compgen -W "${export_formats}" -- ${cur}) )
            return 0
            ;;
        issue|issues)
            local issue_subs="comment --transitions --to --assign --unassign --move --components --yes -h --help"
            COMPREPLY=( $(compgen -W "${issue_subs}" -- ${cur}) )
            return 0
            ;;
        comment)
            # Después de 'issue comment', sugerir opciones de comentario
            local comment_opts="-m --message --output -h --help"
            COMPREPLY=( $(compgen -W "${comment_opts}" -- ${cur}) )
            return 0
            ;;
        move)
            local move_opts="--to-project --components --yes -h --help"
            COMPREPLY=( $(compgen -W "${move_opts}" -- ${cur}) )
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
        'move:Mueve issue a otro proyecto'
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
        '--assign[Asignar issue a usuario]:assign target' \
        '--unassign[Dejar issue sin asignación]' \
        '-m[Mensaje del comentario]:message' \
        '--message[Mensaje del comentario]:message' \
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
        '--move[Mover issue a proyecto]:project key' \
        '--components[Components para move]:components' \
        '--yes[Modo no interactivo para move]' \
        '--to-project[Proyecto destino para move]:project key' \
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
                    _values "issue subcommands" \
                      'comment:Agregar comentario a un issue' \
                      || _message "Clave del issue (ej: ABC-123)"
                    ;;
                move)
                    _message "Clave del issue (ej: ABC-123)"
                    ;;
                user|users)
                    _values "user subcommands" \
                      'get:Perfil completo por email/username/accountId' \
                      'search:Buscar usuarios por texto' \
                      'activity:Resumen de actividad del usuario'
                    ;;
                components)
                    _message "Clave del proyecto"
                    ;;
                component|version|versions)
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
                '--assign[Asignar issue a usuario]:assign target' \
                '--unassign[Dejar issue sin asignación]' \
                '--message[Mensaje del comentario]:message' \
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
      if [[ "$PROJECT_SUBCOMMAND" == "components" ]]; then
        # List components for a project
        if [[ -n "$identifier" ]]; then
          ENDPOINT="/project/$identifier/components"
        else
          echo "Error: 'jira project components' requiere una clave de proyecto" >&2
          echo "Ejemplo: jira project components PROJ" >&2
          exit 1
        fi
      elif [[ "$PROJECT_SUBCOMMAND" == "statuses" ]]; then
        # Get workflows/statuses by issue type for a project
        if [[ -n "$identifier" ]]; then
          ENDPOINT="/project/$identifier/statuses"
        else
          echo "Error: 'jira project statuses' requiere una clave de proyecto" >&2
          echo "Ejemplo: jira project statuses PROJ" >&2
          exit 1
        fi
      elif [[ -n "$PROJECT_WORKFLOW_ISSUETYPE" ]]; then
        # Get workflow for a specific issue type in project
        if [[ -n "$identifier" ]]; then
          ENDPOINT="/project/$identifier/statuses"
          # El filtrado por issuetype se hará después de obtener la respuesta
        else
          echo "Error: 'jira project --workflow' requiere una clave de proyecto" >&2
          echo "Ejemplo: jira project PROJ --workflow Task" >&2
          exit 1
        fi
      elif [[ -n "$identifier" ]]; then
        ENDPOINT="/project/$identifier"
      else
        ENDPOINT="/project"
      fi
      ;;
    issue|issues)
      if [[ "$ISSUE_SUBCOMMAND" == "comment" ]]; then
        # Comando para agregar comentario
        if [[ -n "$identifier" ]]; then
          ENDPOINT="/issue/$identifier/comment"
          METHOD="POST"
        else
          echo "Error: 'jira issue comment' requiere una clave de issue" >&2
          echo "Ejemplo: jira issue comment ABC-123 -m 'Mensaje del comentario'" >&2
          exit 1
        fi
      elif [[ -n "$identifier" ]]; then
        if [[ "$SHOW_TRANSITIONS" == "true" ]]; then
          ENDPOINT="/issue/$identifier/transitions"
        else
          ENDPOINT="/issue/$identifier"
        fi
      else
        ENDPOINT="/search?jql=assignee=currentUser()"
      fi
      ;;
    issue-for-branch)
      if [[ -n "$identifier" ]]; then
        local fields="summary,issuetype,priority,status,resolution"
        ENDPOINT="/issue/$identifier?fields=$fields"
      else
        echo "Error: issue-for-branch requires an issue key" >&2
        exit 1
      fi
      ;;
    search)
      if [[ -n "$identifier" ]]; then
        # Si el identificador ya contiene JQL, usarlo directamente
        if [[ "$identifier" =~ ^jql= ]]; then
          ENDPOINT="/search?$identifier"
        else
          # Codificar correctamente la consulta JQL para URL usando jq
          local jql_encoded
          jql_encoded=$(jq -rn --arg s "$identifier" '$s|@uri')
          ENDPOINT="/search?jql=$jql_encoded"
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
    workflow|workflows)
      if [[ -n "$identifier" ]]; then
        # Get specific workflow by ID
        ENDPOINT="/workflow/$identifier"
      else
        # List all workflows
        ENDPOINT="/workflow"
      fi
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
    api)
      # Modo API directo - el endpoint es el identificador
      API_MODE=true
      if [[ -n "$identifier" ]]; then
        ENDPOINT="$identifier"
      else
        echo "Error: 'jira api' requiere un endpoint" >&2
        echo "Ejemplo: jira api /search?jql=project=ABC" >&2
        exit 1
      fi
      ;;
    profile|myself)
      # Obtener perfil del usuario actual
      ENDPOINT="/myself"
      ;;
    *)
      echo "Recurso no reconocido: $resource" >&2
      echo "Recursos disponibles: project, issue, search, priority, status, workflow, user, profile, api, issuetype, field, resolution, component, version" >&2
      exit 1
      ;;
  esac
}

# Move issue to another project (clone + link). Uses globals: identifier, ISSUE_MOVE_*,
# JIRA_HOST, AUTH_HEADER, JIRA_API_VERSION, execute_curl, DRY_RUN, ISSUE_MOVE_YES.
do_issue_move() {
  local _base="$JIRA_HOST/rest/api/${JIRA_API_VERSION}"
  local _issue_url="$_base/issue/$identifier"
  local _fields="project,summary,description,issuetype,components,labels"
  local _src_json _src_summary _src_desc _src_type _src_components _src_labels
  local _issuetypes_json _target_type_id _target_type_name
  local _comps_list _comps_to_ensure _comp_name _target_components_json _comp_id
  local _payload _create_resp _new_key _project_key

  if [[ -z "$JIRA_HOST" ]] || [[ -z "$AUTH_HEADER" ]]; then
    error "JIRA_HOST y autenticación son necesarios para mover el issue." >&2
    return 1
  fi

  # 1) Obtener issue origen
  _src_json=$(execute_curl -H "Accept: application/json" -H "$AUTH_HEADER" "${_issue_url}?fields=${_fields}" 2>/dev/null)
  if ! printf '%s' "$_src_json" | jq -e '.key' >/dev/null 2>&1; then
    error "No se pudo obtener el issue $identifier. ¿Existe y tienes permiso?" >&2
    printf '%s' "$_src_json" | jq -r '.errorMessages[]? // .errors | to_entries[]? | "\(.key): \(.value)"' 2>/dev/null | head -5 >&2
    return 1
  fi

  _src_summary=$(printf '%s' "$_src_json" | jq -r '.fields.summary // ""')
  _src_desc=$(printf '%s' "$_src_json" | jq -c '.fields.description // empty')
  _src_type=$(printf '%s' "$_src_json" | jq -r '.fields.issuetype.name // "Task"')
  _src_components=$(printf '%s' "$_src_json" | jq -r '[.fields.components[]? | .name] | join("\n")')
  _src_labels=$(printf '%s' "$_src_json" | jq -r '(.fields.labels // []) | join("\n")')

  # 2) Resolver tipo de issue en proyecto destino (tipos centrales: misma lista global)
  _issuetypes_json=$(execute_curl -H "Accept: application/json" -H "$AUTH_HEADER" "$_base/issuetype" 2>/dev/null)
  _target_type_id=$(printf '%s' "$_issuetypes_json" | jq -r --arg n "$_src_type" '
    if type == "array" then . else (.values // .) end
    | map(select(.name == $n)) | .[0].id // empty
  ')
  if [[ -z "$_target_type_id" ]]; then
    _issuetypes_json="${_issuetypes_json:-$(execute_curl -H "Accept: application/json" -H "$AUTH_HEADER" "$_base/issuetype" 2>/dev/null)}"
    _target_type_id=$(printf '%s' "$_issuetypes_json" | jq -r '
      (if type == "array" then . else (.values // []) end)
      | map(select(.name == "Task")) | .[0].id // .[0].id // empty
    ')
    _target_type_name=$(printf '%s' "$_issuetypes_json" | jq -r '
      (if type == "array" then . else (.values // []) end) | .[0].name // "Task"
    ')
    if [[ -z "$_target_type_id" ]]; then
      _target_type_id=$(printf '%s' "$_issuetypes_json" | jq -r '(if type == "array" then . else (.values // []) end) | .[0].id // empty')
      _target_type_name=$(printf '%s' "$_issuetypes_json" | jq -r '(if type == "array" then . else (.values // []) end) | .[0].name // "Task"')
    fi
    if [[ "$ISSUE_MOVE_YES" != "true" ]]; then
      echo "El tipo '$_src_type' no existe en el proyecto destino. Tipos disponibles:" >&2
      printf '%s' "$_issuetypes_json" | jq -r '
        (if type == "array" then . else (.values // []) end)
        | to_entries[] | "  \(.key + 1). \(.value.name)" 
      ' >&2
      local _num
      read -r -p "Número (o nombre del tipo) a usar [$_target_type_name]: " _num
      if [[ -n "$_num" ]]; then
        if [[ "$_num" =~ ^[0-9]+$ ]]; then
          _target_type_id=$(printf '%s' "$_issuetypes_json" | jq -r --argjson i "$((_num - 1))" '
            (if type == "array" then . else (.values // []) end) | .[$i].id // empty
          ')
          _target_type_name=$(printf '%s' "$_issuetypes_json" | jq -r --argjson i "$((_num - 1))" '
            (if type == "array" then . else (.values // []) end) | .[$i].name // empty
          ')
        else
          _target_type_id=$(printf '%s' "$_issuetypes_json" | jq -r --arg n "$_num" '
            (if type == "array" then . else (.values // []) end) | map(select(.name == $n)) | .[0].id // empty
          ')
          _target_type_name="$_num"
        fi
      fi
    fi
    if [[ -z "$_target_type_id" ]]; then
      _target_type_id=$(printf '%s' "$_issuetypes_json" | jq -r '(if type == "array" then . else (.values // []) end) | .[0].id // empty')
      _target_type_name=$(printf '%s' "$_issuetypes_json" | jq -r '(if type == "array" then . else (.values // []) end) | .[0].name // "Task"')
    fi
  else
    _target_type_name="$_src_type"
  fi

  if [[ -z "$_target_type_id" ]]; then
    error "No se pudo resolver un tipo de issue para el proyecto destino." >&2
    return 1
  fi

  # 3) Lista de components a asignar (override o copia del origen)
  # Con set -e, grep sin coincidencias devuelve 1 y sale el script; || true evita eso
  if [[ -n "$ISSUE_MOVE_COMPONENTS_OVERRIDE" ]]; then
    _comps_to_ensure=$(printf '%s' "$ISSUE_MOVE_COMPONENTS_OVERRIDE" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' || true)
  else
    _comps_to_ensure=$(printf '%s' "$_src_components" | grep -v '^$' || true)
  fi

  _target_components_json="[]"
  if [[ -n "$_comps_to_ensure" ]]; then
    _target_components_json=$(printf '%s' "$_comps_to_ensure" | while IFS= read -r _comp_name; do
      [[ -z "$_comp_name" ]] && continue
      _comp_id=$(execute_curl -H "Accept: application/json" -H "$AUTH_HEADER" "$_base/project/$ISSUE_MOVE_TARGET_PROJECT/components" 2>/dev/null \
        | jq -r --arg n "$_comp_name" '.[] | select(.name == $n) | .id' | head -1)
      if [[ -z "$_comp_id" ]]; then
        if [[ "$ISSUE_MOVE_YES" != "true" ]]; then
          read -r -p "El componente '$_comp_name' no existe en $ISSUE_MOVE_TARGET_PROJECT. ¿Crear y asignar? [Y/n]: " _yn
          _yn="${_yn:-Y}"
          if [[ "${_yn^^}" != "Y" && "${_yn^^}" != "YES" ]]; then
            continue
          fi
        fi
        local _create_comp
        _create_comp=$(execute_curl --request POST -H "Content-Type: application/json" -H "$AUTH_HEADER" \
          -H "Accept: application/json" --data "{\"name\":$(printf '%s' "$_comp_name" | jq -Rs .),\"project\":$(printf '%s' "$ISSUE_MOVE_TARGET_PROJECT" | jq -Rs .)}" \
          "$_base/component" 2>/dev/null)
        _comp_id=$(printf '%s' "$_create_comp" | jq -r '.id // empty')
        if [[ -n "$_comp_id" ]]; then
          echo "Componente creado: $_comp_name" >&2
        else
          echo "Error creando componente '$_comp_name', se omite." >&2
          continue
        fi
      fi
      if [[ -n "$_comp_id" ]]; then
        echo "{\"id\":\"$_comp_id\"}"
      fi
    done | jq -s -R 'split("\n") | map(select(length > 0)) | map(fromjson)')
  fi

  # 4) Payload para crear el issue en el proyecto destino
  _payload=$(jq -n \
    --arg proj "$ISSUE_MOVE_TARGET_PROJECT" \
    --argjson itid "$_target_type_id" \
    --arg sum "$_src_summary" \
    --argjson comps "$_target_components_json" \
    --argjson labs "$(printf '%s' "$_src_labels" | grep -v '^$' || true | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
    '
      {
        fields: {
          project: { key: $proj },
          issuetype: { id: ($itid | tostring) },
          summary: $sum,
          components: $comps,
          labels: $labs
        }
      }
    ')
  # Añadir description si existe (v3 ADF o string)
  if [[ -n "$_src_desc" ]] && [[ "$_src_desc" != "null" ]]; then
    if printf '%s' "$_src_desc" | jq -e 'type == "object"' >/dev/null 2>&1; then
      _payload=$(printf '%s' "$_payload" | jq --argjson d "$_src_desc" '.fields.description = $d')
    else
      local _desc_str
      _desc_str=$(printf '%s' "$_src_desc" | jq -r '. // ""')
      if [[ -n "$_desc_str" ]]; then
        if [[ "$JIRA_API_VERSION" == "3" ]]; then
          _payload=$(printf '%s' "$_payload" | jq --arg t "$_desc_str" '.fields.description = {
            type: "doc", version: 1,
            content: [{ type: "paragraph", content: [{ type: "text", text: $t }] }]
          }')
        else
          _payload=$(printf '%s' "$_payload" | jq --arg t "$_desc_str" '.fields.description = $t')
        fi
      fi
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] POST $_base/issue" >&2
    printf '%s' "$_payload" | jq . >&2
    return 0
  fi

  _create_resp=$(execute_curl --request POST -H "Content-Type: application/json" -H "$AUTH_HEADER" \
    -H "Accept: application/json" --data "$_payload" "$_base/issue" 2>/dev/null)
  _new_key=$(printf '%s' "$_create_resp" | jq -r '.key // empty')
  if [[ -z "$_new_key" ]]; then
    error "No se pudo crear el issue en el proyecto $ISSUE_MOVE_TARGET_PROJECT." >&2
    printf '%s' "$_create_resp" | jq -r '.errorMessages[]? // .errors | to_entries[]? | "\(.key): \(.value)"' 2>/dev/null | head -10 >&2
    return 1
  fi

  echo "Creado: $_new_key (proyecto $ISSUE_MOVE_TARGET_PROJECT)"
  # Enlace opcional: relacionar issue origen con el nuevo
  _payload=$(jq -n --arg inward "$identifier" --arg outward "$_new_key" '
    { type: { name: "Relates" }, inwardIssue: { key: $inward }, outwardIssue: { key: $outward } }
  ')
  _link_ok=false
  execute_curl --request POST -H "Content-Type: application/json" -H "$AUTH_HEADER" \
    -H "Accept: application/json" --data "$_payload" "$_base/issueLink" 2>/dev/null && _link_ok=true || true

  echo ""
  echo "--- Resumen ---"
  echo "  Origen:    $identifier"
  echo "  Nuevo:     $_new_key (proyecto $ISSUE_MOVE_TARGET_PROJECT)"
  echo "  Enlace:    Relates entre $identifier y $_new_key $([ "$_link_ok" = true ] && echo "(creado)" || echo "(omitido o fallido)")"
  echo "-------------"
  return 0
}

# Argument parsing
USING_SIMPLIFIED_SYNTAX=false
resource=""
identifier=""

# Normalize move syntax so the rest of the script sees "issue KEY --move PROJ"
if [[ $# -ge 1 && "$1" == "move" ]]; then
  shift
  if [[ $# -lt 1 ]]; then
    echo "Error: 'jira move' requiere clave de issue y --to-project" >&2
    echo "Ejemplo: jira move ABC-123 --to-project PROJ2" >&2
    exit 1
  fi
  _move_key="$1"
  shift
  _new_args=(issue "$_move_key")
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--to-project" && $# -ge 2 ]]; then
      _new_args+=(--move "$2")
      shift; shift
    else
      _new_args+=("$1")
      shift
    fi
  done
  set -- "${_new_args[@]}"
fi

# Normalize "jira KEY --move PROJ" to "jira issue KEY --move PROJ"
if [[ $# -ge 2 && "$1" =~ ^[A-Z][A-Z0-9_]*-[0-9]+$ ]]; then
  for ((_i=2;_i<=$#;_i++)); do
    if [[ "${!_i}" == "--move" ]]; then
      set -- issue "$1" "${@:2}"
      break
    fi
  done
fi

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
    --jira-host)
      JIRA_HOST="${temp_args[i+1]}"
      ((i++))
      ;;
    --jira-token)
      JIRA_TOKEN="${temp_args[i+1]}"
      ((i++))
      ;;
    --jira-email)
      JIRA_EMAIL="${temp_args[i+1]}"
      ((i++))
      ;;
    --jira-api-token)
      JIRA_API_TOKEN="${temp_args[i+1]}"
      ((i++))
      ;;
    --jira-api-version)
      JIRA_API_VERSION="${temp_args[i+1]}"
      ((i++))
      ;;
    --jira-auth)
      JIRA_AUTH="${temp_args[i+1]}"
      ((i++))
      ;;
    --jira-project)
      JIRA_PROJECT="${temp_args[i+1]}"
      ((i++))
      ;;
    --comment-scan-max)
      COMMENT_SCAN_MAX="${temp_args[i+1]}"
      ((i++))
      ;;
    --move)
      ISSUE_MOVE_TARGET_PROJECT="${temp_args[i+1]}"
      ((i++))
      ISSUE_MOVE_MODE=true
      ;;
    --components)
      ISSUE_MOVE_COMPONENTS_OVERRIDE="${temp_args[i+1]}"
      ((i++))
      ;;
    --yes)
      ISSUE_MOVE_YES=true
      ;;
    --data)
      DATA="${temp_args[i+1]}"
      ((i++))
      ;;
    --project)
      # Solo asignar si el siguiente argumento existe y no es otra opción (no empieza con -)
      if [[ $((i+1)) -lt ${#temp_args[@]} && -n "${temp_args[i+1]}" && ! "${temp_args[i+1]}" =~ ^- ]]; then
        CREATE_PROJECT="${temp_args[i+1]}"
      fi
      ((i++))
      ;;
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
    --transition)
      TRANSITION_SPEC="${temp_args[i+1]}"; ((i++)) ;;
    --assign)
      ASSIGN_TARGET="${temp_args[i+1]}"; ((i++)) ;;
    --unassign)
      ASSIGN_TARGET="none" ;;
    --workflow)
      # Flag opcional con valor
      if [[ $((i+1)) -lt ${#temp_args[@]} && ! "${temp_args[i+1]}" =~ ^- ]]; then
        PROJECT_WORKFLOW_ISSUETYPE="${temp_args[i+1]}"
        ((i++))
      else
        PROJECT_WORKFLOW_ISSUETYPE="__ALL__"
      fi
      ;;
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
    -m|--message)
      COMMENT_MESSAGE="${temp_args[i+1]}"; ((i++)) ;;
    --dry-run)
      DRY_RUN=true ;;
    --paginate)
      PAGINATE=true ;;
    # Opciones para 'project components' export/import
    --export)
      COMPONENTS_EXPORT=true ;;
    --import)
      COMPONENTS_IMPORT=true ;;
    --format)
      COMPONENTS_FORMAT="${temp_args[i+1]}"; ((i++)) ;;
    # Opciones para 'api'
    --method)
      API_METHOD="${temp_args[i+1]}"; ((i++)) ;;
    --field|-f)
      API_FIELDS+=("${temp_args[i+1]}"); ((i++)) ;;
    --raw-field|-F)
      API_RAW_FIELDS+=("${temp_args[i+1]}"); ((i++)) ;;
    --header|-H)
      API_HEADERS+=("${temp_args[i+1]}"); ((i++)) ;;
    --input)
      API_INPUT="${temp_args[i+1]}"; ((i++)) ;;
    -h|--help)
      # Don't show help immediately, let resource-specific help handle it
      SHOW_HELP_FLAG=true ;;
    --shell)
      generate_completion "${temp_args[i+1]}"; exit 0 ;;
  esac
done

# Validar opciones de export/import de componentes
if [[ "$COMPONENTS_EXPORT" == "true" && "$COMPONENTS_IMPORT" == "true" ]]; then
  echo "Error: No se puede usar --export y --import a la vez" >&2
  exit 1
fi
if [[ "$COMPONENTS_EXPORT" == "true" || "$COMPONENTS_IMPORT" == "true" ]]; then
  if [[ -z "$COMPONENTS_FORMAT" ]]; then
    COMPONENTS_FORMAT="json"
  fi
  case "$COMPONENTS_FORMAT" in
    json|csv|yaml|tsv) ;;
    *)
      echo "Error: --format debe ser uno de: json, csv, yaml, tsv" >&2
      exit 1
      ;;
  esac
fi

# If --help was used without a resource, show general help
if [[ "$SHOW_HELP_FLAG" == "true" ]] && [[ $# -eq 0 ]]; then
  show_help; exit 0
fi

# Help shortcuts: 'jira help <resource>' or 'jira <resource> -h/--help'
if [[ $# -gt 0 ]] && [[ "$1" == "help" ]]; then
  if [[ $# -gt 1 ]]; then
    case "$2" in
      user|users)       show_help_user; exit 0 ;;
      project|projects) show_help_project; exit 0 ;;
      issue|issues|move) show_help_issue; exit 0 ;;
      search)           show_help_search; exit 0 ;;
      create)           show_help_create; exit 0 ;;
      priority)         show_help_priority; exit 0 ;;
      status)           show_help_status; exit 0 ;;
      workflow)         show_help_workflow; exit 0 ;;
      profile|myself)   show_help_profile; exit 0 ;;
      api)              show_help_api; exit 0 ;;
      issuetype)        show_help_issuetype; exit 0 ;;
      *)                show_help; exit 0 ;;
    esac
  else
    show_help; exit 0
  fi
fi

# Comando directo: 'jira open KEY' → abre el issue en el navegador
if [[ $# -gt 0 && "$1" == "open" ]]; then
  shift
  if [[ $# -lt 1 ]]; then
    echo "Error: 'jira open' requiere una clave de issue" >&2
    echo "Ejemplo: jira open ABC-123" >&2
    exit 1
  fi

  ISSUE_KEY="$1"

  if [[ -z "$JIRA_HOST" ]]; then
    error "Debes especificar la URL de Jira con --host o la variable de entorno JIRA_HOST" >&2
    exit 1
  fi

  # Asegurar que el host tenga esquema para que open/xdg-open funcione
  _open_base="${JIRA_HOST%/}"
  if [[ ! "$_open_base" =~ ^https?:// ]]; then
    _open_base="https://$_open_base"
  fi
  ISSUE_URL="${_open_base}/browse/$ISSUE_KEY"

  if command -v open >/dev/null 2>&1; then
    open "$ISSUE_URL"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$ISSUE_URL"
  else
    echo "No se encontró un comando para abrir el navegador (open/xdg-open)." >&2
    echo "URL del issue: $ISSUE_URL" >&2
    exit 1
  fi

  exit 0
fi

# Alias: 'jira comment <key>' => 'jira issue comment <key>'
if [[ $# -gt 0 && "$1" == "comment" ]]; then
  set -- issue comment "${@:2}"
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
      if [[ $# -gt 0 ]] && [[ "$1" =~ ^(-h|--help|help)$ ]]; then
        case "$resource" in
          user|users)       show_help_user; exit 0 ;;
          project|projects) show_help_project; exit 0 ;;
          issue|issues)     show_help_issue; exit 0 ;;
          search)           show_help_search; exit 0 ;;
          create)           show_help_create; exit 0 ;;
          priority)         show_help_priority; exit 0 ;;
          status)           show_help_status; exit 0 ;;
          workflow)         show_help_workflow; exit 0 ;;
          profile|myself)   show_help_profile; exit 0 ;;
          api)              show_help_api; exit 0 ;;
          issuetype)        show_help_issuetype; exit 0 ;;
        esac
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
      elif [[ "$resource" =~ ^(project|projects)$ ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        # Subcomandos para 'project'
        case "$1" in
          components)
            PROJECT_SUBCOMMAND="components"
            shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
              identifier="$1"; shift
            else
              identifier=""
            fi
            ;;
          statuses)
            PROJECT_SUBCOMMAND="statuses"
            shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
              identifier="$1"; shift
            else
              identifier=""
            fi
            ;;
          *)
            # Project key normal
            identifier="$1"; shift ;;
        esac
      elif [[ "$resource" =~ ^(issue|issues)$ ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        # Subcomandos para 'issue'
        case "$1" in
          comment)
            ISSUE_SUBCOMMAND="comment"
            shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
              identifier="$1"; shift
            else
              identifier=""
            fi
            ;;
          *)
            # Issue key normal
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
  if [[ $# -gt 0 ]] && [[ "$1" =~ ^(-h|--help|help)$ ]]; then
    case "$resource" in
      user|users)       show_help_user; exit 0 ;;
      project|projects) show_help_project; exit 0 ;;
      issue|issues)     show_help_issue; exit 0 ;;
      search)           show_help_search; exit 0 ;;
      create)           show_help_create; exit 0 ;;
      priority)         show_help_priority; exit 0 ;;
      status)           show_help_status; exit 0 ;;
      workflow)         show_help_workflow; exit 0 ;;
      profile|myself)   show_help_profile; exit 0 ;;
      api)              show_help_api; exit 0 ;;
      issuetype)        show_help_issuetype; exit 0 ;;
    esac
  fi
  
  # Also check if --help flag was set globally and we have a resource
  if [[ "$SHOW_HELP_FLAG" == "true" ]]; then
    case "$resource" in
      user|users)       show_help_user; exit 0 ;;
      project|projects) show_help_project; exit 0 ;;
      issue|issues)     show_help_issue; exit 0 ;;
      search)           show_help_search; exit 0 ;;
      create)           show_help_create; exit 0 ;;
      priority)         show_help_priority; exit 0 ;;
      status)           show_help_status; exit 0 ;;
      workflow)         show_help_workflow; exit 0 ;;
      profile|myself)   show_help_profile; exit 0 ;;
      api)              show_help_api; exit 0 ;;
      issuetype)        show_help_issuetype; exit 0 ;;
      *)                show_help; exit 0 ;;
    esac
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
  elif [[ "$resource" =~ ^(project|projects)$ ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
    case "$1" in
      components)
        PROJECT_SUBCOMMAND="components"
        shift
        if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
          identifier="$1"; shift
        fi
        ;;
      statuses)
        PROJECT_SUBCOMMAND="statuses"
        shift
        if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
          identifier="$1"; shift
        fi
        ;;
      *)
        identifier="$1"; shift ;;
    esac
  elif [[ "$resource" =~ ^(issue|issues)$ ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
    # Subcomandos para 'issue'
    case "$1" in
      comment)
        ISSUE_SUBCOMMAND="comment"
        shift
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
    --paginate)
      # Flag sin valor, ya procesado en el primer pase
      shift
      ;;
    --data|--token|--host|--output|--csv-export|--transitions|--to|--transition|--assign|--unassign|--project|--summary|--description|--type|--assignee|--reporter|--priority|--epic|--link-issue|--template|--workflow|--from-date|--to-date|--lookback|--limit|--jira-host|--jira-token|--jira-email|--jira-api-token|--jira-api-version|--jira-auth|--jira-project|--comment-scan-max|-m|--message|--method|--field|--raw-field|--header|--input|--export|--import|--format|-f|-F|-H|--move|--components|--yes)
      # Ya procesados en el primer pase, saltarlos. Solo shift 2 si la opción lleva valor (--format, --output, etc.)
      if [[ "$1" =~ ^--(format|output|data|token|host|csv-export|to|transition|project|summary|description|type|assignee|reporter|priority|epic|link-issue|template|workflow|from-date|to-date|lookback|limit|jira-host|jira-token|jira-email|jira-api-token|jira-api-version|jira-auth|jira-project|comment-scan-max|message|method|field|raw-field|header|input|move|components)$ ]] && [[ $# -ge 2 && ! "$2" =~ ^- ]]; then
        shift 2
      else
        shift
      fi
      ;;
    -h|--help|--shell)
      # Ya procesados en el primer pase
      shift
      ;;
    /*)
      if [[ "$USING_SIMPLIFIED_SYNTAX" == "true" ]]; then
        echo "Error: No puedes especificar endpoint directo con sintaxis simplificada" >&2
        exit 1
      fi
      ENDPOINT="$1"
      shift
      ;;
    project|issue|search|create|priority|status|workflow|user|profile|myself|api|issuetype|field|resolution|component|version)
      # Recursos válidos, ya procesados en la sección de sintaxis simplificada
      shift
      ;;
    *)
      echo "Argumento desconocido: $1" >&2
      exit 1
      ;;
  esac
done

# If help was requested without a resource context, show help now (before validations)
if [[ "$SHOW_HELP_FLAG" == "true" ]] && [[ -z "$resource" ]]; then
  show_help
  exit 0
fi

# Validaciones específicas para argumentos de transición
if [[ "$TRANSITION_TARGET_SET" == "true" ]]; then
  if [[ -z "$TRANSITION_TARGET" || "$TRANSITION_TARGET" == -* ]]; then
    echo "Error: --to requiere un ID de transición válido" >&2
    exit 1
  fi
fi

# Validación modo move
if [[ "$ISSUE_MOVE_MODE" == "true" ]]; then
  if [[ ! "$resource" =~ ^(issue|issues)$ ]] || [[ -z "$identifier" ]]; then
    echo "Error: --move requiere un issue con clave (ej: jira issue ABC-123 --move PROJ2)" >&2
    exit 1
  fi
  if [[ -z "$ISSUE_MOVE_TARGET_PROJECT" ]]; then
    echo "Error: --move requiere el proyecto destino (ej: jira issue ABC-123 --move PROJ2)" >&2
    exit 1
  fi
fi

# Validaciones
if [[ -z "$JIRA_HOST" ]]; then
  error "Debes especificar la URL de Jira con --host o la variable de entorno JIRA_HOST" >&2
  exit 1
fi

# Asegurar que JIRA_HOST tenga esquema (https:// por defecto). Sin esto, curl puede usar http://,
# recibir un redirect a https:// y al seguir la redirección reenviar como GET sin body, y Jira
# responde "project is required" porque no recibe el JSON del POST.
if [[ ! "$JIRA_HOST" =~ ^https?:// ]]; then
  JIRA_HOST="https://${JIRA_HOST}"
fi

if [[ -z "$ENDPOINT" ]]; then
  echo "Debes especificar el endpoint o recurso" >&2
  echo "Ejemplos:" >&2
  echo "  jira project CORE" >&2
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

# Auto-detect JIRA_AUTH if not explicitly set
if [[ -z "$JIRA_AUTH" ]]; then
  if [[ -n "$JIRA_EMAIL" && -n "$JIRA_API_TOKEN" ]]; then
    JIRA_AUTH="basic"
  elif [[ -n "$JIRA_USER" && -n "$JIRA_PASSWORD" ]]; then
    JIRA_AUTH="basic"
  elif [[ -n "$JIRA_TOKEN" ]]; then
    # Auto-detect if JIRA_TOKEN is base64 encoded Basic Auth (contains user:pass)
    # Check if it decodes AND both parts before/after ':' are printable ASCII
    if decoded=$(echo "$JIRA_TOKEN" | base64 -d 2>/dev/null) && [[ "$decoded" == *:* ]]; then
      # Extract parts before and after the colon
      user_part="${decoded%%:*}"
      pass_part="${decoded#*:}"
      # Check if both parts are printable (no binary/control chars)
      if [[ "$user_part" =~ ^[[:print:]]+$ ]] && [[ "$pass_part" =~ ^[[:print:]]+$ ]]; then
        JIRA_AUTH="basic"
      else
        JIRA_AUTH="bearer"
      fi
    else
      JIRA_AUTH="bearer"
    fi
  fi
fi

# Build AUTH_HEADER based on JIRA_AUTH type
case "$JIRA_AUTH" in
  basic)
    # Priority: 1) JIRA_TOKEN (pre-encoded base64), 2) JIRA_USER+JIRA_PASSWORD, 3) JIRA_EMAIL+JIRA_API_TOKEN
    if [[ -n "$JIRA_TOKEN" ]]; then
      # JIRA_TOKEN is already base64 encoded Basic Auth token
      AUTH_HEADER="Authorization: Basic $JIRA_TOKEN"
    elif [[ -n "$JIRA_USER" && -n "$JIRA_PASSWORD" ]]; then
      # Encode JIRA_USER:JIRA_PASSWORD to base64
      BASIC_TOKEN=$(printf "%s:%s" "$JIRA_USER" "$JIRA_PASSWORD" | base64 | tr -d '\n')
      AUTH_HEADER="Authorization: Basic $BASIC_TOKEN"
    elif [[ -n "$JIRA_EMAIL" && -n "$JIRA_API_TOKEN" ]]; then
      # Encode JIRA_EMAIL:JIRA_API_TOKEN to base64
      BASIC_TOKEN=$(printf "%s:%s" "$JIRA_EMAIL" "$JIRA_API_TOKEN" | base64 | tr -d '\n')
      AUTH_HEADER="Authorization: Basic $BASIC_TOKEN"
    fi
    ;;
  bearer)
    if [[ -n "$JIRA_TOKEN" ]]; then
      AUTH_HEADER="Authorization: Bearer $JIRA_TOKEN"
    fi
    ;;
esac

# Ejecutar move y salir (evita el flujo normal GET/POST del issue)
if [[ "$ISSUE_MOVE_MODE" == "true" ]] && [[ "$resource" =~ ^(issue|issues)$ ]] && [[ -n "$identifier" ]] && [[ -n "$ISSUE_MOVE_TARGET_PROJECT" ]]; then
  do_issue_move
  exit $?
fi

# Resolver --transition SPEC (por nombre de transición, nombre de estado o ID)
if [[ -n "$TRANSITION_SPEC" ]]; then
  if [[ ! "$resource" =~ ^(issue|issues)$ ]] || [[ -z "$identifier" ]]; then
    echo "Error: --transition requiere 'jira issue <KEY>'" >&2
    exit 1
  fi

  _transitions_url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/issue/$identifier/transitions"
  _transitions_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$_transitions_url")

  # Intento 1: match exacto por id, nombre de transición o nombre de estado destino (case-insensitive)
  _transition_id=$(printf '%s' "$_transitions_resp" | jq -r --arg s "$TRANSITION_SPEC" '
    (.transitions // [])
    | (map(select((.id == $s)
                  or ((.name // "" | ascii_downcase) == ($s | ascii_downcase))
                  or ((.to.name // "" | ascii_downcase) == ($s | ascii_downcase)))) | .[0].id) // empty')

  # Intento 2: match parcial por nombre (si no hubo exacto)
  if [[ -z "$_transition_id" ]]; then
    _transition_id=$(printf '%s' "$_transitions_resp" | jq -r --arg s "$TRANSITION_SPEC" '
      (.transitions // [])
      | (map(select((.name // "" | ascii_downcase) | contains($s | ascii_downcase)
                    or ((.to.name // "" | ascii_downcase) | contains($s | ascii_downcase)))) | .[0].id) // empty')
  fi

  if [[ -z "$_transition_id" ]]; then
    echo "Error: No se encontró la transición '$TRANSITION_SPEC' para el issue $identifier" >&2
    echo "Transiciones disponibles:" >&2
    printf '%s' "$_transitions_resp" | jq -r '(.transitions // []) | map("- " + .id + " | " + .name + " -> " + (.to.name // "")) | .[]' >&2
    exit 1
  fi

  TRANSITION_TARGET="$_transition_id"
  TRANSITION_TARGET_SET=true
  SHOW_TRANSITIONS=true
  ENDPOINT="/issue/$identifier/transitions"
  METHOD="POST"
  if [[ -z "$DATA" ]]; then
    DATA="{\"transition\":{\"id\":\"$TRANSITION_TARGET\"}}"
  fi
fi

# Si se solicita una asignación con --assign, preparar PUT automático
if [[ -n "$ASSIGN_TARGET" ]]; then
  if [[ ! "$resource" =~ ^(issue|issues)$ ]] || [[ -z "$identifier" ]]; then
    echo "Error: --assign requiere 'jira issue <KEY>'" >&2
    exit 1
  fi
  
  # Obtener el accountId del usuario actual si se usa "me"
  if [[ "$ASSIGN_TARGET" == "me" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      # En modo dry-run, usar un placeholder
      if [[ "$JIRA_API_VERSION" == "3" ]]; then
        ASSIGN_TARGET="USER_ACCOUNT_ID_PLACEHOLDER"
      else
        ASSIGN_TARGET="USER_NAME_PLACEHOLDER"
      fi
    else
      _myself_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$JIRA_HOST/rest/api/$JIRA_API_VERSION/myself")
      if [[ "$JIRA_API_VERSION" == "3" ]]; then
        _my_account_id=$(printf '%s' "$_myself_resp" | jq -r '.accountId // empty')
        if [[ -z "$_my_account_id" ]]; then
          echo "Error: No se pudo obtener el accountId del usuario actual" >&2
          exit 1
        fi
        ASSIGN_TARGET="$_my_account_id"
      else
        _my_name=$(printf '%s' "$_myself_resp" | jq -r '.name // empty')
        if [[ -z "$_my_name" ]]; then
          echo "Error: No se pudo obtener el name del usuario actual" >&2
          exit 1
        fi
        ASSIGN_TARGET="$_my_name"
      fi
    fi
  elif [[ "$ASSIGN_TARGET" == "none" ]]; then
    # Para Jira Cloud API v3, usamos null para desasignar
    if [[ "$JIRA_API_VERSION" == "3" ]]; then
      ASSIGN_TARGET="null"
    else
      # Para Jira Server API v2, usamos nombre vacío
      ASSIGN_TARGET=""
    fi
  else
    # Para email o username, buscar el accountId
    if [[ "$ASSIGN_TARGET" == *@* ]]; then
      # Es un email, buscar por query
      _user_search_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$JIRA_HOST/rest/api/$JIRA_API_VERSION/user/search?query=$ASSIGN_TARGET")
    else
      # Es un username, buscar por username
      if [[ "$JIRA_API_VERSION" == "3" ]]; then
        _user_search_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$JIRA_HOST/rest/api/$JIRA_API_VERSION/user/search?query=$ASSIGN_TARGET")
      else
        _user_search_resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$JIRA_HOST/rest/api/$JIRA_API_VERSION/user?username=$ASSIGN_TARGET")
      fi
    fi
    
    _found_account_id=$(printf '%s' "$_user_search_resp" | jq -r 'if type == "array" and length > 0 then .[0] | if has("accountId") then .accountId else .name end // empty else empty end')
    if [[ -z "$_found_account_id" ]]; then
      echo "Error: No se encontró el usuario '$ASSIGN_TARGET'" >&2
      exit 1
    fi
    ASSIGN_TARGET="$_found_account_id"
  fi
  
  # Preparar el payload para asignación
  if [[ "$JIRA_API_VERSION" == "3" ]]; then
    if [[ "$ASSIGN_TARGET" == "null" ]]; then
      DATA="{\"fields\":{\"assignee\":null}}"
    else
      DATA="{\"fields\":{\"assignee\":{\"accountId\":\"$ASSIGN_TARGET\"}}}"
    fi
  else
    if [[ -z "$ASSIGN_TARGET" ]]; then
      DATA="{\"fields\":{\"assignee\":{\"name\":\"\"}}}"
    else
      DATA="{\"fields\":{\"assignee\":{\"name\":\"$ASSIGN_TARGET\"}}}"
    fi
  fi
  
  ENDPOINT="/issue/$identifier"
  METHOD="PUT"
fi

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
          local jql="$1"
          local resp
          if [[ "$JIRA_API_VERSION" == "3" ]]; then
            local _payload
            _payload=$(jq -n --arg jql "$jql" '{jql: $jql}')
            resp=$(execute_curl --request POST -H "Content-Type: application/json" -H "Accept: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} --data "$_payload" "$JIRA_HOST/rest/api/3/search/approximate-count")
            printf '%s' "$resp" | jq -r '.count // .total // .issueCount // 0'
          else
            local enc; enc=$(jq -rn --arg s "$jql" '$s|@uri')
            local url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$enc&maxResults=0&fields=none"
            resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url")
            printf '%s' "$resp" | jq -r '.total // 0'
          fi
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
            local url
            if [[ "$JIRA_API_VERSION" == "3" ]]; then
              url="$JIRA_HOST/rest/api/3/search/jql?jql=$enc&maxResults=$USER_ACTIVITY_LIMIT&fields=key,summary,project,status,labels,components,${epic_field_name}"
            else
              url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$enc&maxResults=$USER_ACTIVITY_LIMIT&fields=key,summary,project,status,labels,components,${epic_field_name}"
            fi
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
          local jql="$1"
          local resp
          if [[ "$JIRA_API_VERSION" == "3" ]]; then
            local _payload
            _payload=$(jq -n --arg jql "$jql" '{jql: $jql}')
            resp=$(execute_curl --request POST -H "Content-Type: application/json" -H "Accept: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} --data "$_payload" "$JIRA_HOST/rest/api/3/search/approximate-count")
            printf '%s' "$resp" | jq -r '.count // .total // .issueCount // 0'
          else
            local enc; enc=$(jq -rn --arg s "$jql" '$s|@uri')
            local url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$enc&maxResults=0&fields=none"
            resp=$(execute_curl --request GET -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url")
            printf '%s' "$resp" | jq -r '.total // 0'
          fi
        }
        _tot_created=$(get_total_by_jql "$JQL_CREATED")
        _tot_assigned=$(get_total_by_jql "$JQL_ASSIGNED")
        _tot_resolved=$(get_total_by_jql "$JQL_RESOLVED")
        _tot_in_progress=$(get_total_by_jql "$JQL_INPROGRESS")
        _tot_not_started=$(get_total_by_jql "$JQL_TODO")

        # Comentados: escanear issues recientes
        SCAN_MAX="${COMMENT_SCAN_MAX:-${JIRA_ACTIVITY_COMMENT_SCAN_MAX:-100}}"; PAGE=50
        _jql_recent="$date_filter_updated ORDER BY updated DESC"; _processed=0; _commented=0; _startAt=0
        _next_page_token=""
        while [[ $_processed -lt $SCAN_MAX ]]; do
          _enc=$(jq -rn --arg s "$_jql_recent" '$s|@uri')
          if [[ "$JIRA_API_VERSION" == "3" ]]; then
            if [[ -z "$_next_page_token" ]]; then
              _url="$JIRA_HOST/rest/api/3/search/jql?jql=$_enc&maxResults=$PAGE&fields=key"
            else
              _tok=$(jq -rn --arg s "$_next_page_token" '$s|@uri')
              _url="$JIRA_HOST/rest/api/3/search/jql?jql=$_enc&maxResults=$PAGE&fields=key&nextPageToken=$_tok"
            fi
          else
            _url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/search?jql=$_enc&startAt=$_startAt&maxResults=$PAGE&fields=key"
          fi
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
          if [[ "$JIRA_API_VERSION" == "3" ]]; then
            _is_last=$(printf '%s' "$_resp" | jq -r '.isLast // false')
            _next_page_token=$(printf '%s' "$_resp" | jq -r '.nextPageToken // empty')
            [[ "$_is_last" == "true" ]] && break
            [[ -z "$_next_page_token" ]] && break
          else
            _startAt=$(( _startAt + PAGE ))
          fi
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

prepare_api_payload() {
  # Si hay --input, usarlo directamente
  if [[ -n "$API_INPUT" ]]; then
    if [[ "$API_INPUT" == "-" ]]; then
      # Leer desde stdin
      if [[ -t 0 ]]; then
        echo "Error: No hay datos en stdin. Usa un pipe o redirección." >&2
        exit 1
      fi
      cat
    elif [[ -f "$API_INPUT" ]]; then
      cat "$API_INPUT"
    else
      # Es JSON inline
      printf '%s' "$API_INPUT"
    fi
    return
  fi
  
  # Construir payload desde --field y --raw-field
  local payload_file
  payload_file=$(mktemp)
  printf '{}' > "$payload_file"
  
  # Procesar --raw-field (valores como string)
  for field in "${API_RAW_FIELDS[@]}"; do
    if [[ "$field" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      jq --arg key "$key" --arg value "$value" '. + {($key): $value}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
    fi
  done
  
  # Procesar --field (con inferencia de tipo)
  for field in "${API_FIELDS[@]}"; do
    if [[ "$field" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      
      # Inferencia de tipo como glab
      if [[ "$value" == "true" ]]; then
        jq --arg key "$key" '. + {($key): true}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
      elif [[ "$value" == "false" ]]; then
        jq --arg key "$key" '. + {($key): false}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
      elif [[ "$value" == "null" ]]; then
        jq --arg key "$key" '. + {($key): null}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
      elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
        jq --arg key "$key" --argjson value "$value" '. + {($key): $value}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
      elif [[ "$value" =~ ^@ ]]; then
        # Leer desde archivo
        local file_value="${value#@}"
        if [[ "$file_value" == "-" ]]; then
          # Leer desde stdin
          if [[ -t 0 ]]; then
            echo "Error: No hay datos en stdin para @$key" >&2
            exit 1
          fi
          local content
          content=$(cat)
          jq --arg key "$key" --arg value "$content" '. + {($key): $value}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
        elif [[ -f "$file_value" ]]; then
          local content
          content=$(cat "$file_value")
          jq --arg key "$key" --arg value "$content" '. + {($key): $value}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
        else
          echo "Error: Archivo no encontrado: $file_value" >&2
          exit 1
        fi
      else
        # String por defecto
        jq --arg key "$key" --arg value "$value" '. + {($key): $value}' "$payload_file" > "${payload_file}.tmp" && mv "${payload_file}.tmp" "$payload_file"
      fi
    fi
  done
  
  cat "$payload_file"
  rm -f "$payload_file"
}

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

  # Proyecto: --project tiene prioridad absoluta; si se pasó, no usar JIRA_PROJECT ni el base.
  # Asignar .fields.project como objeto completo.
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
    | (if $p_flag != "" then .fields.project = { key: ($p_flag | ascii_upcase) }
       elif ((.fields.project.key // "") == "") and ($p_env != "") then .fields.project = { key: ($p_env | ascii_upcase) }
       else . end)
    | (if $s   != "" then .fields.summary     = $s else . end)
    | (if $d   != "" then .fields.description = $d else . end)
    | (if $t   != "" then .fields.issuetype = { name: $t } else . end)
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

# Jira Cloud (API v3): /rest/api/3/search fue removido; usar /rest/api/3/search/jql
# Ref: https://confluence.atlassian.com/jirakb/run-jql-search-query-using-jira-cloud-rest-api-1289424308.html
if [[ "$JIRA_API_VERSION" == "3" ]] && [[ "$REQUEST_URL" == *"/rest/api/3/search?"* ]] && [[ "$REQUEST_URL" != *"/rest/api/3/search/jql?"* ]]; then
  REQUEST_URL="${REQUEST_URL//\/rest\/api\/3\/search?/\/rest\/api\/3\/search\/jql?}"
fi

# Import de componentes: leer stdin, parsear y POST por cada componente
if [[ "$PROJECT_SUBCOMMAND" == "components" && "$COMPONENTS_IMPORT" == "true" && -n "$identifier" ]]; then
  if [[ -z "$JIRA_HOST" ]]; then
    error "JIRA_HOST no está definido (--host o variable de entorno)"
    exit 1
  fi
  if [[ -z "$AUTH_HEADER" ]]; then
    error "Autenticación no configurada (JIRA_TOKEN o JIRA_EMAIL+JIRA_API_TOKEN)"
    exit 1
  fi
  _import_input=$(cat)
  _components_json=""
  case "$COMPONENTS_FORMAT" in
    json)
      _components_json=$(printf '%s' "$_import_input" | jq -c 'if type == "array" then . else [.] end')
      ;;
    yaml)
      require_cmd yq
      _components_json=$(printf '%s' "$_import_input" | yq -c 'if type == "array" then . else [.] end')
      ;;
    csv|tsv)
      if command -v yq >/dev/null 2>&1; then
        _parser="csv"
        [[ "$COMPONENTS_FORMAT" == "tsv" ]] && _parser="tsv"
        _components_json=$(printf '%s' "$_import_input" | yq -p "$_parser" -o json -I0 -c 'if type == "array" then . else [.] end | map(select(.name != null and .name != ""))')
      else
        _sep=$'\t'
        [[ "$COMPONENTS_FORMAT" == "csv" ]] && _sep=','
        _components_json=$(printf '%s' "$_import_input" | awk -v FS="$_sep" '
          NR==1 { for(i=1;i<=NF;i++) h[$i]=i; next }
          {
            name=""; desc=""; assigneeType=""; leadAccountId=""
            if (h["name"]) name=$h["name"]
            if (h["description"]) desc=$h["description"]
            if (h["assigneeType"]) assigneeType=$h["assigneeType"]
            if (h["leadAccountId"]) leadAccountId=$h["leadAccountId"]
            gsub(/"/, "\\\"", name); gsub(/"/, "\\\"", desc)
            printf "{\"name\":\"%s\",\"description\":\"%s\",\"assigneeType\":\"%s\",\"leadAccountId\":\"%s\"}\n", name, desc, assigneeType, leadAccountId
          }
        ' | jq -s -c 'map(select(.name != ""))')
      fi
      ;;
    *)
      _components_json="[]"
      ;;
  esac
  if [[ -z "$_components_json" ]] || ! printf '%s' "$_components_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "Error: No se pudo parsear el contenido como lista de componentes (formato: $COMPONENTS_FORMAT)" >&2
    exit 1
  fi
  _count=$(printf '%s' "$_components_json" | jq 'length')
  _created=0
  _failed=0
  _post_url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}/component"
  for _idx in $(seq 0 $((_count - 1))); do
    _comp=$(printf '%s' "$_components_json" | jq -c --argjson i "$_idx" '.[$i]')
    _name=$(printf '%s' "$_comp" | jq -r '.name // ""')
    [[ -z "$_name" ]] && continue
    _payload=$(printf '%s' "$_comp" | jq -c --arg proj "$identifier" '
      { name: .name, project: $proj }
      + (if .description != null and .description != "" then { description: .description } else {} end)
      + (if .assigneeType != null and .assigneeType != "" then { assigneeType: .assigneeType } else {} end)
      + (if .leadAccountId != null and .leadAccountId != "" then { leadAccountId: .leadAccountId } else {} end)
    ')
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] POST $_post_url" "$_payload" >&2
      _created=$((_created + 1))
    else
      _resp=$(execute_curl --request POST -H "Content-Type: application/json" -H "$AUTH_HEADER" --data "$_payload" "$_post_url" 2>/dev/null)
      if printf '%s' "$_resp" | jq -e '.id // .name' >/dev/null 2>&1; then
        echo "Creado: $_name" >&2
        _created=$((_created + 1))
      else
        echo "Error creando '$_name': $_resp" >&2
        _failed=$((_failed + 1))
      fi
    fi
  done
  echo "Importados: $_created, errores: $_failed" >&2
  exit 0
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
  
  # Agregar headers adicionales del modo API
  for header in "${API_HEADERS[@]}"; do
    curl_args+=(-H "$header")
  done
  
  if [[ "$API_MODE" == "true" ]]; then
    # Manejo especial para modo API
    # Determinar método (si se especificó --method o si hay campos/data)
    if [[ -n "$API_METHOD" ]]; then
      curl_args[1]="$API_METHOD"
    elif [[ ${#API_FIELDS[@]} -gt 0 || ${#API_RAW_FIELDS[@]} -gt 0 || -n "$API_INPUT" ]]; then
      # Si hay campos o input, cambiar a POST (como glab)
      curl_args[1]="POST"
    fi
    
    # Construir payload para API
    if [[ ${#API_FIELDS[@]} -gt 0 || ${#API_RAW_FIELDS[@]} -gt 0 || -n "$API_INPUT" ]]; then
      api_payload_file=$(mktemp)
      prepare_api_payload > "$api_payload_file"
      curl_args+=(--data "@$api_payload_file")
      trap "rm -f '$api_payload_file'" EXIT
    fi
  elif [[ "$CREATE_MODE" == "true" || ( "$METHOD" == "POST" && "$ENDPOINT" == "/issue" ) ]]; then
    FINAL_DATA_FILE=$(prepare_create_payload)
    if [[ -f "$FINAL_DATA_FILE" ]]; then
      _proj_key=$(jq -r '.fields.project.key // empty' "$FINAL_DATA_FILE" 2>/dev/null)
      if [[ -z "$_proj_key" ]]; then
        error "Al crear un issue, el proyecto es obligatorio. Usa --project KEY o define JIRA_PROJECT." >&2
        error "Ejemplo: jira create --project opsai --summary \"Título\" --description \"Descripción\"" >&2
        rm -f "$FINAL_DATA_FILE"
        exit 1
      fi
    fi
    curl_args+=(--data @"$FINAL_DATA_FILE")
  elif [[ "$ISSUE_SUBCOMMAND" == "comment" && "$METHOD" == "POST" ]]; then
    # Construir payload para comentario
    if [[ -z "$COMMENT_MESSAGE" ]]; then
      echo "Error: Se requiere un mensaje para el comentario. Usa -m o --message" >&2
      echo "Ejemplo: jira issue comment ABC-123 -m 'Mensaje del comentario'" >&2
      echo "         echo 'mensaje' | jira issue comment ABC-123 -m -" >&2
      exit 1
    fi
    
    # Leer desde stdin si el mensaje es "-"
    if [[ "$COMMENT_MESSAGE" == "-" ]]; then
      if [[ -t 0 ]]; then
        echo "Error: No hay datos en stdin. Usa un pipe o redirección." >&2
        echo "Ejemplo: echo 'mensaje' | jira issue comment ABC-123 -m -" >&2
        exit 1
      fi
      COMMENT_MESSAGE=$(cat)
      # Eliminar nueva línea final si existe
      COMMENT_MESSAGE="${COMMENT_MESSAGE%$'\n'}"
    fi
    
    if [[ -z "$COMMENT_MESSAGE" ]]; then
      echo "Error: El mensaje del comentario está vacío" >&2
      exit 1
    fi
    
    _comment_payload=$(mktemp)
    if [[ "$JIRA_API_VERSION" == "3" ]]; then
      # API v3 (Jira Cloud) usa formato ADF (Atlassian Document Format)
      jq -n \
        --arg msg "$COMMENT_MESSAGE" \
        '{
          "body": {
            "type": "doc",
            "version": 1,
            "content": [
              {
                "type": "paragraph",
                "content": [
                  {
                    "type": "text",
                    "text": $msg
                  }
                ]
              }
            ]
          }
        }' > "$_comment_payload"
    else
      # API v2 (Jira Server/DC) usa texto plano
      jq -n \
        --arg msg "$COMMENT_MESSAGE" \
        '{
          "body": $msg
        }' > "$_comment_payload"
    fi
    curl_args+=(--data @"$_comment_payload")
    # Limpiar archivo temporal después de la ejecución
    trap "rm -f '$_comment_payload'" EXIT
  else
    if [[ -n "$DATA" ]]; then
      # For updates on API v3, convert plain string description to ADF automatically
      if [[ "$METHOD" == "PUT" && "$ENDPOINT" =~ ^/issue/ ]]; then
        _put_in_tmp=""
        _put_src_file=""
        if [[ -f "$DATA" ]]; then
          _put_src_file="$DATA"
        else
          _put_in_tmp=$(mktemp)
          printf '%s' "$DATA" > "$_put_in_tmp"
          _put_src_file="$_put_in_tmp"
        fi
        _put_final=$(mktemp)
        jq --arg api_ver "$JIRA_API_VERSION" '
          if ($api_ver == "3") and (.fields | has("description")) and ((.fields.description | type) == "string") then
            .fields.description = {
              "type": "doc",
              "version": 1,
              "content": [
                {"type": "paragraph", "content": [ {"type": "text", "text": .fields.description } ]}
              ]
            }
          else . end' "$_put_src_file" > "$_put_final"
        curl_args+=(--data @"$_put_final")
      else
        if [[ -f "$DATA" ]]; then
          curl_args+=(--data @"$DATA")
        else
          curl_args+=(--data "$DATA")
        fi
      fi
    fi
  fi
  
  # Manejar paginación para búsquedas
  # API v3 (Cloud): /search sustituido por /search/jql; paginación con nextPageToken (no startAt)
  if [[ "$PAGINATE" == "true" ]] && [[ "$ENDPOINT" =~ ^/search\? ]]; then
    jql_param=""
    other_params=""
    if [[ "$JIRA_API_VERSION" == "3" ]]; then
      base_endpoint="/search/jql"
    else
      base_endpoint="/search"
    fi

    # Separar jql de otros parámetros
    if [[ "$ENDPOINT" =~ jql=([^&]+) ]]; then
      jql_param="${BASH_REMATCH[1]}"
      if [[ "$ENDPOINT" =~ \&(.*)$ ]]; then
        temp_params="${BASH_REMATCH[1]}"
        other_params=$(printf '%s' "$temp_params" | sed 's/[&?]startAt=[^&]*//g' | sed 's/[&?]maxResults=[^&]*//g' | sed 's/[&?]nextPageToken=[^&]*//g' | sed 's/^&//')
        [[ -n "$other_params" ]] && other_params="&${other_params}"
      fi
    fi

    if [[ -z "$jql_param" ]]; then
      error "No se pudo extraer JQL del endpoint para paginación"
      exit 1
    fi

    start_at=0
    max_results=100
    all_issues=()
    first_response=""
    total_results=0
    next_page_token=""

    while true; do
      if [[ "$JIRA_API_VERSION" == "3" ]]; then
        if [[ -z "$next_page_token" ]]; then
          paginated_endpoint="${base_endpoint}?jql=${jql_param}&maxResults=${max_results}${other_params}"
        else
          _tok=$(jq -rn --arg s "$next_page_token" '$s|@uri')
          paginated_endpoint="${base_endpoint}?jql=${jql_param}&maxResults=${max_results}&nextPageToken=${_tok}${other_params}"
        fi
      else
        paginated_endpoint="${base_endpoint}?jql=${jql_param}&startAt=${start_at}&maxResults=${max_results}${other_params}"
      fi
      paginated_url="$JIRA_HOST/rest/api/${JIRA_API_VERSION}${paginated_endpoint}"

      page_response=$(execute_curl "${curl_args[@]}" "$paginated_url")

      if ! printf '%s' "$page_response" | jq -e '.' >/dev/null 2>&1; then
        error "Error en la respuesta de la API"
        printf '%s' "$page_response" >&2
        exit 1
      fi

      if [[ -z "$first_response" ]]; then
        first_response="$page_response"
        total_results=$(printf '%s' "$page_response" | jq -r '.total // 0')
      fi

      page_issues=$(printf '%s' "$page_response" | jq -c '.issues[]? // empty')

      if [[ -z "$page_issues" ]]; then
        break
      fi

      while IFS= read -r issue; do
        [[ -n "$issue" ]] && all_issues+=("$issue")
      done <<< "$page_issues"

      current_count=$(printf '%s' "$page_response" | jq -r '.issues | length')

      if [[ "$JIRA_API_VERSION" == "3" ]]; then
        _is_last=$(printf '%s' "$page_response" | jq -r '.isLast // false')
        next_page_token=$(printf '%s' "$page_response" | jq -r '.nextPageToken // empty')
        [[ "$_is_last" == "true" ]] && break
        [[ -z "$next_page_token" ]] && break
      else
        current_start_at=$(printf '%s' "$page_response" | jq -r '.startAt // 0')
        if [[ "$current_count" -lt "$max_results" ]] || [[ $((current_start_at + current_count)) -ge "$total_results" ]]; then
          break
        fi
        start_at=$((start_at + max_results))
      fi
    done

    if [[ ${#all_issues[@]} -gt 0 ]]; then
      issues_temp=$(mktemp)
      printf '%s\n' "${all_issues[@]}" | jq -s '.' > "$issues_temp"
      first_temp=$(mktemp)
      printf '%s' "$first_response" > "$first_temp"
      RESPONSE=$(jq --slurpfile issues "$issues_temp" '.issues = $issues[0] | .startAt = 0 | .maxResults = ($issues[0] | length) | del(.nextPageToken) | del(.isLast)' "$first_temp")
      rm -f "$issues_temp" "$first_temp"
    else
      RESPONSE="$first_response"
    fi
  else
    curl_args+=("$REQUEST_URL")
    RESPONSE=$( execute_curl "${curl_args[@]}" )
  fi
fi

# Tras crear un issue con éxito: mostrar resumen (summary, type, desc, estado) y enlace web (browse), no el JSON de la API
CREATE_SHOW_SUMMARY=false
if [[ "$CREATE_MODE" == "true" ]] && printf '%s' "$RESPONSE" | jq -e '.key and (has("errors") | not)' >/dev/null 2>&1; then
  _key=$(printf '%s' "$RESPONSE" | jq -r '.key')
  _get_url="${JIRA_HOST%/}/rest/api/${JIRA_API_VERSION}/issue/${_key}"
  _issue_json=$(execute_curl --request GET -H "Accept: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$_get_url" 2>/dev/null)
  _browse="${JIRA_HOST%/}/browse/${_key}"
  if printf '%s' "$_issue_json" | jq -e '.fields' >/dev/null 2>&1; then
    _summary=$(printf '%s' "$_issue_json" | jq -r '.fields.summary // "—"')
    _type=$(printf '%s' "$_issue_json" | jq -r '.fields.issuetype.name // "—"')
    _status=$(printf '%s' "$_issue_json" | jq -r '.fields.status.name // "—"')
    _desc_raw=$(printf '%s' "$_issue_json" | jq -r '.fields.description // ""')
    if [[ "$_desc_raw" == "" || "$_desc_raw" == "null" ]]; then
      _desc="—"
    elif printf '%s' "$_desc_raw" | jq -e 'type == "object"' >/dev/null 2>&1; then
      _desc=$(printf '%s' "$_desc_raw" | jq -r '[.. | .text? // empty] | join(" ") | if length > 0 then . else "(ver en web)" end' 2>/dev/null || echo "(ver en web)")
    else
      _desc="$_desc_raw"
    fi
  else
    _summary="${CREATE_SUMMARY:—-}"
    _type="${CREATE_TYPE:—-}"
    _status="—"
    _desc="${CREATE_DESCRIPTION:—-}"
  fi
  [[ ${#_desc} -gt 200 ]] && _desc="${_desc:0:200}..."
  jq -n \
    --arg key "$_key" \
    --arg summary "$_summary" \
    --arg issuetype "$_type" \
    --arg description "$_desc" \
    --arg status "$_status" \
    --arg browse "$_browse" \
    '{key:$key,summary:$summary,issuetype:$issuetype,description:$description,status:$status,browse:$browse}'
  CREATE_SHOW_SUMMARY=true
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

# Filtrar respuesta para --workflow [issuetype]
if [[ -n "$PROJECT_WORKFLOW_ISSUETYPE" ]]; then
  if [[ "$PROJECT_WORKFLOW_ISSUETYPE" == "__ALL__" ]]; then
    # Mostrar todos los workflows con sus transiciones
    RESPONSE=$(echo "$RESPONSE" | jq '[
      .[] | 
      {
        issueType: .name,
        issueTypeId: .id,
        statuses: [
          .statuses[] | 
          {
            name: .name,
            id: .id,
            statusCategory: .statusCategory.name,
            transitions: [
              (.untranslatedName // .name) as $currentStatus |
              $currentStatus
            ]
          }
        ]
      }
    ]')
  else
    # Filtrar por tipo de issue específico
    RESPONSE=$(echo "$RESPONSE" | jq --arg issuetype "$PROJECT_WORKFLOW_ISSUETYPE" '
      [
        .[] | 
        select((.name | ascii_downcase) == ($issuetype | ascii_downcase)) |
        {
          issueType: .name,
          issueTypeId: .id,
          workflow: {
            statuses: [
              .statuses[] | 
              {
                name: .name,
                id: .id,
                statusCategory: .statusCategory.name
              }
            ]
          }
        }
      ] | 
      if length > 0 then .[0] else {error: "Issue type not found", availableTypes: [inputs[].name]} end
    ')
    
    # Verificar si el tipo de issue existe
    if echo "$RESPONSE" | jq -e 'has("error")' > /dev/null 2>&1; then
      echo "Error: Tipo de issue '$PROJECT_WORKFLOW_ISSUETYPE' no encontrado en el proyecto" >&2
      echo "$RESPONSE" | jq -r '.error' >&2
      exit 1
    fi
  fi
  IS_SINGLE_OBJECT=false
fi

# Export de componentes: normalizar a name, description, assigneeType, leadAccountId y salir en COMPONENTS_FORMAT
if [[ "$COMPONENTS_EXPORT" == "true" && "$ENDPOINT" =~ /project/[^/]+/components$ ]]; then
  _norm=$(printf '%s' "$RESPONSE" | jq -c '
    if type == "array" then . else [.] end
    | map({
        name: (.name // ""),
        description: (.description // ""),
        assigneeType: (.assigneeType // ""),
        leadAccountId: ((.lead.accountId // .leadAccountId // "") | tostring)
      })
  ')
  case "$COMPONENTS_FORMAT" in
    json)
      echo "$_norm" | jq .
      exit 0
      ;;
    csv)
      echo "$_norm" | jq -r 'if length > 0 then (["name","description","assigneeType","leadAccountId"], (.[] | [.name, .description, .assigneeType, .leadAccountId])) | @csv else "name,description,assigneeType,leadAccountId" end'
      exit 0
      ;;
    tsv)
      echo "$_norm" | jq -r 'if length > 0 then (["name","description","assigneeType","leadAccountId"], (.[] | [.name, .description, .assigneeType, .leadAccountId])) | @tsv else "name\tdescription\tassigneeType\tleadAccountId" end'
      exit 0
      ;;
    yaml)
      require_cmd yq
      echo "$_norm" | jq . | yq -P
      exit 0
      ;;
    *)
      echo "$_norm" | jq .
      exit 0
      ;;
  esac
fi

# Formato de salida
if [[ "$CREATE_SHOW_SUMMARY" == "true" ]]; then
  exit 0
fi
case "$OUTPUT" in
  json)
    # Formato especial para --workflow
    if [[ -n "$PROJECT_WORKFLOW_ISSUETYPE" ]]; then
      echo "$RESPONSE" | jq
    else
      echo "$RESPONSE" | jq
    fi
    ;;
  csv)
    # Formato específico para --workflow
    if [[ -n "$PROJECT_WORKFLOW_ISSUETYPE" && "$PROJECT_WORKFLOW_ISSUETYPE" != "__ALL__" ]]; then
      echo "Status ID,Status Name,Status Category"
      echo "$RESPONSE" | jq -r '.workflow.statuses[] | [.id, .name, .statusCategory] | @csv'
      exit 0
    fi
    
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
    # Formato específico para --workflow
    if [[ -n "$PROJECT_WORKFLOW_ISSUETYPE" && "$PROJECT_WORKFLOW_ISSUETYPE" != "__ALL__" ]]; then
      echo "Workflow para tipo de issue: $(echo "$RESPONSE" | jq -r '.issueType')"
      echo ""
      {
        echo -e "ID\tStatus\tCategory";
        echo "$RESPONSE" | jq -r '.workflow.statuses[] | [.id, .name, .statusCategory] | @tsv' ;
      } | column -t -s $'\t'
      exit 0
    fi
    
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
    # Formato específico para --workflow
    if [[ -n "$PROJECT_WORKFLOW_ISSUETYPE" && "$PROJECT_WORKFLOW_ISSUETYPE" != "__ALL__" ]]; then
      echo "# Workflow para tipo de issue: $(echo "$RESPONSE" | jq -r '.issueType')"
      echo ""
      echo "| ID | Status | Category |"
      echo "|---|---|---|"
      echo "$RESPONSE" | jq -r '.workflow.statuses[] | "|" + (.id|tostring) + "|" + .name + "|" + .statusCategory + "|"'
      exit 0
    fi
    
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
