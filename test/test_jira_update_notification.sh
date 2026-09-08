#!/usr/bin/env bash
# Test version check notification isolation (stderr only, not stdout)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

JIRA_BIN="${PROJECT_ROOT}/src/jira.sh"
TMP_CACHE=$(mktemp)
trap 'rm -f "$TMP_CACHE"' EXIT

echo "9999999999" > "$TMP_CACHE"
echo "v99.0.0" >> "$TMP_CACHE"

pass=0
fail=0

assert() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  ✓ $desc: PASS"
    pass=$((pass + 1))
  else
    echo "  ✗ $desc: FAIL"
    fail=$((fail + 1))
  fi
}

echo "Testing Update Notification Channel Isolation"
echo "=============================================="

# 1. Stdout must not contain the update warning (clean for pipes/json)
stdout_output=$(JIRA_HOST="https://jira.example.com" JIRA_VERSION_CACHE_FILE="$TMP_CACHE" CLICOLOR_FORCE=0 "$JIRA_BIN" PROJ-123 --dry-run 2>/dev/null)
assert "Stdout does not contain update notice" test -z "$(echo "$stdout_output" | grep "A new version of jira-cli is available" || true)"
assert "Stdout remains valid JSON" bash -c "echo '$stdout_output' | jq -e . >/dev/null"

# 2. Stderr must receive the update warning
stderr_output=$(JIRA_HOST="https://jira.example.com" JIRA_VERSION_CACHE_FILE="$TMP_CACHE" CLICOLOR_FORCE=0 "$JIRA_BIN" PROJ-123 --dry-run 2>&1 >/dev/null)
assert "Stderr contains update warning" bash -c "echo '$stderr_output' | grep -q 'A new version of jira-cli is available'"
assert "Stderr contains self-update hint" bash -c "echo '$stderr_output' | grep -q 'jira self-update'"

# 3. Fast-dispatch commands also trigger notification on stderr
branch_stderr=$(JIRA_VERSION_CACHE_FILE="$TMP_CACHE" CLICOLOR_FORCE=0 "$JIRA_BIN" branch PROJ-123 -N 2>&1 >/dev/null)
assert "Fast-dispatch (branch) shows warning on stderr" bash -c "echo '$branch_stderr' | grep -q 'A new version of jira-cli is available'"

# 4. Help and no-arg invocations suppress update notification
help_stderr=$(JIRA_VERSION_CACHE_FILE="$TMP_CACHE" CLICOLOR_FORCE=0 "$JIRA_BIN" --help 2>&1 >/dev/null)
assert "--help suppresses update warning" test -z "$(echo "$help_stderr" | grep "A new version of jira-cli is available" || true)"

no_arg_stderr=$(JIRA_VERSION_CACHE_FILE="$TMP_CACHE" CLICOLOR_FORCE=0 "$JIRA_BIN" 2>&1 >/dev/null)
assert "jira without args suppresses update warning" test -z "$(echo "$no_arg_stderr" | grep "A new version of jira-cli is available" || true)"

# 5. JIRA_NO_UPDATE_CHECK=1 suppresses notification
suppressed_stderr=$(JIRA_NO_UPDATE_CHECK=1 JIRA_HOST="https://jira.example.com" JIRA_VERSION_CACHE_FILE="$TMP_CACHE" "$JIRA_BIN" PROJ-123 --dry-run 2>&1 >/dev/null)
assert "JIRA_NO_UPDATE_CHECK=1 suppresses warning" test -z "$(echo "$suppressed_stderr" | grep "A new version of jira-cli is available" || true)"

echo
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
