function may_color() {
	case "$TERM" in
        *color*|*256*|xterm*|screen*|tmux*)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

function yellow() {
	printf "\033[0;33m%s\033[0m" "$@"
}

function red() {
	printf "\033[0;31m%s\033[0m" "$@"
}
function green() {
	printf "\033[0;32m%s\033[0m" "$@"
}
function blue() {
	printf "\033[0;34m%s\033[0m" "$@"
}


function echoc() {
	local color=$(echo "$1"|tr '[:upper:]' '[:lower:]')
	local title=$2
	shift 2
	local message=$@
	if $(may_color); then
		case "$color" in
		red)
			printf "%s %s" $(red "$title") "$message"
			;;
		green)
			printf "%s %s" $(green "$title") "$message"
			;;
		yellow)
			printf "%s %s" $(yellow "$title") "$message"
			;;
		blue)
			printf "%s %s" $(blue "$title") "$message"
			;;
		*)
			echo -n $message
			;;
		esac
	else
		echo -n "$title $message"
	fi
	echo
}


function info() {
	echoc "blue" "[INFO]" "$@"
}
function debug() {
	echoc "" "[DEBUG]" "$@"
}
function error() {
	echoc "red" "[ERROR]" "$@"
}
function warn() {
	echoc "yellow" "[WARN]" "$@"
}

function success() {
	echoc "green" "[SUCCESS]" "$@"
}

function warning() {
  echoc "yellow" "[WARN]" "$@"
}

function split_title() {
	local max_length="80"
	local text="$@"

	while [[ ${#text} -gt $max_length ]]; do
		# Corta el texto en la longitud máxima permitida
		echo "*** ${text:0:$max_length} ***"
		# Resto del texto
		text="${text:$max_length}"
	done
	# Muestra el resto que no supera el límite
	echo "*** $text ***"
}

function printtitle() {
	local title="$@"
	info "********************************************"
	info "*** $title ***"
	info "********************************************"
}