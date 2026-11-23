#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Import Validator
# =============================================================================
# Detects forbidden imports, unsafe code patterns, and debug statements
# in code being written by Claude.
#
# Patterns (forbidden_imports.txt) are Python regular expressions, matched
# case-insensitively: lookaheads such as (?!.*Loader) are supported.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PATTERNS_FILE PYCODE REPLY

  get_file_path || return 0

  # Only check code files
  has_ext 'ts|tsx|js|jsx|py|go|cs|java|cpp|c|rs|rb|php|sh' || return 0

  PATTERNS_FILE="$HOOK_DIR/forbidden_imports.txt"
  [ -f "$PATTERNS_FILE" ] || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
matches = scan(ARGS[0], CONTENT, re.I) if CONTENT else []
if matches:
    ask('IMPORT/CODE VIOLATION: ' + '; '.join(matches)[:200])
PYEOF

  run_py "$PYCODE" "$PATTERNS_FILE"
  return 0
}

main
