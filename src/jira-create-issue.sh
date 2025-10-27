#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

source $DIR/../lib/helpers.sh



while [ $# -gt 0 ]; do
  case $1 in
    --type)
      issue_type=$2
      shift 2
      ;;
    --epic)
      epic=$2
      shift 2
      ;;
    --project)
      project=$2
      shift 2
      ;;
    --summary)
      summary=$2
      shift 2
      ;;
    --description)
      description=$2
      shift 2
      ;;

    --assignee)
      assignee=$2
      shift 2
      ;;

    --reporter)
      reporter=$2
      shift 2
      ;;

    --priority)
      priority=$2
      shift 2
      ;;

    --link-issue)
      link_issue=$2
      shift 2
      ;;  

    --template)
      template=$2
      shift 2
      ;;
    *)
      [ -z "$issue_key" ] && {
        
        issue_key="$1"
        shift

        } || {
        echo "Unknown option: $1"
        exit 1
      }
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

if [ -z "$template" ]; then
  template=$(mktemp)
  cat <<EOF > $template
{
  "fields": {
    "project": { "key": "PROJ" },
    "summary": "Title",
    "description": "Description",
    "issuetype": { "name": "Task" }
  }
}
EOF
fi

payload=$(mktemp)
cat $template > $payload

# Validate required fields
if [ -z "$summary" ]; then
  echo -n "Enter issue summary: "
  read summary
fi

if [ -z "$description" ]; then
  echo "Enter issue description: "
  read description
fi

# Validate that both summary and description are provided
if [ -z "$summary" ] || [ -z "$description" ]; then
  error "Both summary and description are required to create a JIRA issue. Aborting."
  exit 1
fi

[ -n "$issue_type" ]  && update_payload $payload ".fields.issuetype.name" "$issue_type"
[ -n "$project" ]     && update_payload $payload ".fields.project.key" "$project"
[ -n "$summary" ]     && update_payload $payload ".fields.summary" "$summary"
[ -n "$description" ] && update_payload $payload ".fields.description" "$description"
[ -n "$assignee" ]    && update_payload $payload ".fields.assignee.name" "$assignee"
[ -n "$reporter" ]    && update_payload $payload ".fields.reporter.name" "$reporter"
[ -n "$epic" ]        && update_payload $payload ".fields.customfield_10100" "$epic"
[ -n "$priority" ]    && update_payload $payload ".fields.priority.name" "$priority"
[ -n "$link_issue" ]  && update_payload $payload ".fields.issuelinks[0].outwardIssue.key" "$link_issue"


[ -z "$issue_key" ] && $DIR/jira.sh POST issue --data $payload || $DIR/jira.sh PUT issue/$issue_key --data $payload
