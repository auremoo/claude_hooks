#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Dangerous Command Guard
# =============================================================================
# Scans Bash commands for dangerous patterns before execution.
# If a dangerous command is detected, asks user for confirmation.
# =============================================================================

INPUT=$(cat)

# Extract the command from hook JSON input
COMMAND=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    print(inp.get('command', ''))
except:
    print('')
" "$INPUT" 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- Load patterns ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS_FILE="$HOOK_DIR/dangerous_patterns.txt"

if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

# Build regex from non-empty, non-comment lines
REGEX=$(grep -v '^#' "$PATTERNS_FILE" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')

if [ -z "$REGEX" ]; then
  exit 0
fi

# --- Scan command ---
MATCH=$(echo "$COMMAND" | grep -iE "$REGEX" 2>/dev/null | head -1 | cut -c1-200 | sed 's/"/\\"/g')

if [ -n "$MATCH" ]; then
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'DANGEROUS COMMAND detected: ${MATCH}'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
