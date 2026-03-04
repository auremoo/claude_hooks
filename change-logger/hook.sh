#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Change Logger
# =============================================================================
# Logs all file modifications (Edit, Write, Bash) to .claude/changelog.log.
# Provides audit trail of every change Claude makes to your project.
# =============================================================================

INPUT=$(cat)

# Parse tool info
TOOL_INFO=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    tool_name = d.get('tool_name', 'unknown')
    inp = d.get('tool_input', {})
    file_path = inp.get('file_path', '') or inp.get('path', '')
    command = inp.get('command', '')
    print(tool_name)
    print(file_path)
    print(command[:200] if command else '')
except:
    print('unknown')
    print('')
    print('')
" "$INPUT" 2>/dev/null)

TOOL_NAME=$(echo "$TOOL_INFO" | sed -n '1p')
FILE_PATH=$(echo "$TOOL_INFO" | sed -n '2p')
COMMAND=$(echo "$TOOL_INFO" | sed -n '3p')

# --- Determine log entry ---
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOG_DIR="$PROJECT_DIR/.claude"
LOG_FILE="$LOG_DIR/changelog.log"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

case "$TOOL_NAME" in
  Edit|Write)
    if [ -n "$FILE_PATH" ]; then
      echo "[$TIMESTAMP] $TOOL_NAME: $FILE_PATH" >> "$LOG_FILE"
    fi
    ;;
  Bash)
    # Only log commands that modify files (git, mv, cp, mkdir, etc.)
    if echo "$COMMAND" | grep -qE '(git\s+commit|git\s+push|git\s+merge|mv\s|cp\s|mkdir\s|touch\s|npm\s+install|pip\s+install|yarn\s+add)'; then
      # Escape for safe logging
      SAFE_CMD=$(echo "$COMMAND" | tr '\n' ' ' | cut -c1-200)
      echo "[$TIMESTAMP] Bash: $SAFE_CMD" >> "$LOG_FILE"
    fi
    ;;
esac

# --- Keep log file manageable (max 1000 lines) ---
if [ -f "$LOG_FILE" ]; then
  LINE_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
  if [ "$LINE_COUNT" -gt 1000 ]; then
    tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
fi

# PostToolUse hooks should always exit 0
exit 0
