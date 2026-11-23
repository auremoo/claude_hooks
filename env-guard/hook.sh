#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - Environment Guard
# =============================================================================
# Prevents environment cross-contamination by detecting production URLs
# in dev configs, localhost in production files, etc.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PYCODE REPLY RULES_FILE

  get_file_path or_path || return 0

  # Fast exit (no python) when no rule applies to this file
  RULES_FILE="$HOOK_DIR/env_rules.txt"
  path_gate "$RULES_FILE" ' | ' || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
# For the Read tool, scan the file on disk; for Edit/Write, scan the new content
content = read_file(PATH) if TOOL == 'Read' else CONTENT
if not PATH or not content:
    sys.exit(0)
lines = content.split('\n')
violations = []
for rule in rules(ARGS[0]):
    # FILE_PATTERN | FORBIDDEN_CONTENT_PATTERN | MESSAGE  (patterns may contain "|")
    head, sep, message = rule.rpartition(' | ')
    file_pattern, sep2, content_pattern = head.partition(' | ')
    if not sep or not sep2:
        continue
    file_rx = rx(file_pattern.strip(), re.I)
    if not file_rx or not file_rx.search(PATH):
        continue
    content_rx = rx(content_pattern.strip(), re.I)
    if not content_rx:
        continue
    for line in lines:
        if content_rx.search(line):
            violations.append('%s: %s' % (message.strip(), line.strip()[:60]))
            break
if violations:
    ask('ENV GUARD: ' + '; '.join(violations[:3])[:250])
PYEOF

  run_py "$PYCODE" "$RULES_FILE"
  return 0
}

main
