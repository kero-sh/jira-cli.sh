#!/bin/bash
DIR="$( cd "$( dirname $(realpath ${BASH_SOURCE[0]} ))" && pwd )";

$DIR/jira.sh issue "$1" --transitions --to 71 > /dev/null
$DIR/jira-issue-transition-done.sh "$1"