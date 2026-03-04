#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Context Usage Monitor
# =============================================================================
# Tracks the volume of data read by Claude during a session.
# Warns when approaching configurable thresholds.
# =============================================================================

# --- Configuration ---
WARN_LINES=10000    # Warning threshold (lines read)
ALERT_LINES=20000   # Alert threshold (lines read)

INPUT=$(cat)

FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    print(inp.get('file_path', '') or inp.get('path', '') or '')
except:
    print('')
" "$INPUT" 2>/dev/null)

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Count lines in the read file ---
FILE_LINES=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ')

# --- Track cumulative usage ---
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRACKER_FILE="$PROJECT_DIR/.claude/context-usage.txt"
mkdir -p "$PROJECT_DIR/.claude"

# Read current total
CURRENT_TOTAL=0
if [ -f "$TRACKER_FILE" ]; then
  CURRENT_TOTAL=$(cat "$TRACKER_FILE" 2>/dev/null | tr -d ' ')
fi

# Update total
NEW_TOTAL=$((CURRENT_TOTAL + FILE_LINES))
echo "$NEW_TOTAL" > "$TRACKER_FILE"

# --- Log the read ---
TIMESTAMP=$(date '+%H:%M:%S')
echo "[$TIMESTAMP] +${FILE_LINES}L $(basename "$FILE_PATH") (total: ${NEW_TOTAL}L)" >> "$PROJECT_DIR/.claude/context-usage.log"

# --- Check thresholds ---
if [ "$NEW_TOTAL" -gt "$ALERT_LINES" ]; then
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'notification': 'CONTEXT ALERT: ${NEW_TOTAL} lines read this session (threshold: ${ALERT_LINES}). Context quality may degrade. Consider starting a new session.'
    }
}
print(json.dumps(result))
"
elif [ "$NEW_TOTAL" -gt "$WARN_LINES" ]; then
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'notification': 'CONTEXT WARNING: ${NEW_TOTAL} lines read this session (threshold: ${WARN_LINES}). Be selective with file reads.'
    }
}
print(json.dumps(result))
"
fi

exit 0
