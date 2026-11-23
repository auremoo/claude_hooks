#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Dangerous Command Guard
# =============================================================================
# Scans Bash commands for dangerous patterns before execution.
# If a dangerous command is detected, asks user for confirmation.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local COMMAND MATCH PATTERNS_FILE RC REGEX REPLY

  json_str command || return 0
  COMMAND=$REPLY
  [ -n "$COMMAND" ] || return 0

  # Regex built from non-empty, non-comment lines of the patterns file
  PATTERNS_FILE="$HOOK_DIR/dangerous_patterns.txt"
  load_patterns "$PATTERNS_FILE" || return 0

  # --- Scan command ---
  # Most commands are harmless: when bash itself can prove it, grep is not started
  surely_no_match "$COMMAND" "$REGEX" && return 0
  MATCH=$(grep -iE -m1 -e "$REGEX" <<<"$COMMAND" 2>/dev/null)
  RC=$?
  if (( RC >= 2 )); then
    grep_failed dangerous-command-guard "$PATTERNS_FILE"
  elif [ -n "$MATCH" ]; then
    emit_pre ask "DANGEROUS COMMAND detected: ${MATCH:0:200}"
  fi
  return 0
}

main
