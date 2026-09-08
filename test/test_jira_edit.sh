#!/usr/bin/env bash
# Unit tests for jira issue editing, labels, and components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_BIN="${SCRIPT_DIR}/../bin/jira"

failed=0
total=0

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  total=$((total + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc: PASS"
  else
    echo "  ✗ $desc: FAIL (expected '$expected', got '$actual')"
    failed=$((failed + 1))
  fi
}

echo "═══════════════════════════════════════════════════"
echo "  Testing Issue Editing & Labels/Components"
echo "═══════════════════════════════════════════════════"

JIRA_API_VERSION=3
export JIRA_API_VERSION

# Edit summary and priority
dry_out=$("$JIRA_BIN" edit PROJ-100 --summary "Updated Summary" --priority High --dry-run 2>/dev/null)
assert_eq "Updated summary" "Updated Summary" "$(echo "$dry_out" | jq -r '.fields.summary // empty')"
assert_eq "Updated priority" "High" "$(echo "$dry_out" | jq -r '.fields.priority.name // empty')"

# Atomic label addition & removal
dry_labels=$("$JIRA_BIN" issue edit PROJ-100 --add-label backend,v2 --remove-label legacy --dry-run 2>/dev/null)
assert_eq "Add label 1" "backend" "$(echo "$dry_labels" | jq -r '.update.labels[0].add // empty')"
assert_eq "Add label 2" "v2" "$(echo "$dry_labels" | jq -r '.update.labels[1].add // empty')"
assert_eq "Remove label" "legacy" "$(echo "$dry_labels" | jq -r '.update.labels[2].remove // empty')"

# Atomic component addition & removal
dry_comps=$("$JIRA_BIN" edit PROJ-100 --add-component API --remove-component OldCore --dry-run 2>/dev/null)
assert_eq "Add component" "API" "$(echo "$dry_comps" | jq -r '.update.components[0].add.name // empty')"
assert_eq "Remove component" "OldCore" "$(echo "$dry_comps" | jq -r '.update.components[1].remove.name // empty')"

# Custom field
dry_cf=$("$JIRA_BIN" edit PROJ-100 --field customfield_10014=EPIC-500 --dry-run 2>/dev/null)
assert_eq "Custom field assignment" "EPIC-500" "$(echo "$dry_cf" | jq -r '.fields.customfield_10014 // empty')"

# --data with nested fields
dry_data_nested=$("$JIRA_BIN" edit PROJ-100 --data '{"fields":{"summary":"Data Nested","priority":{"name":"Low"}}}' --dry-run 2>/dev/null)
assert_eq "Data nested summary" "Data Nested" "$(echo "$dry_data_nested" | jq -r '.fields.summary // empty')"
assert_eq "Data nested priority" "Low" "$(echo "$dry_data_nested" | jq -r '.fields.priority.name // empty')"

# --data with flat fields (auto-wrap in fields and normalize priority)
dry_data_flat=$("$JIRA_BIN" edit PROJ-100 --data '{"summary":"Flat Summary","priority":"Medium"}' --dry-run 2>/dev/null)
assert_eq "Data flat summary wrapped" "Flat Summary" "$(echo "$dry_data_flat" | jq -r '.fields.summary // empty')"
assert_eq "Data flat priority normalized" "Medium" "$(echo "$dry_data_flat" | jq -r '.fields.priority.name // empty')"

# --data with file
tmp_json=$(mktemp --suffix=.json)
echo '{"summary":"From File","priority":"High"}' > "$tmp_json"
dry_data_file=$("$JIRA_BIN" edit PROJ-100 --data "$tmp_json" --dry-run 2>/dev/null)
assert_eq "Data from file summary" "From File" "$(echo "$dry_data_file" | jq -r '.fields.summary // empty')"
assert_eq "Data from file priority" "High" "$(echo "$dry_data_file" | jq -r '.fields.priority.name // empty')"
rm -f "$tmp_json"

# --data with stdin
dry_data_stdin=$(echo '{"summary":"From Stdin"}' | "$JIRA_BIN" edit PROJ-100 --data - --dry-run 2>/dev/null)
assert_eq "Data from stdin summary" "From Stdin" "$(echo "$dry_data_stdin" | jq -r '.fields.summary // empty')"

# --data with CLI override
dry_data_override=$("$JIRA_BIN" edit PROJ-100 --data '{"summary":"Initial","priority":"Low"}' --summary "Overridden" --dry-run 2>/dev/null)
assert_eq "Data override summary" "Overridden" "$(echo "$dry_data_override" | jq -r '.fields.summary // empty')"
assert_eq "Data override preserves priority" "Low" "$(echo "$dry_data_override" | jq -r '.fields.priority.name // empty')"

# --data error handling
err_invalid_json=$("$JIRA_BIN" edit PROJ-100 --data '{bad json' --dry-run 2>&1 || true)
total=$((total + 1))
if echo "$err_invalid_json" | grep -qi "invalid --data"; then
  echo "  ✓ Reject invalid JSON: PASS"
else
  echo "  ✗ Reject invalid JSON: FAIL"
  failed=$((failed + 1))
fi

err_missing_file=$("$JIRA_BIN" edit PROJ-100 --data "/nonexistent/path/file.json" --dry-run 2>&1 || true)
total=$((total + 1))
if echo "$err_missing_file" | grep -qi "invalid --data"; then
  echo "  ✓ Reject nonexistent file: PASS"
else
  echo "  ✗ Reject nonexistent file: FAIL"
  failed=$((failed + 1))
fi

echo
echo "Results: $((total - failed))/$total passed"
if [ $failed -gt 0 ]; then
  exit 1
fi
exit 0
