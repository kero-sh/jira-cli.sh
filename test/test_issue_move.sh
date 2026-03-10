#!/bin/bash

# Tests for 'jira issue --move' / 'jira move' (move issue to another project)
# Note: set -e disabled so all tests run even if one fails

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$DIR/.."
SRC_DIR="$PROJECT_ROOT/src"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

test_command() {
    local description="$1"
    local command="$2"
    local expected_pattern="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local output
    output=$(eval "$command" 2>&1)

    if echo "$output" | grep -qF -- "$expected_pattern"; then
        echo -e "${GREEN}✓${NC} $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        echo -e "${YELLOW}  Expected pattern: $expected_pattern${NC}"
        echo -e "${YELLOW}  Got: $output${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

echo "========================================"
echo "Testing 'jira issue --move' / 'jira move'"
echo "========================================"
echo ""

# Validation: --move without project destination
test_command \
    "Error when --move without project destination" \
    "bash $SRC_DIR/jira.sh issue ABC-123 --move 2>&1" \
    "requiere el proyecto destino"

# Validation: --move without issue key (only 'issue' and --move PROJ)
test_command \
    "Error when --move without issue key" \
    "bash $SRC_DIR/jira.sh issue --move PROJ2 2>&1" \
    "requiere un issue con clave"

# jira move without key
test_command \
    "Error when 'jira move' without issue key" \
    "bash $SRC_DIR/jira.sh move 2>&1" \
    "requiere clave de issue"

# jira move with key but no --to-project: normalized to issue ABC-123, then fails on JIRA_HOST or auth
test_command \
    "'jira move ABC-123' without --to-project runs as GET issue and needs JIRA_HOST" \
    "bash $SRC_DIR/jira.sh move ABC-123 2>&1" \
    "JIRA_HOST"

# Help: issue -h mentions --move
test_command \
    "Issue help mentions --move" \
    "bash $SRC_DIR/jira.sh issue -h" \
    "--move"

# Help: issue -h mentions --components and --yes
test_command \
    "Issue help mentions --components and --yes" \
    "bash $SRC_DIR/jira.sh issue -h" \
    "--yes"

# jira help move shows issue help
test_command \
    "'jira help move' shows issue help" \
    "bash $SRC_DIR/jira.sh help move" \
    "move"

# Main help mentions move
test_command \
    "Main help mentions move" \
    "bash $SRC_DIR/jira.sh --help" \
    "move"

# Without auth, do_issue_move fails before fetching.
test_command \
    "Move without token fails (auth required)" \
    "JIRA_HOST='https://test.atlassian.net' bash $SRC_DIR/jira.sh issue ABC-123 --move PROJ2 --dry-run 2>&1" \
    "autenticación"

echo ""
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

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed!${NC}"
exit 0
