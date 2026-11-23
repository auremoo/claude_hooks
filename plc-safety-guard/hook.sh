#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - PLC Safety Guard
# =============================================================================
# Detects unsafe patterns in PLC/automation code before it's written.
# Supports: IEC 61131-3 Structured Text, CODESYS, TwinCAT, Siemens SCL.
#
# Patterns (plc_unsafe_patterns.txt) are Python regular expressions, matched
# case-insensitively: lookaheads such as (?!.*watchdog) are supported.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PATTERNS_FILE PYCODE REPLY

  get_file_path || return 0

  # Check PLC-related files
  has_ext 'st|scl|pou|exp|xml|tmc|plcproj|gsd|aml' nocase || return 0

  PATTERNS_FILE="$HOOK_DIR/plc_unsafe_patterns.txt"
  [ -f "$PATTERNS_FILE" ] || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
matches = scan(ARGS[0], CONTENT, re.I) if CONTENT else []
if matches:
    ask('PLC SAFETY: Unsafe pattern detected in automation code: %s. '
        'Verify safety interlocks before proceeding.' % '; '.join(matches)[:200])
PYEOF

  run_py "$PYCODE" "$PATTERNS_FILE"
  return 0
}

main
