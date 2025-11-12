#!/bin/bash

# Test script to validate that help flags work for all commands
# Run from the project root: bash test/test_help.sh

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$DIR/.."
SRC_DIR="$PROJECT_ROOT/src"
BIN_DIR="$PROJECT_ROOT/bin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result function
test_help() {
    local description="$1"
    local command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        echo -e "${YELLOW}  Command: $command${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

echo "========================================"
echo "Testing Help Flags for JIRA CLI"
echo "========================================"
echo ""

# Test main jira command
echo "Testing main jira command:"
test_help "jira --help" "bash $SRC_DIR/jira.sh --help"
test_help "jira -h" "bash $SRC_DIR/jira.sh -h"
test_help "jira help" "bash $SRC_DIR/jira.sh help"
echo ""

# Test jira resources with help
echo "Testing jira resources with help:"
test_help "jira project --help" "bash $SRC_DIR/jira.sh project --help"
test_help "jira project -h" "bash $SRC_DIR/jira.sh project -h"
test_help "jira help project" "bash $SRC_DIR/jira.sh help project"

test_help "jira issue --help" "bash $SRC_DIR/jira.sh issue --help"
test_help "jira issue -h" "bash $SRC_DIR/jira.sh issue -h"
test_help "jira help issue" "bash $SRC_DIR/jira.sh help issue"

test_help "jira search --help" "bash $SRC_DIR/jira.sh search --help"
test_help "jira search -h" "bash $SRC_DIR/jira.sh search -h"
test_help "jira help search" "bash $SRC_DIR/jira.sh help search"

test_help "jira create --help" "bash $SRC_DIR/jira.sh create --help"
test_help "jira create -h" "bash $SRC_DIR/jira.sh create -h"
test_help "jira help create" "bash $SRC_DIR/jira.sh help create"

test_help "jira user --help" "bash $SRC_DIR/jira.sh user --help"
test_help "jira user -h" "bash $SRC_DIR/jira.sh user -h"
test_help "jira help user" "bash $SRC_DIR/jira.sh help user"

test_help "jira priority --help" "bash $SRC_DIR/jira.sh priority --help"
test_help "jira priority -h" "bash $SRC_DIR/jira.sh priority -h"
test_help "jira help priority" "bash $SRC_DIR/jira.sh help priority"

test_help "jira status --help" "bash $SRC_DIR/jira.sh status --help"
test_help "jira status -h" "bash $SRC_DIR/jira.sh status -h"
test_help "jira help status" "bash $SRC_DIR/jira.sh help status"

test_help "jira issuetype --help" "bash $SRC_DIR/jira.sh issuetype --help"
test_help "jira issuetype -h" "bash $SRC_DIR/jira.sh issuetype -h"
test_help "jira help issuetype" "bash $SRC_DIR/jira.sh help issuetype"
echo ""

# Test standalone scripts
echo "Testing standalone scripts:"
test_help "jira-issue.sh --help" "bash $SRC_DIR/jira-issue.sh --help"
test_help "jira-issue.sh -h" "bash $SRC_DIR/jira-issue.sh -h"

test_help "jira-search.sh --help" "bash $SRC_DIR/jira-search.sh --help"
test_help "jira-search.sh -h" "bash $SRC_DIR/jira-search.sh -h"

test_help "jira-create-issue.sh --help" "bash $SRC_DIR/jira-create-issue.sh --help"
test_help "jira-create-issue.sh -h" "bash $SRC_DIR/jira-create-issue.sh -h"

test_help "jira-issue-create-branch.sh --help" "bash $SRC_DIR/jira-issue-create-branch.sh --help"
test_help "jira-issue-create-branch.sh -h" "bash $SRC_DIR/jira-issue-create-branch.sh -h"

test_help "jira-issue-link.sh --help" "bash $SRC_DIR/jira-issue-link.sh --help"
test_help "jira-issue-link.sh -h" "bash $SRC_DIR/jira-issue-link.sh -h"

test_help "jira-issues-pending-for-me.sh --help" "bash $SRC_DIR/jira-issues-pending-for-me.sh --help"
test_help "jira-issues-pending-for-me.sh -h" "bash $SRC_DIR/jira-issues-pending-for-me.sh -h"

test_help "jira-issue-transition-done.sh --help" "bash $SRC_DIR/jira-issue-transition-done.sh --help"
test_help "jira-issue-transition-done.sh -h" "bash $SRC_DIR/jira-issue-transition-done.sh -h"

test_help "jira-issue-transition-redo.sh --help" "bash $SRC_DIR/jira-issue-transition-redo.sh --help"
test_help "jira-issue-transition-redo.sh -h" "bash $SRC_DIR/jira-issue-transition-redo.sh -h"

test_help "md2jira.sh --help" "bash $SRC_DIR/md2jira.sh --help"
test_help "md2jira.sh -h" "bash $SRC_DIR/md2jira.sh -h"
echo ""

# Test binaries if they exist
if [ -d "$BIN_DIR" ]; then
    echo "Testing bin/ scripts (if executable):"
    
    if [ -x "$BIN_DIR/jira" ]; then
        test_help "bin/jira --help" "$BIN_DIR/jira --help"
        test_help "bin/jira -h" "$BIN_DIR/jira -h"
    fi
    
    if [ -x "$BIN_DIR/jira-create-issue" ]; then
        test_help "bin/jira-create-issue --help" "$BIN_DIR/jira-create-issue --help"
    fi
    
    if [ -x "$BIN_DIR/jira-issue" ]; then
        test_help "bin/jira-issue --help" "$BIN_DIR/jira-issue --help"
    fi
    
    if [ -x "$BIN_DIR/jira-issue-create-branch" ]; then
        test_help "bin/jira-issue-create-branch --help" "$BIN_DIR/jira-issue-create-branch --help"
    fi
    
    echo ""
fi

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC}       $PASSED_TESTS"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed:${NC}       $FAILED_TESTS"
else
    echo -e "${GREEN}Failed:${NC}       $FAILED_TESTS"
fi
echo ""

# Exit with appropriate code
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
