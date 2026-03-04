#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - PLC Safety Guard
# =============================================================================
# Detects unsafe patterns in PLC/automation code before it's written.
# Supports: IEC 61131-3 Structured Text, CODESYS, TwinCAT, Siemens SCL.
# =============================================================================

INPUT=$(cat)

TOOL_INFO=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    file_path = inp.get('file_path', '')
    content = inp.get('new_string', '') or inp.get('content', '')
    print(file_path)
    print(content)
except:
    print('')
    print('')
" "$INPUT" 2>/dev/null)

FILE_PATH=$(echo "$TOOL_INFO" | head -1)
CONTENT=$(echo "$TOOL_INFO" | tail -n +2)

if [ -z "$FILE_PATH" ] || [ -z "$CONTENT" ]; then
  exit 0
fi

# Check PLC-related files
if ! echo "$FILE_PATH" | grep -qiE '\.(st|scl|pou|exp|xml|tmc|plcproj|gsd|aml)$'; then
  exit 0
fi

# --- Load unsafe patterns ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS_FILE="$HOOK_DIR/plc_unsafe_patterns.txt"

if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

REGEX=$(grep -v '^#' "$PATTERNS_FILE" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')

if [ -z "$REGEX" ]; then
  exit 0
fi

MATCH=$(echo "$CONTENT" | grep -inE "$REGEX" 2>/dev/null | head -3 | tr '\n' '; ' | cut -c1-200 | sed 's/"/\\"/g')

if [ -n "$MATCH" ]; then
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'PLC SAFETY: Unsafe pattern detected in automation code: ${MATCH}. Verify safety interlocks before proceeding.'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
