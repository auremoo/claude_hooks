#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Architecture Boundary
# =============================================================================
# Enforces architectural layer boundaries by checking imports in modified files.
# Prevents violations like domain importing infrastructure, etc.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PYCODE REPLY RULES_FILE

  get_file_path || return 0

  # Fast exit (no python) when the file belongs to no layer of the rules file
  RULES_FILE="$HOOK_DIR/boundary_rules.txt"
  path_gate "$RULES_FILE" ' -> ' || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
if not PATH or not CONTENT:
    sys.exit(0)
lines = CONTENT.split('\n')
violations = []
for rule in rules(ARGS[0]):
    if ' -> ' not in rule:
        continue
    source, forbidden = (part.strip() for part in rule.split(' -> ', 1))
    source_rx = rx(source, re.I)
    # Does the file belong to the source layer?
    if not source_rx or not source_rx.search(PATH):
        continue
    forbidden_rx = rx(forbidden, re.I)
    if not forbidden_rx:
        continue
    # Does the new content contain a forbidden import?
    for line in lines:
        if forbidden_rx.search(line):
            violations.append('%s -> %s' % (source, line.strip()[:80]))
            break
if violations:
    ask('ARCHITECTURE VIOLATION: %s. This import crosses an architectural boundary.'
        % '; '.join(violations[:3])[:250])
PYEOF

  run_py "$PYCODE" "$RULES_FILE"
  return 0
}

main
