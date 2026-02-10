#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Sensitive Data Scanner
# =============================================================================
# Scans files BEFORE they are sent to Anthropic's servers via Read/Grep/Edit/Write.
# If sensitive patterns are found, prompts the user for confirmation.
#
# Install: run install.sh in your project, or copy manually:
#   1. Copy this file + sensitive_patterns.txt to .claude/hooks/
#   2. Add hook config to .claude/settings.json (see install.sh)
#
# Requires: bash, python3 (uses python3 instead of jq for JSON parsing)
# =============================================================================

INPUT=$(cat)

# --- Extract file_path from hook JSON input ---
# Hook receives: {"tool_name":"Read","tool_input":{"file_path":"/some/path"}}
# Handles both "file_path" (Read/Edit/Write) and "path" (Grep/Glob)
FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    print(inp.get('file_path', '') or inp.get('path', '') or '')
except:
    print('')
" "$INPUT" 2>/dev/null)

# No file path or file doesn't exist -> allow
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Load patterns ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS_FILE="$HOOK_DIR/sensitive_patterns.txt"

if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

# Build regex from non-empty, non-comment lines
REGEX=$(grep -v '^#' "$PATTERNS_FILE" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')

if [ -z "$REGEX" ]; then
  exit 0
fi

# --- Scan target file ---
MATCHES=$(grep -inE "$REGEX" "$FILE_PATH" 2>/dev/null | head -5)

if [ -n "$MATCHES" ]; then
  MATCH_COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
  PREVIEW=$(echo "$MATCHES" | head -3 | tr '\n' '; ' | cut -c1-200 | sed 's/"/\\"/g')

  # Return "ask" decision so user sees the warning and can approve/deny
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'SENSITIVE DATA in ${FILE_PATH} (${MATCH_COUNT} match). Preview: ${PREVIEW}'
    }
}
print(json.dumps(result))
"
  exit 0
fi

# No match -> allow silently
exit 0
