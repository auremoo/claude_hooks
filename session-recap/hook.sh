#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Session Recap
# =============================================================================
# Maintains a .claude/session-recap.md file summarizing all actions taken
# during the current session. Useful for handoff or resuming later.
# =============================================================================

INPUT=$(cat)

TOOL_INFO=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    tool_name = d.get('tool_name', 'unknown')
    inp = d.get('tool_input', {})
    file_path = inp.get('file_path', '') or inp.get('path', '')
    command = inp.get('command', '')
    old_string = inp.get('old_string', '')[:80] if inp.get('old_string') else ''
    new_string = inp.get('new_string', '')[:80] if inp.get('new_string') else ''
    print(tool_name)
    print(file_path)
    print(command[:150] if command else '')
    print(old_string)
    print(new_string)
except:
    print('unknown')
    print('')
    print('')
    print('')
    print('')
" "$INPUT" 2>/dev/null)

TOOL_NAME=$(echo "$TOOL_INFO" | sed -n '1p')
FILE_PATH=$(echo "$TOOL_INFO" | sed -n '2p')
COMMAND=$(echo "$TOOL_INFO" | sed -n '3p')
OLD_STR=$(echo "$TOOL_INFO" | sed -n '4p')
NEW_STR=$(echo "$TOOL_INFO" | sed -n '5p')

PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
RECAP_FILE="$PROJECT_DIR/.claude/session-recap.md"
mkdir -p "$PROJECT_DIR/.claude"

TIMESTAMP=$(date '+%H:%M:%S')
DATE=$(date '+%Y-%m-%d')

# Create header if file doesn't exist or is from a different day
if [ ! -f "$RECAP_FILE" ] || ! head -1 "$RECAP_FILE" 2>/dev/null | grep -q "$DATE"; then
  cat > "$RECAP_FILE" << HEADER
# Session Recap - $DATE

## Actions

HEADER
fi

# --- Append action based on tool type ---
case "$TOOL_NAME" in
  Write)
    if [ -n "$FILE_PATH" ]; then
      echo "- \`$TIMESTAMP\` **Created/Wrote** \`$FILE_PATH\`" >> "$RECAP_FILE"
    fi
    ;;
  Edit)
    if [ -n "$FILE_PATH" ]; then
      DETAIL=""
      if [ -n "$OLD_STR" ] && [ -n "$NEW_STR" ]; then
        DETAIL=" — \`${OLD_STR}\` → \`${NEW_STR}\`"
      fi
      echo "- \`$TIMESTAMP\` **Edited** \`$FILE_PATH\`${DETAIL}" >> "$RECAP_FILE"
    fi
    ;;
  Bash)
    if [ -n "$COMMAND" ]; then
      # Only log significant commands
      if echo "$COMMAND" | grep -qE '(git|npm|pip|yarn|pnpm|dotnet|cargo|go |make|docker|terraform|kubectl)'; then
        SAFE_CMD=$(echo "$COMMAND" | tr '\n' ' ' | cut -c1-120)
        echo "- \`$TIMESTAMP\` **Ran** \`$SAFE_CMD\`" >> "$RECAP_FILE"
      fi
    fi
    ;;
esac

exit 0
