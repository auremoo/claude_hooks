#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Safety Standard Check
# =============================================================================
# Checks code for compliance with industrial safety standards:
# IEC 61508, DO-178C, ISO 26262, IEC 62443, MISRA C.
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

# Only check C/C++/Rust/Ada files (safety-critical languages)
if ! echo "$FILE_PATH" | grep -qiE '\.(c|h|cpp|hpp|cc|hh|rs|ada|adb|ads)$'; then
  exit 0
fi

# --- Load safety rules ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_FILE="$HOOK_DIR/safety_rules.txt"

if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

VIOLATIONS=$(python3 -c "
import re, sys

file_path = sys.argv[1]
content = sys.argv[2]
rules_file = sys.argv[3]

violations = []

with open(rules_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [p.strip() for p in line.split('|')]
        if len(parts) != 4:
            continue

        standard, rule_id, pattern, message = parts

        for i, content_line in enumerate(content.split('\n')):
            if re.search(pattern, content_line):
                violations.append(f'[{standard} {rule_id}] {message}')
                break

if violations:
    print('; '.join(violations[:4]))
else:
    print('')
" "$FILE_PATH" "$CONTENT" "$RULES_FILE" 2>/dev/null)

if [ -n "$VIOLATIONS" ]; then
  SAFE_VIOLATIONS=$(echo "$VIOLATIONS" | cut -c1-350 | sed 's/"/\\"/g')
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'SAFETY COMPLIANCE: ${SAFE_VIOLATIONS}'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
