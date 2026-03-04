#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Branch Protection
# =============================================================================
# Prevents direct commits and pushes to protected branches.
# Asks user for confirmation if a git commit/push targets a protected branch.
# =============================================================================

INPUT=$(cat)

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

# Only check git commit and git push commands
if ! echo "$COMMAND" | grep -qE 'git\s+(commit|push)'; then
  exit 0
fi

# --- Load protected branches ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCHES_FILE="$HOOK_DIR/protected_branches.txt"

if [ ! -f "$BRANCHES_FILE" ]; then
  exit 0
fi

PROTECTED=$(grep -v '^#' "$BRANCHES_FILE" | grep -v '^[[:space:]]*$' | tr '\n' ' ')

if [ -z "$PROTECTED" ]; then
  exit 0
fi

# --- Get current branch ---
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -z "$CURRENT_BRANCH" ]; then
  exit 0
fi

# --- Check if current branch is protected ---
for BRANCH in $PROTECTED; do
  if [ "$CURRENT_BRANCH" = "$BRANCH" ]; then
    ACTION="commit"
    echo "$COMMAND" | grep -qE 'git\s+push' && ACTION="push"

    python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'BRANCH PROTECTION: attempting to ${ACTION} on protected branch \"${CURRENT_BRANCH}\". Consider working on a feature branch instead.'
    }
}
print(json.dumps(result))
"
    exit 0
  fi
done

exit 0
