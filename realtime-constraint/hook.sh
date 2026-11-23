#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Real-Time Constraint
# =============================================================================
# Detects patterns that break real-time determinism in embedded/RTOS code.
# Checks: dynamic allocation, blocking I/O, exceptions, unbounded loops.
#
# Patterns (realtime_violations.txt) are Python regular expressions, matched
# case-sensitively: lookaheads such as (?!.*timeout) are supported.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PATTERNS_FILE PYCODE REPLY

  get_file_path || return 0

  # Only check C/C++/Rust embedded files
  has_ext 'c|h|cpp|hpp|cc|hh|rs|ino' nocase || return 0

  PATTERNS_FILE="$HOOK_DIR/realtime_violations.txt"
  [ -f "$PATTERNS_FILE" ] || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
matches = scan(ARGS[0], CONTENT) if CONTENT else []
if matches:
    ask('REAL-TIME VIOLATION: Non-deterministic pattern detected: %s. '
        'This may break timing guarantees.' % '; '.join(matches)[:200])
PYEOF

  run_py "$PYCODE" "$PATTERNS_FILE"
  return 0
}

main
