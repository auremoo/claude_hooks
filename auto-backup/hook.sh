#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Auto Backup
# =============================================================================
# Creates a backup copy of files BEFORE Claude modifies them via Edit/Write.
# Backups are stored in .claude/backups/ with timestamps.
# =============================================================================

# --- Configuration ---
MAX_BACKUPS=20   # Backups kept per file

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local BACKUPS BACKUP_DIR BACKUP_FILE D EXCESS FILE_PATH N PROJECT_DIR RELATIVE_PATH REPLY
  local TIMESTAMP

  # No file path or file doesn't exist yet (new file) -> skip
  get_file_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # --- Create backup ---
  get_project_dir
  BACKUP_DIR="$PROJECT_DIR/.claude/backups"
  ensure_dir "$BACKUP_DIR"

  # Backup name: path relative to the project, separators replaced by "_"
  (( IS_WIN )) && shopt -s nocasematch
  if [[ $FILE_PATH == "$PROJECT_DIR"/* ]]; then
    RELATIVE_PATH=${FILE_PATH:${#PROJECT_DIR}+1}
  else
    RELATIVE_PATH=$FILE_PATH
  fi
  shopt -u nocasematch
  RELATIVE_PATH=${RELATIVE_PATH//[\/:]/_}

  now TIMESTAMP '%Y%m%d_%H%M%S'
  BACKUP_FILE="$BACKUP_DIR/${RELATIVE_PATH}.${TIMESTAMP}.bak"
  # Several edits within the same second: keep every state (…_1.bak, …_2.bak)
  N=0
  while [ -e "$BACKUP_FILE" ]; do
    N=$((N + 1))
    BACKUP_FILE="$BACKUP_DIR/${RELATIVE_PATH}.${TIMESTAMP}_${N}.bak"
  done

  cp "$FILE_PATH" "$BACKUP_FILE" 2>/dev/null

  # --- Cleanup old backups (keep the last MAX_BACKUPS per file) ---
  # Timestamped names sort chronologically, so the glob lists oldest first.
  D='[0-9]'
  BACKUPS=("$BACKUP_DIR/$RELATIVE_PATH".$D$D$D$D$D$D$D${D}_$D$D$D$D$D$D*.bak)
  EXCESS=$(( ${#BACKUPS[@]} - MAX_BACKUPS ))
  if (( EXCESS > 0 )); then
    rm -f -- "${BACKUPS[@]:0:EXCESS}" 2>/dev/null
  fi

  # Allow the operation to proceed (backup is silent)
  return 0
}

main
