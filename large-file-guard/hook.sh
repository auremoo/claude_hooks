#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Large File Guard
# =============================================================================
# Warns before reading files larger than a configurable threshold.
# Default threshold: 1 MB. Change MAX_SIZE_KB below to adjust.
# =============================================================================

# --- Configuration ---
MAX_SIZE_KB=1024  # 1 MB threshold (in KB)

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH FILE_SIZE FILE_SIZE_KB HUMAN_SIZE REPLY

  get_file_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # --- Check file size ---
  FILE_SIZE=$(wc -c < "$FILE_PATH" 2>/dev/null)
  FILE_SIZE_KB=$(( ${FILE_SIZE:-0} / 1024 ))

  if (( FILE_SIZE_KB > MAX_SIZE_KB )); then
    # Convert to human-readable
    if (( FILE_SIZE_KB > 1024 )); then
      HUMAN_SIZE="$((FILE_SIZE_KB / 1024)) MB"
    else
      HUMAN_SIZE="${FILE_SIZE_KB} KB"
    fi
    emit_pre ask "LARGE FILE: \"${FILE_PATH##*/}\" is ${HUMAN_SIZE} (threshold: $((MAX_SIZE_KB / 1024)) MB). Reading large files consumes significant context. Continue?"
  fi
  return 0
}

main
