#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

$DIR/jira GET "/search?jql=assignee=currentUser()%20AND%20statusCategory!=Done&fields=key,summary,status"