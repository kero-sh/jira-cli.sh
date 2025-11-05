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
    --description-file)
      description_file=$2
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

# Description input (supports multiline)
desc_tmp=""
if [ -z "$description" ] && [ -z "$description_file" ]; then
  info "Enter issue description (finish with Ctrl-D):"
  desc_tmp=$(mktemp)
  # Read until EOF (Ctrl-D)
  cat > "$desc_tmp"
  # If user just pressed Ctrl-D without content, treat as empty
  if [ ! -s "$desc_tmp" ]; then
    rm -f "$desc_tmp"; desc_tmp=""
  fi
fi

# Validate that both summary and description are provided (supporting file/multiline)
has_desc=false
if [ -n "$description" ] || [ -n "$description_file" ] || [ -n "$desc_tmp" ]; then
  has_desc=true
fi
if [ -z "$summary" ] || [ "$has_desc" != true ]; then
  error "Both summary and description are required to create a JIRA issue. Aborting."
  exit 1
fi

[ -n "$issue_type" ]  && update_payload $payload ".fields.issuetype.name" "$issue_type"
[ -n "$project" ]     && update_payload $payload ".fields.project.key" "$project"
[ -n "$summary" ]     && update_payload $payload ".fields.summary" "$summary"
# Set description with rawfile when coming from file or multiline input
if [ -n "$description_file" ]; then
  jq --rawfile desc "$description_file" '.fields.description = $desc' "$payload" > "$payload.tmp" && mv "$payload.tmp" "$payload"
elif [ -n "$desc_tmp" ]; then
  jq --rawfile desc "$desc_tmp" '.fields.description = $desc' "$payload" > "$payload.tmp" && mv "$payload.tmp" "$payload"
elif [ -n "$description" ]; then
  update_payload $payload ".fields.description" "$description"
fi
[ -n "$assignee" ]    && update_payload $payload ".fields.assignee.name" "$assignee"
[ -n "$reporter" ]    && update_payload $payload ".fields.reporter.name" "$reporter"
[ -n "$epic" ]        && update_payload $payload ".fields.customfield_10100" "$epic"
[ -n "$priority" ]    && update_payload $payload ".fields.priority.name" "$priority"
[ -n "$link_issue" ]  && update_payload $payload ".fields.issuelinks[0].outwardIssue.key" "$link_issue"


# Use explicit REST endpoints and call the main CLI in bin/
if [ -z "$issue_key" ]; then
  "$DIR/../bin/jira" POST /issue --data "$payload"
else
  "$DIR/../bin/jira" PUT /issue/"$issue_key" --data "$payload"
fi
