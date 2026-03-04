#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Hardware Register Guard
# =============================================================================
# Protects against accidental writes to critical hardware registers:
# watchdog, reset, flash write/erase, power management, boot config.
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

# Only check C/C++ embedded files
if ! echo "$FILE_PATH" | grep -qiE '\.(c|h|cpp|hpp|cc|s|asm)$'; then
  exit 0
fi

# --- Load protected register patterns ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS_FILE="$HOOK_DIR/protected_registers.txt"

if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

# Build patterns and reasons
MATCH_RESULT=$(python3 -c "
import re, sys

content = sys.argv[1]
patterns_file = sys.argv[2]
matches = []

with open(patterns_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue

        parts = [p.strip() for p in line.split('|')]
        pattern = parts[0]
        reason = parts[1] if len(parts) > 1 else 'Protected register'

        for content_line in content.split('\n'):
            if re.search(re.escape(pattern).replace(r'\.\*', '.*').replace(r'\s\*', r'\s*'), content_line):
                matches.append(f'{reason}: {content_line.strip()[:60]}')
                break

if matches:
    print('; '.join(matches[:3]))
else:
    print('')
" "$CONTENT" "$PATTERNS_FILE" 2>/dev/null)

if [ -n "$MATCH_RESULT" ]; then
  SAFE_MATCH=$(echo "$MATCH_RESULT" | cut -c1-300 | sed 's/"/\\"/g')
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'HW REGISTER GUARD: ${SAFE_MATCH}. Writing to protected hardware registers requires explicit confirmation.'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
