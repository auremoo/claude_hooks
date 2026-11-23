#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Branch Protection
# =============================================================================
# Prevents direct commits and pushes to protected branches.
# Asks user for confirmation if a git commit/push targets a protected branch:
#   - commit or push while a protected branch is checked out
#   - push naming a protected branch explicitly (git push origin HEAD:main)
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local ACTION BRANCH BRANCHES_FILE COMMAND CURRENT_BRANCH PROTECTED PUSH_ARGS REPLY RE_COMMIT
  local RE_PUSH TARGET line

  json_str command || return 0
  COMMAND=$REPLY

  # Only check git commit and git push commands
  RE_COMMIT="${GIT_RE}commit([^[:alnum:]_-]|\$)"
  RE_PUSH="${GIT_RE}push([^[:alnum:]_-]|\$)(.*)"
  ACTION=""
  PUSH_ARGS=""
  [[ $COMMAND =~ $RE_COMMIT ]] && ACTION="commit"
  if [[ $COMMAND =~ $RE_PUSH ]]; then
    ACTION="push"
    PUSH_ARGS=${BASH_REMATCH[${#BASH_REMATCH[@]}-1]}
    PUSH_ARGS=${PUSH_ARGS%%[;&|]*}
  fi
  [ -n "$ACTION" ] || return 0

  # --- Load protected branches (one per line) ---
  BRANCHES_FILE="$HOOK_DIR/protected_branches.txt"
  [ -f "$BRANCHES_FILE" ] || return 0
  PROTECTED=()
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    line=${line//[[:space:]]/}
    case "$line" in '#'*|'') continue ;; esac
    PROTECTED+=("$line")
  done < "$BRANCHES_FILE"
  (( ${#PROTECTED[@]} )) || return 0

  CURRENT_BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null)

  for BRANCH in "${PROTECTED[@]}"; do
    TARGET=""
    if [ "$CURRENT_BRANCH" = "$BRANCH" ]; then
      TARGET=$BRANCH
    elif [ "$ACTION" = "push" ]; then
      # Explicit refspec: "origin main", "HEAD:main", "feat:refs/heads/main"
      case " $PUSH_ARGS " in
        *[[:space:]:/+]"$BRANCH"[[:space:]:]*) TARGET=$BRANCH ;;
      esac
    fi
    if [ -n "$TARGET" ]; then
      emit_pre ask "BRANCH PROTECTION: attempting to ${ACTION} on protected branch \"${TARGET}\". Consider working on a feature branch instead."
      return 0
    fi
  done
  return 0
}

main
