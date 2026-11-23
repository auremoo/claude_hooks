#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Session Recap
# =============================================================================
# Maintains a .claude/session-recap.md file summarizing all actions taken
# during the current session. Useful for handoff or resuming later.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local DATE ENTRY FILE_PATH FIRST_LINE NEW_STR OLD_STR PROJECT_DIR RECAP_FILE REPLY SAFE_CMD
  local TIMESTAMP TOOL_NAME

  json_str tool_name; TOOL_NAME=$REPLY

  # --- Build the entry for this tool call (nothing to log -> exit early) ---
  ENTRY=""
  case "$TOOL_NAME" in
    Write)
      get_file_path || return 0
      ENTRY="**Created/Wrote** \`$FILE_PATH\`"
      ;;
    Edit)
      get_file_path || return 0
      ENTRY="**Edited** \`$FILE_PATH\`"
      json_prefix old_string 80; OLD_STR=${REPLY//[$'\n\r\t']/ }
      json_prefix new_string 80; NEW_STR=${REPLY//[$'\n\r\t']/ }
      if [ -n "$OLD_STR" ] && [ -n "$NEW_STR" ]; then
        ENTRY+=" — \`${OLD_STR}\` → \`${NEW_STR}\`"
      fi
      ;;
    Bash)
      json_str command || return 0
      # Only log significant commands
      [[ $REPLY =~ (git|npm|pip|yarn|pnpm|dotnet|cargo|go\ |make|docker|terraform|kubectl) ]] || return 0
      SAFE_CMD=${REPLY//[$'\n\r\t']/ }
      ENTRY="**Ran** \`${SAFE_CMD:0:120}\`"
      ;;
    *)
      return 0
      ;;
  esac

  get_project_dir
  ensure_dir "$PROJECT_DIR/.claude"
  RECAP_FILE="$PROJECT_DIR/.claude/session-recap.md"

  now TIMESTAMP '%H:%M:%S'
  now DATE '%Y-%m-%d'

  # Create header if file doesn't exist or is from a different day
  FIRST_LINE=""
  [ -f "$RECAP_FILE" ] && IFS= read -r FIRST_LINE < "$RECAP_FILE"
  if [[ $FIRST_LINE != *"$DATE"* ]]; then
    printf '# Session Recap - %s\n\n## Actions\n\n' "$DATE" > "$RECAP_FILE"
  fi

  printf -- '- `%s` %s\n' "$TIMESTAMP" "$ENTRY" >> "$RECAP_FILE"
  return 0
}

main
