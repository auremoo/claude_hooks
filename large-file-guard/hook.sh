#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Large File Guard
# =============================================================================
# Warns before reading files larger than a configurable threshold.
# Default threshold: 1 MB. Change MAX_SIZE_KB below to adjust.
# =============================================================================

# --- Configuration ---
MAX_SIZE_KB=1024  # 1 MB threshold (in KB)

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

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Check file size ---
FILE_SIZE_KB=$(python3 -c "
import os, sys
try:
    size = os.path.getsize(sys.argv[1])
    print(size // 1024)
except:
    print(0)
" "$FILE_PATH" 2>/dev/null)

if [ "$FILE_SIZE_KB" -gt "$MAX_SIZE_KB" ]; then
  # Convert to human-readable
  if [ "$FILE_SIZE_KB" -gt 1024 ]; then
    HUMAN_SIZE="$((FILE_SIZE_KB / 1024)) MB"
  else
    HUMAN_SIZE="${FILE_SIZE_KB} KB"
  fi

  BASENAME=$(basename "$FILE_PATH")

  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'LARGE FILE: \"${BASENAME}\" is ${HUMAN_SIZE} (threshold: $((MAX_SIZE_KB / 1024)) MB). Reading large files consumes significant context. Continue?'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
