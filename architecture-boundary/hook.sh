#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Architecture Boundary
# =============================================================================
# Enforces architectural layer boundaries by checking imports in modified files.
# Prevents violations like domain importing infrastructure, etc.
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

# --- Load boundary rules ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_FILE="$HOOK_DIR/boundary_rules.txt"

if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

# --- Check rules ---
VIOLATION=$(python3 -c "
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
        if ' -> ' not in line:
            continue

        source_pattern, forbidden_pattern = line.split(' -> ', 1)
        source_pattern = source_pattern.strip()
        forbidden_pattern = forbidden_pattern.strip()

        # Check if the file matches the source layer
        if re.search(source_pattern, file_path, re.IGNORECASE):
            # Check if the new content contains forbidden imports
            for content_line in content.split('\n'):
                if re.search(forbidden_pattern, content_line, re.IGNORECASE):
                    violations.append(f'{source_pattern} -> {content_line.strip()[:80]}')
                    break

    if violations:
        print('; '.join(violations[:3]))
    else:
        print('')
" "$FILE_PATH" "$CONTENT" "$RULES_FILE" 2>/dev/null)

if [ -n "$VIOLATION" ]; then
  SAFE_VIOLATION=$(echo "$VIOLATION" | cut -c1-250 | sed 's/"/\\"/g')
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'ARCHITECTURE VIOLATION: ${SAFE_VIOLATION}. This import crosses an architectural boundary.'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
