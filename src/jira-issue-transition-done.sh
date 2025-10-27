
#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

source $DIR/../lib/helpers.sh

function next_transition() {
    local issue="$1"
    local transition="$2"
    x=$($DIR/jira.sh issue "$issue" --transitions 2>/dev/null)
    if [[ -z "$x" ]]; then        
        return 1
    fi
    tx=$(echo "$x" | jq --arg id "$transition" '.transitions[]|select(.id==$id)')
    [ -n "$tx" ] && info "transition to $transition" && $DIR/jira.sh issue "$issue" --transitions --to "$transition";
}

next_transition "$1" 21 && next_transition "$1" 31  && next_transition "$1" 41 && next_transition "$1" 51  &&  next_transition "$1" 71 && next_transition "$1" 81 && next_transition "$1" 61

$DIR/jira-issue.sh "$1"