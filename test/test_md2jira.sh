#!/usr/bin/env bash

# ============================================================================
# Test Script for md2jira
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Source the testing framework
source "/Users/carlosherrera/src/carlos/caherrera/shellunittest/src/unittest.sh"

# Initialize the framework
initialize_test_framework "$@"

print_test_header "md2jira Conversion Tests"

# ============================================================================
# Test: Basic Markdown to Wiki Conversion
# ============================================================================

print_section "Wiki Markup Conversion Tests"

# Test heading conversion
output=$(echo "# Heading 1" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "h1. Heading 1" "$output" "Should convert # to h1."

output=$(echo "## Heading 2" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "h2. Heading 2" "$output" "Should convert ## to h2."

output=$(echo "### Heading 3" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "h3. Heading 3" "$output" "Should convert ### to h3."

# Test bold conversion
output=$(echo "**bold text**" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "*bold text*" "$output" "Should convert **bold** to *bold*"

# Test inline code conversion
output=$(echo "\`code\`" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "{{code}}" "$output" "Should convert \`code\` to {{code}}"

# Test list conversion
output=$(echo "* Item 1" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "* Item 1" "$output" "Should convert * to *"

output=$(echo "- Item 1" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "* Item 1" "$output" "Should convert - to *"

# Test checkbox conversion
output=$(echo "* [x] Done" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "* (/) Done" "$output" "Should convert [x] to (/)"

output=$(echo "* [ ] Todo" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "* (x) Todo" "$output" "Should convert [ ] to (x)"

# Test link conversion
output=$(echo "[text](url)" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "[text|url]" "$output" "Should convert [text](url) to [text|url]"

# ============================================================================
# Test: Code Block Conversion
# ============================================================================

print_section "Code Block Conversion Tests"

# Create temp file with code block
TEST_FILE=$(mktemp)
cat > "$TEST_FILE" << 'EOF'
```bash
echo "hello"
```
EOF

output=$("${PROJECT_ROOT}/bin/md2jira" --wiki "$TEST_FILE" 2>/dev/null)
assert_contains "$output" "{code:bash}" "Should contain code block with language"
assert_contains "$output" 'echo "hello"' "Should contain code content"
rm "$TEST_FILE"

# ============================================================================
# Test: ADF Format Output
# ============================================================================

print_section "ADF Format Tests"

# Test that ADF produces valid JSON
output=$(echo "# Test" | "${PROJECT_ROOT}/bin/md2jira" --adf 2>/dev/null)
echo "$output" | jq . > /dev/null 2>&1
assert_success "ADF output should be valid JSON"

# Test ADF structure
assert_contains "$output" '"type":"doc"' "ADF should have doc type"
assert_contains "$output" '"version":1' "ADF should have version 1"

# Test heading in ADF
output=$(echo "# Heading" | "${PROJECT_ROOT}/bin/md2jira" --adf 2>/dev/null)
assert_contains "$output" '"type":"heading"' "Should contain heading type"
assert_contains "$output" '"level":1' "Should have level 1"
assert_contains "$output" "Heading" "Should contain heading text"

# Test checkbox in ADF
output=$(echo "* [x] Done" | "${PROJECT_ROOT}/bin/md2jira" --adf 2>/dev/null)
assert_contains "$output" '"type":"taskList"' "Should contain taskList type"
assert_contains "$output" '"state":"DONE"' "Should have DONE state"

output=$(echo "* [ ] Todo" | "${PROJECT_ROOT}/bin/md2jira" --adf 2>/dev/null)
assert_contains "$output" '"state":"TODO"' "Should have TODO state"

# ============================================================================
# Test: Auto-detection
# ============================================================================

print_section "Format Auto-detection Tests"

# Test Cloud detection (atlassian.net)
export JIRA_HOST="https://test.atlassian.net"
output=$(echo "# Test" | "${PROJECT_ROOT}/bin/md2jira" 2>&1)
assert_contains "$output" "adf" "Should auto-detect ADF for atlassian.net"

# Test Server detection (other URLs)
export JIRA_HOST="https://jira.company.com"
output=$(echo "# Test" | "${PROJECT_ROOT}/bin/md2jira" 2>&1)
assert_contains "$output" "wiki" "Should auto-detect Wiki for non-Cloud"

unset JIRA_HOST

# ============================================================================
# Test: Help Output
# ============================================================================

print_section "Help and Usage Tests"

output=$("${PROJECT_ROOT}/bin/md2jira" -h 2>&1)
assert_contains "$output" "md2jira" "Help should contain script name"
assert_contains "$output" "--adf" "Help should mention --adf flag"
assert_contains "$output" "--wiki" "Help should mention --wiki flag"
assert_contains "$output" "EXAMPLES" "Help should contain examples"

# ============================================================================
# Test: Error Handling
# ============================================================================

print_section "Error Handling Tests"

# Test non-existent file
"${PROJECT_ROOT}/bin/md2jira" "/nonexistent/file.md" 2>&1 | grep -q "File not found"
assert_success "Should show error for non-existent file"

# Test no input
"${PROJECT_ROOT}/bin/md2jira" < /dev/null 2>&1 | grep -q "No input"
assert_success "Should show error when no input provided"

# ============================================================================
# Test: Multiple Input Methods
# ============================================================================

print_section "Input Method Tests"

# Test file input
TEST_FILE=$(mktemp)
echo "# File Test" > "$TEST_FILE"
output=$("${PROJECT_ROOT}/bin/md2jira" --wiki "$TEST_FILE" 2>/dev/null)
assert_equals "h1. File Test" "$output" "Should read from file"
rm "$TEST_FILE"

# Test pipe input
output=$(echo "# Pipe Test" | "${PROJECT_ROOT}/bin/md2jira" --wiki 2>/dev/null)
assert_equals "h1. Pipe Test" "$output" "Should read from pipe"

# Test stdin redirect
TEST_FILE=$(mktemp)
echo "# Stdin Test" > "$TEST_FILE"
output=$("${PROJECT_ROOT}/bin/md2jira" --wiki < "$TEST_FILE" 2>/dev/null)
assert_equals "h1. Stdin Test" "$output" "Should read from stdin redirect"
rm "$TEST_FILE"

print_summary
