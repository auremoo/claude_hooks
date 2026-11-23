#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Hardware Register Guard
# =============================================================================
# Protects against accidental writes to critical hardware registers:
# watchdog, reset, flash write/erase, power management, boot config.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PATTERNS_FILE PYCODE REPLY

  get_file_path || return 0

  # Only check C/C++ embedded files
  has_ext 'c|h|cpp|hpp|cc|s|asm' nocase || return 0

  PATTERNS_FILE="$HOOK_DIR/protected_registers.txt"
  [ -f "$PATTERNS_FILE" ] || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
if not CONTENT:
    sys.exit(0)
lines = CONTENT.split('\n')
matches = []
for rule in rules(ARGS[0]):
    # pattern | reason   (pattern is a regular expression)
    pattern, sep, reason = rule.rpartition(' | ')
    if not sep:
        pattern, reason = rule, 'Protected register'
    pattern_rx = rx(pattern.strip())
    if not pattern_rx:
        continue
    for line in lines:
        if pattern_rx.search(line):
            matches.append('%s: %s' % (reason.strip(), line.strip()[:60]))
            break
if matches:
    ask('HW REGISTER GUARD: %s. Writing to protected hardware registers requires '
        'explicit confirmation.' % '; '.join(matches[:3])[:300])
PYEOF

  run_py "$PYCODE" "$PATTERNS_FILE"
  return 0
}

main
