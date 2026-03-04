#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Auto Backup
# =============================================================================
# Creates a backup copy of files BEFORE Claude modifies them via Edit/Write.
# Backups are stored in .claude/backups/ with timestamps.
# =============================================================================

INPUT=$(cat)

FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    print(inp.get('file_path', '') or '')
except:
    print('')
" "$INPUT" 2>/dev/null)

# No file path or file doesn't exist yet (new file) -> skip
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Create backup ---
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
BACKUP_DIR="$PROJECT_DIR/.claude/backups"
mkdir -p "$BACKUP_DIR"

# Generate backup filename: original-name.TIMESTAMP.bak
BASENAME=$(basename "$FILE_PATH")
RELATIVE_PATH=$(python3 -c "
import os, sys
try:
    rel = os.path.relpath(sys.argv[1], sys.argv[2])
    # Replace path separators with underscores for flat backup storage
    print(rel.replace('/', '_').replace('\\\\', '_'))
except:
    print(os.path.basename(sys.argv[1]))
" "$FILE_PATH" "$PROJECT_DIR" 2>/dev/null)

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${RELATIVE_PATH}.${TIMESTAMP}.bak"

cp "$FILE_PATH" "$BACKUP_FILE" 2>/dev/null

# --- Cleanup old backups (keep last 20 per file) ---
PATTERN="$BACKUP_DIR/${RELATIVE_PATH}.*.bak"
BACKUP_COUNT=$(ls -1 $PATTERN 2>/dev/null | wc -l | tr -d ' ')
if [ "$BACKUP_COUNT" -gt 20 ]; then
  ls -1t $PATTERN 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null
fi

# Allow the operation to proceed (backup is silent)
exit 0
