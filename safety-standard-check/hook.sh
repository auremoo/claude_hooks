#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Safety Standard Check
# =============================================================================
# Checks code for compliance with industrial safety standards:
# IEC 61508, DO-178C, ISO 26262, IEC 62443, MISRA C.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PYCODE REPLY RULES_FILE

  get_file_path || return 0

  # Only check C/C++/Rust/Ada files (safety-critical languages)
  has_ext 'c|h|cpp|hpp|cc|hh|rs|ada|adb|ads' nocase || return 0

  RULES_FILE="$HOOK_DIR/safety_rules.txt"
  [ -f "$RULES_FILE" ] || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
if not CONTENT:
    sys.exit(0)
violations = []
for rule in rules(ARGS[0]):
    # STANDARD | RULE_ID | PATTERN | MESSAGE  (PATTERN itself may contain "|")
    head, sep, message = rule.rpartition(' | ')
    parts = head.split('|', 2)
    if not sep or len(parts) != 3:
        continue
    standard, rule_id, pattern = (p.strip() for p in parts)
    pattern_rx = rx(pattern, re.M)
    if pattern_rx and pattern_rx.search(CONTENT):
        violations.append('[%s %s] %s' % (standard, rule_id, message.strip()))
if violations:
    ask('SAFETY COMPLIANCE: ' + '; '.join(violations[:4])[:350])
PYEOF

  run_py "$PYCODE" "$RULES_FILE"
  return 0
}

main
