#!/usr/bin/env bash

# ============================================================================
# Run All Tests
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITTEST="/Users/carlosherrera/src/carlos/caherrera/shellunittest/bin/unittest"

echo "═══════════════════════════════════════════════════"
echo "  Running All Tests for jira-cli.sh"
echo "═══════════════════════════════════════════════════"
echo

# Run unittest with the test directory
if [ -x "$UNITTEST" ]; then
    "$UNITTEST" "$SCRIPT_DIR" "$@"
    exit_code=$?
else
    echo "ERROR: unittest not found at $UNITTEST"
    exit 1
fi

echo
echo "═══════════════════════════════════════════════════"
if [ $exit_code -eq 0 ]; then
    echo "  ✓ All tests passed!"
else
    echo "  ✗ Some tests failed"
fi
echo "═══════════════════════════════════════════════════"

exit $exit_code
