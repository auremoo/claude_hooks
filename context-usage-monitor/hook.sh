#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Context Usage Monitor
# =============================================================================
# Tracks the volume of data read by Claude during a session.
# Warns once when each configurable threshold is crossed.
# The counter restarts automatically when a new session begins.
# =============================================================================

# --- Configuration ---
WARN_LINES=10000        # Warning threshold (lines read)
ALERT_LINES=20000       # Alert threshold (lines read)
DEFAULT_READ_LINES=2000 # Lines returned by Read when no "limit" is given

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local CURRENT_TOTAL FILE_LINES FILE_PATH LIMIT NEW_TOTAL PROJECT_DIR REPLY SAVED_SESSION
  local SAVED_TOTAL SESSION_ID TIMESTAMP TRACKER_FILE

  get_file_path or_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # --- Count lines actually read ---
  FILE_LINES=$(wc -l < "$FILE_PATH" 2>/dev/null)
  FILE_LINES=$(( ${FILE_LINES:-0} ))
  LIMIT=$DEFAULT_READ_LINES
  json_num limit && (( REPLY > 0 )) && LIMIT=$REPLY
  (( FILE_LINES > LIMIT )) && FILE_LINES=$LIMIT

  # --- Track cumulative usage (tracker file: "<total> <session_id>") ---
  get_project_dir
  ensure_dir "$PROJECT_DIR/.claude"
  TRACKER_FILE="$PROJECT_DIR/.claude/context-usage.txt"

  json_str session_id; SESSION_ID=${REPLY:-unknown}
  CURRENT_TOTAL=0
  if [ -f "$TRACKER_FILE" ]; then
    read -r SAVED_TOTAL SAVED_SESSION < "$TRACKER_FILE"
    if [ "$SAVED_SESSION" = "$SESSION_ID" ] && [[ $SAVED_TOTAL =~ ^[0-9]+$ ]]; then
      CURRENT_TOTAL=$SAVED_TOTAL
    fi
  fi

  NEW_TOTAL=$((CURRENT_TOTAL + FILE_LINES))
  printf '%s %s\n' "$NEW_TOTAL" "$SESSION_ID" > "$TRACKER_FILE"

  # --- Log the read ---
  now TIMESTAMP '%H:%M:%S'
  printf '[%s] +%sL %s (total: %sL)\n' "$TIMESTAMP" "$FILE_LINES" "${FILE_PATH##*/}" "$NEW_TOTAL" >> "$PROJECT_DIR/.claude/context-usage.log"

  # --- Notify when a threshold is crossed (once per threshold, not on every read) ---
  if (( CURRENT_TOTAL <= ALERT_LINES && NEW_TOTAL > ALERT_LINES )); then
    emit_post "CONTEXT ALERT: ${NEW_TOTAL} lines read this session (threshold: ${ALERT_LINES}). Context quality may degrade. Consider starting a new session."
  elif (( CURRENT_TOTAL <= WARN_LINES && NEW_TOTAL > WARN_LINES )); then
    emit_post "CONTEXT WARNING: ${NEW_TOTAL} lines read this session (threshold: ${WARN_LINES}). Be selective with file reads."
  fi
  return 0
}

main
