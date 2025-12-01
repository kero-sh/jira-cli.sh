#!/bin/bash

# Get the directory where the script is located
readonly LIB_DIR="$( cd "$( dirname $(realpath "${BASH_SOURCE[0]}" ))" && pwd )";
readonly VENDOR_DIR="$LIB_DIR/../vendor";
readonly SYSTEM_LOCAL_BIN_DIR="/usr/local/bin/jira-cli";

# Load helpers.sh with fallback locations
HELPER_FOUND=false

# 1. Check if HELPER_SCRIPT environment variable is set
if [[ -n "$HELPER_SCRIPT" ]]; then
  if [[ -f "$HELPER_SCRIPT" ]]; then
    # shellcheck source=/dev/null
    source "$HELPER_SCRIPT"
    HELPER_FOUND=true  
  fi
fi

# 2. Fallback locations (in order)
if [[ "$HELPER_FOUND" == "false" ]]; then
  for helper_path in \
    "$LIB_DIR/helpers.sh" \
    "$VENDOR_DIR/helpers.sh" \
    "$SYSTEM_LOCAL_BIN_DIR/helpers.sh"; do
    if [[ -f "$helper_path" ]]; then
      # shellcheck source=/dev/null
      source "$helper_path"
      HELPER_FOUND=true
      break
    fi
  done
fi

# 3. If still not found, define minimal fallback functions
if [[ "$HELPER_FOUND" == "false" ]]; then
  echo "[CRITICAL] helpers.sh not found" >&2
  exit 1
fi
