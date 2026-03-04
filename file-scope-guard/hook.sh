#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - File Scope Guard
# =============================================================================
# Restricts Claude to only access files within allowed directories.
# Blocks access to sensitive system paths (SSH keys, credentials, etc.).
# =============================================================================

INPUT=$(cat)

# Extract file path from hook JSON input
FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    # Handle different tool input formats
    path = inp.get('file_path', '') or inp.get('path', '') or inp.get('pattern', '')
    print(path)
except:
    print('')
" "$INPUT" 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Resolve to absolute path if relative
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# --- Always-blocked paths (sensitive system files) ---
BLOCKED_PATHS=(
  "$HOME/.ssh"
  "$HOME/.gnupg"
  "$HOME/.aws"
  "$HOME/.config/gh"
  "$HOME/.env"
  "/etc/shadow"
  "/etc/passwd"
  "/etc/sudoers"
)

for BLOCKED in "${BLOCKED_PATHS[@]}"; do
  if [[ "$FILE_PATH" == "$BLOCKED"* ]]; then
    python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': 'FILE SCOPE GUARD: access to ${FILE_PATH} is BLOCKED (sensitive system path).'
    }
}
print(json.dumps(result))
"
    exit 0
  fi
done

# --- Load allowed paths ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWED_FILE="$HOOK_DIR/allowed_paths.txt"

if [ ! -f "$ALLOWED_FILE" ]; then
  exit 0
fi

# Get project directory (parent of .claude/)
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Read allowed paths, replacing $PROJECT_DIR placeholder
ALLOWED_PATHS=()
while IFS= read -r line; do
  [[ "$line" =~ ^#.*$ ]] && continue
  [[ -z "${line// /}" ]] && continue
  resolved="${line//\$PROJECT_DIR/$PROJECT_DIR}"
  ALLOWED_PATHS+=("$resolved")
done < "$ALLOWED_FILE"

# If no allowed paths configured, allow everything (except blocked above)
if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

# Check if file is under an allowed path
for ALLOWED in "${ALLOWED_PATHS[@]}"; do
  if [[ "$FILE_PATH" == "$ALLOWED"* ]]; then
    exit 0
  fi
done

# File is outside allowed scope
python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',
        'permissionDecisionReason': 'FILE SCOPE GUARD: ${FILE_PATH} is outside allowed project scope. Confirm access?'
    }
}
print(json.dumps(result))
"
exit 0
