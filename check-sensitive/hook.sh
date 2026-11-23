#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Sensitive Data Scanner
# =============================================================================
# Scans files BEFORE they are sent to Anthropic's servers via Read/Grep/Edit/Write.
# If sensitive patterns are found, prompts the user for confirmation.
#
#   - Read / Edit / Write / Grep on a file: the file is scanned.
#   - Grep on a directory in "content" mode (matching lines are returned to
#     Claude): the lines the search would return are scanned. When the search
#     cannot be reproduced faithfully with grep, every searched file is scanned.
#     Other Grep modes only return file names or counts: nothing to scan.
#
# Install: run install.sh in your project, or copy manually:
#   1. Copy this file + _common.sh + sensitive_patterns.txt to .claude/hooks/
#   2. Add hook config to .claude/settings.json (see install.sh)
#
# Requires: bash, grep
# =============================================================================

# --- Configuration ---
SCAN_TIMEOUT=3   # Seconds allowed for a directory scan (needs GNU `timeout`)

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH GLOB GREP_OPTS HITS MATCHES MATCH_COUNT PATTERN PATTERNS_FILE PRECISE PREVIEW RC
  local REGEX REPLY RUN TIMEOUT_BIN TOOL_NAME

  json_str tool_name; TOOL_NAME=$REPLY

  # "file_path" (Read/Edit/Write) or "path" (Grep/Glob); Grep defaults to the cwd
  if ! get_file_path or_path; then
    [ "$TOOL_NAME" = "Grep" ] || return 0
    if json_str cwd && [ -n "$REPLY" ]; then norm_path "$REPLY"; FILE_PATH=$REPLY; else FILE_PATH=$PWD; fi
  fi
  [ -e "$FILE_PATH" ] || return 0

  # Regex built from non-empty, non-comment lines of the patterns file
  PATTERNS_FILE="$HOOK_DIR/sensitive_patterns.txt"
  load_patterns "$PATTERNS_FILE" || return 0

  # join_preview TEXT -> MATCH_COUNT, PREVIEW (first 3 lines joined)
  join_preview() {
    local line
    MATCH_COUNT=0; PREVIEW=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      MATCH_COUNT=$((MATCH_COUNT + 1))
      line=${line%$'\r'}
      (( MATCH_COUNT <= 3 )) && PREVIEW+="${line#"$FILE_PATH"/}; "
    done <<<"$1"
  }

  # ----------------------------------------------------------------------------- single file
  if [ -f "$FILE_PATH" ]; then
    MATCHES=$(grep -inE -m5 -e "$REGEX" -- "$FILE_PATH" 2>/dev/null)
    RC=$?
    if (( RC >= 2 )); then
      grep_failed check-sensitive "$PATTERNS_FILE"
    elif [ -n "$MATCHES" ]; then
      join_preview "$MATCHES"
      # "ask" decision: the user sees the warning and can approve or deny
      emit_pre ask "SENSITIVE DATA in ${FILE_PATH} (${MATCH_COUNT} match). Preview: ${PREVIEW:0:200}"
    fi
    return 0
  fi

  # ----------------------------------------------------------------------------- Grep on a directory
  [ -d "$FILE_PATH" ] && [ "$TOOL_NAME" = "Grep" ] || return 0
  json_str output_mode; [ "$REPLY" = "content" ] || return 0

  # A broken patterns file must be reported, not silently ignored
  grep -iE -e "$REGEX" </dev/null >/dev/null 2>&1
  if (( $? >= 2 )); then
    grep_failed check-sensitive "$PATTERNS_FILE"
    return 0
  fi

  json_str pattern; PATTERN=$REPLY
  json_str glob;    GLOB=$REPLY

  # .claude is skipped: it holds the patterns file itself, which matches by nature
  GREP_OPTS=(-rI --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.claude)
  # Simple globs only ("*.ts"); otherwise search every file (a superset: still safe)
  [ -n "$GLOB" ] && [[ $GLOB != */* && $GLOB != *[{}]* ]] && GREP_OPTS+=(--include="$GLOB")
  [[ $INPUT =~ \"-i\"[[:space:]]*:[[:space:]]*true ]] && GREP_OPTS+=(-i)

  find_timeout
  RUN=()
  [ -n "$TIMEOUT_BIN" ] && RUN=("$TIMEOUT_BIN" "$SCAN_TIMEOUT")

  # Can grep -E reproduce Claude's (ripgrep) search? Only for patterns whose syntax
  # means the same in both: no \d-like escapes, no (?...) groups, no lazy
  # quantifiers, no multiline mode.
  PRECISE=0
  if [ -n "$PATTERN" ] && ! [[ $INPUT =~ \"multiline\"[[:space:]]*:[[:space:]]*true ]] \
     && [[ $PATTERN != *\\[ac-rt-vx-zAC-RT-VX-Z0-9]* && $PATTERN != *'(?'* && $PATTERN != *[*+?]'?'* ]]; then
    grep -E -e "$PATTERN" </dev/null >/dev/null 2>&1
    (( $? < 2 )) && PRECISE=1
  fi

  if (( PRECISE )); then
    # Lines the search would return, filtered by the sensitive patterns
    HITS=$(set -o pipefail
           "${RUN[@]}" grep "${GREP_OPTS[@]}" -HnE -e "$PATTERN" -- "$FILE_PATH" 2>/dev/null | grep -iE -m5 -e "$REGEX")
    RC=$?
    if [ -n "$HITS" ]; then
      join_preview "$HITS"
      emit_pre ask "SENSITIVE DATA in Grep results under ${FILE_PATH} (${MATCH_COUNT} match). Preview: ${PREVIEW:0:300}"
      return 0
    fi
  else
    # Files of the searched tree containing sensitive data
    HITS=$(set -o pipefail
           "${RUN[@]}" grep "${GREP_OPTS[@]}" -liE -e "$REGEX" -- "$FILE_PATH" 2>/dev/null | head -n 5)
    RC=$?
    if [ -n "$HITS" ]; then
      join_preview "$HITS"
      emit_pre ask "SENSITIVE DATA in files searched by Grep under ${FILE_PATH}: ${PREVIEW:0:300}Results may include it."
      return 0
    fi
  fi

  if (( RC == 124 )); then
    emit_pre ask "SENSITIVE DATA: the scan of ${FILE_PATH} timed out after ${SCAN_TIMEOUT}s, Grep results could not be checked. Narrow the search path or confirm."
  fi
  return 0
}

main
