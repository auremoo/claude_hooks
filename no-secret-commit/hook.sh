#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - No Secret Commit
# =============================================================================
# Scans staged files for secrets (API keys, tokens, passwords) before
# allowing a git commit. Acts as a lightweight gitleaks/git-secrets.
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

# --- Load secret patterns ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS_FILE="$HOOK_DIR/secret_patterns.txt"

if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi

REGEX=$(grep -v '^#' "$PATTERNS_FILE" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')

if [ -z "$REGEX" ]; then
  exit 0
fi

# --- Get staged files ---
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)

if [ -z "$STAGED_FILES" ]; then
  # Maybe files are being added in the same command, check git status
  STAGED_FILES=$(git diff --name-only --staged 2>/dev/null)
  if [ -z "$STAGED_FILES" ]; then
    exit 0
  fi
fi

# --- Scan staged file contents ---
FOUND_SECRETS=""

while IFS= read -r file; do
  [ -f "$file" ] || continue

  # Skip binary files
  if file "$file" 2>/dev/null | grep -q "binary"; then
    continue
  fi

  # Scan staged content (what will actually be committed)
  MATCHES=$(git show ":$file" 2>/dev/null | grep -inE "$REGEX" 2>/dev/null | head -3)

  if [ -n "$MATCHES" ]; then
    PREVIEW=$(echo "$MATCHES" | head -2 | tr '\n' '; ' | cut -c1-150 | sed 's/"/\\"/g')
    FOUND_SECRETS="${FOUND_SECRETS}${file}: ${PREVIEW}\n"
  fi
done <<< "$STAGED_FILES"

if [ -n "$FOUND_SECRETS" ]; then
  SAFE_SECRETS=$(echo -e "$FOUND_SECRETS" | head -5 | tr '\n' ' ' | cut -c1-300 | sed 's/"/\\"/g')

  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'SECRETS DETECTED in staged files! ${SAFE_SECRETS} -- Remove secrets before committing.'
    }
}
print(json.dumps(result))
"
  exit 0
fi

exit 0
