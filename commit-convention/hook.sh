#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Commit Convention
# =============================================================================
# Validates git commit messages follow Conventional Commits format.
# Format: type(scope): description
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
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

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
  exit 0
fi

# Skip amend commits (they modify existing messages)
if echo "$COMMAND" | grep -qE '\-\-amend'; then
  exit 0
fi

# Extract commit message from -m flag
COMMIT_MSG=$(python3 -c "
import sys, re

cmd = sys.argv[1]

# Match -m followed by quoted string (single or double quotes, or heredoc)
# Handle: -m \"msg\", -m 'msg', -m \"\$(cat <<'EOF'...EOF)\"
patterns = [
    r'-m\s+\"([^\"]+)\"',
    r\"-m\s+'([^']+)'\",
    r'-m\s+\"\\\$\(cat <<.*?EOF(.*?)EOF',
]

for p in patterns:
    match = re.search(p, cmd, re.DOTALL)
    if match:
        msg = match.group(1).strip()
        # Get first line only
        first_line = msg.split('\n')[0].strip()
        print(first_line)
        sys.exit(0)

print('')
" "$COMMAND" 2>/dev/null)

if [ -z "$COMMIT_MSG" ]; then
  exit 0
fi

# --- Validate Conventional Commits format ---
# Pattern: type(optional-scope): description
VALID_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
CONVENTION_REGEX="^($VALID_TYPES)(\([a-zA-Z0-9_.-]+\))?: .+"

if ! echo "$COMMIT_MSG" | grep -qE "$CONVENTION_REGEX"; then
  python3 -c "
import json
msg = '''${COMMIT_MSG}'''[:100]
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'COMMIT CONVENTION: message does not follow Conventional Commits format. Got: \"' + msg + '\". Expected: type(scope): description. Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
