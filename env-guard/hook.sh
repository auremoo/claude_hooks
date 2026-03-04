#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Environment Guard
# =============================================================================
# Prevents environment cross-contamination by detecting production URLs
# in dev configs, localhost in production files, etc.
# =============================================================================

INPUT=$(cat)

TOOL_INFO=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    tool_name = d.get('tool_name', '')
    inp = d.get('tool_input', {})
    file_path = inp.get('file_path', '') or inp.get('path', '')
    content = inp.get('new_string', '') or inp.get('content', '')
    print(file_path)
    print(tool_name)
    print(content)
except:
    print('')
    print('')
    print('')
" "$INPUT" 2>/dev/null)

FILE_PATH=$(echo "$TOOL_INFO" | head -1)
TOOL_NAME=$(echo "$TOOL_INFO" | sed -n '2p')
CONTENT=$(echo "$TOOL_INFO" | tail -n +3)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# For Read tool, scan the file content; for Edit/Write, scan new content
if [ "$TOOL_NAME" = "Read" ] && [ -f "$FILE_PATH" ]; then
  CONTENT=$(cat "$FILE_PATH" 2>/dev/null)
fi

if [ -z "$CONTENT" ]; then
  exit 0
fi

# --- Load env rules ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_FILE="$HOOK_DIR/env_rules.txt"

if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

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
        parts = [p.strip() for p in line.split('|')]
        if len(parts) != 3:
            continue

        file_pattern, content_pattern, message = parts

        if re.search(file_pattern, file_path, re.IGNORECASE):
            for content_line in content.split('\n'):
                if re.search(content_pattern, content_line, re.IGNORECASE):
                    violations.append(f'{message}: {content_line.strip()[:60]}')
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
        'permissionDecisionReason': 'ENV GUARD: ${SAFE_VIOLATION}'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
