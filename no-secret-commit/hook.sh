#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - No Secret Commit
# =============================================================================
# Scans what is about to be committed for secrets (API keys, tokens, passwords)
# before allowing a git commit. Acts as a lightweight gitleaks/git-secrets.
#
# Scanned content (added lines only, binary files skipped):
#   - git commit ...               -> the staged diff
#   - git commit -a / -am ...      -> staged + unstaged changes of tracked files
#   - git add ... && git commit    -> same, plus untracked (non-ignored) files,
#                                     since nothing is staged yet when the hook runs
# The whole scan is one git + sed + grep pipeline, whatever the number of files.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local COMMAND CURRENT_FILE DIFF_BASE FILE_HITS FOUND_COUNT FOUND_SECRETS HITS PATTERNS_FILE RC
  local REGEX REPLY RE_ADD RE_ALL RE_COMMIT SOH UNTRACKED_HITS WITH_UNTRACKED line

  json_str command || return 0
  COMMAND=$REPLY

  # Only check git commit commands
  RE_COMMIT="${GIT_RE}commit([^[:alnum:]_-]|\$)"
  [[ $COMMAND =~ $RE_COMMIT ]] || return 0

  PATTERNS_FILE="$HOOK_DIR/secret_patterns.txt"
  load_patterns "$PATTERNS_FILE" || return 0

  # --- What will be committed? ---
  RE_ADD="${GIT_RE}add([[:space:]]|\$)"
  RE_ALL='commit[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'
  DIFF_BASE="--cached"
  WITH_UNTRACKED=0
  if [[ $COMMAND =~ $RE_ADD ]]; then
    WITH_UNTRACKED=1
    git rev-parse -q --verify HEAD >/dev/null 2>&1 && DIFF_BASE="HEAD"
  elif [[ $COMMAND =~ $RE_ALL ]]; then
    git rev-parse -q --verify HEAD >/dev/null 2>&1 && DIFF_BASE="HEAD"
  fi

  # --- Scan added lines ---
  # sed turns the diff into: <SOH>path for each file header, then its added lines
  # without the leading "+"; grep keeps the headers and the matching lines.
  SOH=$'\001'
  HITS=$(git -c core.quotePath=false diff "$DIFF_BASE" -U0 --no-color --no-ext-diff --diff-filter=ACMR 2>/dev/null \
    | sed -n -e "s/^+++ b\\//$SOH/p" -e "s/^+++ \"b\\/\\(.*\\)\"\$/$SOH\\1/p" -e '/^+++ /d' -e 's/^+//p' \
    | grep -aiE -e "^$SOH|$REGEX" 2>/dev/null)
  RC=$?
  if (( RC >= 2 )); then
    grep_failed no-secret-commit "$PATTERNS_FILE"
    return 0
  fi

  FOUND_SECRETS=""
  FOUND_COUNT=0
  CURRENT_FILE=""
  FILE_HITS=0
  while IFS= read -r line; do
    if [[ $line == "$SOH"* ]]; then
      CURRENT_FILE=${line#"$SOH"}
      FILE_HITS=0
    elif [ -n "$line" ] && (( FILE_HITS < 2 && FOUND_COUNT < 5 )); then
      (( FILE_HITS == 0 )) && FOUND_SECRETS+="${CURRENT_FILE}: "
      FOUND_SECRETS+="${line:0:120}; "
      FILE_HITS=$((FILE_HITS + 1))
      FOUND_COUNT=$((FOUND_COUNT + 1))
    fi
  done <<<"$HITS"

  # Untracked files that the same command is about to `git add`
  if (( WITH_UNTRACKED && FOUND_COUNT < 5 )); then
    UNTRACKED_HITS=$(git ls-files -o --exclude-standard -z 2>/dev/null \
      | xargs -0 grep -InHiE -m2 -e "$REGEX" /dev/null 2>/dev/null | head -n 5)
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      FOUND_SECRETS+="${line:0:150}; "
      FOUND_COUNT=$((FOUND_COUNT + 1))
    done <<<"$UNTRACKED_HITS"
  fi

  if (( FOUND_COUNT > 0 )); then
    emit_pre ask "SECRETS DETECTED in files to commit! ${FOUND_SECRETS:0:300} -- Remove secrets before committing."
  fi
  return 0
}

main
