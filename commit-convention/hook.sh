#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Commit Convention
# =============================================================================
# Validates git commit messages follow Conventional Commits format.
# Format: type(scope): description      (a "!" before ":" marks a breaking change)
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
#
# Understands -m "msg", -m 'msg', -am "msg", --message="msg" and heredoc
# messages: git commit -m "$(cat <<'EOF' ... EOF)"
# =============================================================================

# --- Configuration ---
VALID_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local COMMAND COMMIT_ARGS COMMIT_MSG CONVENTION_REGEX NL REPLY RE_COMMIT RE_HEREDOC RE_MSG

  json_str command || return 0
  COMMAND=$REPLY

  # Only check git commit commands
  RE_COMMIT="${GIT_RE}commit([^[:alnum:]_-]|\$)(.*)"
  [[ $COMMAND =~ $RE_COMMIT ]] || return 0
  COMMIT_ARGS=${BASH_REMATCH[${#BASH_REMATCH[@]}-1]}

  # Skip amend commits (they modify existing messages)
  [[ $COMMIT_ARGS == *--amend* ]] && return 0

  # --- Extract the first line of the commit message ---
  NL=$'\n'
  RE_HEREDOC="<<-?[[:space:]]*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?[^$NL]*$NL[[:space:]]*([^$NL]*)"
  RE_MSG="(^|[[:space:]])(-[a-zA-Z]*m|--message)[[:space:]=]*(\"(([^\"\\\\]|\\\\.)*)\"|'([^']*)')"
  COMMIT_MSG=""
  if [[ $COMMIT_ARGS =~ $RE_HEREDOC ]]; then
    COMMIT_MSG=${BASH_REMATCH[1]}
  elif [[ $COMMIT_ARGS =~ $RE_MSG ]]; then
    COMMIT_MSG=${BASH_REMATCH[4]}${BASH_REMATCH[6]}
    COMMIT_MSG=${COMMIT_MSG#"${COMMIT_MSG%%[![:space:]]*}"}
    COMMIT_MSG=${COMMIT_MSG%%"$NL"*}
  fi
  COMMIT_MSG=${COMMIT_MSG%"${COMMIT_MSG##*[![:space:]]}"}

  # No inline message (editor, -F file, ...) -> nothing to validate
  [ -n "$COMMIT_MSG" ] || return 0

  # --- Validate Conventional Commits format ---
  CONVENTION_REGEX="^($VALID_TYPES)(\([a-zA-Z0-9_./-]+\))?!?: .+"

  if ! [[ $COMMIT_MSG =~ $CONVENTION_REGEX ]]; then
    emit_pre ask "COMMIT CONVENTION: message does not follow Conventional Commits format. Got: \"${COMMIT_MSG:0:100}\". Expected: type(scope): description. Types: ${VALID_TYPES//|/, }."
  fi
  return 0
}

main
