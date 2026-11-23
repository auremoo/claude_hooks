#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Change Logger
# =============================================================================
# Logs all file modifications (Edit, Write, Bash) to .claude/changelog.log.
# Provides audit trail of every change Claude makes to your project.
# =============================================================================

# --- Configuration ---
MAX_LOG_LINES=1000    # Truncate the log when it grows beyond this...
KEEP_LOG_LINES=500    # ...keeping the most recent lines

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local ENTRY FILE_PATH LINE_COUNT LOG_FILE PROJECT_DIR RE REPLY S SAFE_CMD TIMESTAMP TOOL_NAME

  json_str tool_name; TOOL_NAME=$REPLY

  # --- Determine log entry (nothing to log -> exit early) ---
  case "$TOOL_NAME" in
    Edit|Write)
      get_file_path || return 0
      ENTRY="$TOOL_NAME: $FILE_PATH"
      ;;
    Bash)
      json_str command || return 0
      # Only log commands that modify files (git, mv, cp, mkdir, etc.)
      S='[[:space:]]'
      RE="(git$S+commit|git$S+push|git$S+merge|mv$S|cp$S|mkdir$S|touch$S|npm$S+install|pip$S+install|yarn$S+add)"
      [[ $REPLY =~ $RE ]] || return 0
      SAFE_CMD=${REPLY//[$'\n\r\t']/ }
      ENTRY="Bash: ${SAFE_CMD:0:200}"
      ;;
    *)
      return 0
      ;;
  esac

  get_project_dir
  ensure_dir "$PROJECT_DIR/.claude"
  LOG_FILE="$PROJECT_DIR/.claude/changelog.log"

  now TIMESTAMP '%Y-%m-%d %H:%M:%S'
  printf '[%s] %s\n' "$TIMESTAMP" "$ENTRY" >> "$LOG_FILE"

  # --- Keep log file manageable ---
  # Counting lines costs a process: do it on ~1 write out of 20, which is enough
  # to keep the log bounded (it may briefly exceed MAX_LOG_LINES by a few lines).
  if (( RANDOM % 20 == 0 )); then
    LINE_COUNT=$(wc -l < "$LOG_FILE")
    if (( ${LINE_COUNT:-0} > MAX_LOG_LINES )); then
      tail -n "$KEEP_LOG_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
  fi

  # PostToolUse hooks should always return 0
  return 0
}

main
