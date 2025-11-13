#!/bin/bash

# Test script for 'jira issue components' command

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$DIR/.."
SRC_DIR="$PROJECT_ROOT/src"

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
test_command() {
    local description="$1"
    local command="$2"
    local expected_pattern="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    local output=$(eval "$command" 2>&1)
    
    if echo "$output" | grep -q "$expected_pattern"; then
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
echo "Testing 'jira project components' Command"
echo "========================================"
echo ""

# Test error message when no project is provided
test_command \
    "Error when no project provided" \
    "bash $SRC_DIR/jira.sh project components" \
    "requiere una clave de proyecto"

# Test that the endpoint is constructed correctly (using --dry-run)
test_command \
    "Correct endpoint construction with --dry-run" \
    "JIRA_HOST='https://test.atlassian.net' JIRA_TOKEN='test' bash $SRC_DIR/jira.sh project components TEST --dry-run" \
    "project/TEST/components"

# Test help message
test_command \
    "Help message includes components command" \
    "bash $SRC_DIR/jira.sh project -h" \
    "components <project>"

# Test that the command shows up in main help
test_command \
    "Main help includes project components" \
    "bash $SRC_DIR/jira.sh --help" \
    "project components"

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

# Exit with appropriate code
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
