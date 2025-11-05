#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

[ -z "$in" ] && in="$1"
[ -z "$out" ] && out="$2"
shift 2

while [ $# -gt 0 ]; do
  case $1 in
    --type)
      type=$2
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

function update_payload() {
  local payload="$1"
  local key="$2"
  local value="$3"
  if [ -n "$value" ]; then
    jq --arg value "$value" "$key = \$value" $payload > $payload.tmp && mv $payload.tmp $payload
  fi
}

payload=$(mktemp)
cat cat <<< "
"issuelinks": [
  {
    "type": {
      "name": "Relates"
    },
    "outwardIssue": {
      "key": "ABC-123"
    }
  }
]" > $payload

[ -n "$type" ]  && update_payload $payload ".issuelinks[0].type.name" "$type"
[ -n "$in" ]    && update_payload $payload ".issuelinks[0].inwardIssue.key" "$in"
[ -n "$out" ]   && update_payload $payload ".issuelinks[0].outwardIssue.key" "$out"


"$DIR/jira" POST /issueLink --data "$payload"
