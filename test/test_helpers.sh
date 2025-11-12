#!/usr/bin/env bash

# ============================================================================
# Test Script for helpers.sh
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Source the testing framework
source "/Users/carlosherrera/src/carlos/caherrera/shellunittest/src/unittest.sh"

# Initialize the framework
initialize_test_framework "$@"

print_test_header "helpers.sh Function Tests"

# Source helpers
source "${PROJECT_ROOT}/lib/helpers.sh"

# ============================================================================
# Test: Color Functions
# ============================================================================

print_section "Color Function Tests"

# Test color functions exist and produce output
output=$(red "test")
assert_contains "$output" "test" "red() should contain text"

output=$(green "test")
assert_contains "$output" "test" "green() should contain text"

output=$(blue "test")
assert_contains "$output" "test" "blue() should contain text"

output=$(yellow "test")
assert_contains "$output" "test" "yellow() should contain text"

# ============================================================================
# Test: Logging Functions Output to stderr
# ============================================================================

print_section "Logging Functions stderr Tests"

# Test that info goes to stderr (not stdout)
output=$(info "test message" 2>&1 >/dev/null)
assert_contains "$output" "[INFO]" "info() should output to stderr"
assert_contains "$output" "test message" "info() should contain message"

# Test that stdout is clean when logging to stderr
output=$(info "test" 2>/dev/null)
assert_equals "" "$output" "info() should not output to stdout"

# Test error function
output=$(error "error message" 2>&1 >/dev/null)
assert_contains "$output" "[ERROR]" "error() should output to stderr"
assert_contains "$output" "error message" "error() should contain message"

# Test warn function
output=$(warn "warning" 2>&1 >/dev/null)
assert_contains "$output" "[WARN]" "warn() should output to stderr"

# Test success function
output=$(success "success" 2>&1 >/dev/null)
assert_contains "$output" "[SUCCESS]" "success() should output to stderr"

# Test debug function
output=$(debug "debug" 2>&1 >/dev/null)
assert_contains "$output" "[DEBUG]" "debug() should output to stderr"

# ============================================================================
# Test: may_color Function
# ============================================================================

print_section "Color Detection Tests"

# Save original TERM
ORIGINAL_TERM="$TERM"

# Test with color-capable terminal
export TERM="xterm-256color"
may_color
assert_success "may_color should return 0 for xterm-256color"

export TERM="xterm-color"
may_color
assert_success "may_color should return 0 for xterm-color"

# Test with non-color terminal
export TERM="dumb"
may_color && result=0 || result=1
assert_exit_code 1 $result "may_color should return 1 for dumb terminal"

# Restore TERM
export TERM="$ORIGINAL_TERM"

# ============================================================================
# Test: split_title Function
# ============================================================================

print_section "split_title Function Tests"

# Test short text (should not split)
output=$(split_title "Short text" 2>&1)
assert_contains "$output" "*** Short text ***" "Should format short text"

# Test long text (should split)
long_text="This is a very long text that exceeds the maximum length of eighty characters and should be split"
output=$(split_title "$long_text" 2>&1)
# Should have multiple lines
line_count=$(echo "$output" | wc -l)
[ "$line_count" -gt 1 ]
assert_success "split_title should split long text into multiple lines"

# ============================================================================
# Test: printtitle Function
# ============================================================================

print_section "printtitle Function Tests"

output=$(printtitle "Test Title" 2>&1)
assert_contains "$output" "Test Title" "printtitle should contain title"
assert_contains "$output" "***" "printtitle should contain asterisks"
assert_contains "$output" "[INFO]" "printtitle should use info function"

# Count lines (should be 3: top border, title, bottom border)
line_count=$(echo "$output" | grep -c "^\[INFO\]")
assert_equals "3" "$line_count" "printtitle should output 3 info lines"

# ============================================================================
# Test: Message Functions Don't Interfere with stdout
# ============================================================================

print_section "stdout Isolation Tests"

# Create a function that outputs to stdout with logging
test_function() {
    info "Processing data..."
    echo "RESULT_DATA"
    success "Done"
}

# Capture only stdout
result=$(test_function 2>/dev/null)
assert_equals "RESULT_DATA" "$result" "stdout should only contain data, not log messages"

# Verify stderr contains logs
logs=$(test_function 2>&1 >/dev/null)
assert_contains "$logs" "[INFO]" "stderr should contain INFO"
assert_contains "$logs" "[SUCCESS]" "stderr should contain SUCCESS"
# Check that stdout data is not in stderr
echo "$logs" | grep -v "RESULT_DATA" > /dev/null
assert_success "stderr should not contain stdout data"

print_summary
