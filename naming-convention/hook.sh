#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Naming Convention
# =============================================================================
# Checks modified code for naming convention violations based on
# configurable rules per file type.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PYCODE REPLY RULES_FILE

  get_file_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # Only check code files
  has_ext 'ts|tsx|js|jsx|py|go|cs|java|rs|rb|php' || return 0

  # Fast exit (no python) when no rule applies to this file type
  RULES_FILE="$HOOK_DIR/naming_rules.txt"
  path_gate "$RULES_FILE" ' | ' || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
text = read_file(PATH)
if text is None:
    sys.exit(0)
lines = text.split('\n')

# Rules for this file type: FILE_PATTERN | CHECK_TYPE | DETAILS
# (FILE_PATTERN may contain "|", DETAILS may be empty)
checks = []
for rule in rules(ARGS[0]):
    m = re.match(r'^(.*?)\s+\|\s*(\w+)\s*\|\s*(.*)$', rule)
    if not m:
        continue
    file_rx = rx(m.group(1).strip())
    if file_rx and file_rx.search(PATH):
        checks.append((m.group(2), m.group(3).strip()))
if not checks:
    sys.exit(0)

CASES = {
    'camelCase': r'^[a-z][a-zA-Z0-9]*$',
    'PascalCase': r'^[A-Z][a-zA-Z0-9]*$',
    'snake_case': r'^[a-z][a-z0-9_]*$',
    'UPPER_SNAKE_CASE': r'^[A-Z][A-Z0-9_]*$',
    'kebab-case': r'^[a-z][a-z0-9-]*$',
}

def is_case(name, expected):
    """expected: one case name, or several separated by "/" (any of them)."""
    known = [CASES[c.strip()] for c in expected.split('/') if c.strip() in CASES]
    return not known or any(re.match(pattern, name) for pattern in known)

def declarations(pattern):
    declaration_rx = re.compile(pattern)
    for i, line in enumerate(lines):
        m = declaration_rx.match(line)
        if m:
            yield i + 1, m.group(1)

warnings = []
for check, details in checks:
    if check == 'interface_prefix' and details:
        for num, name in declarations(r'^\s*(?:export\s+)?interface\s+(\w+)'):
            if not name.startswith(details):
                warnings.append('Interface "%s" (line %d) should start with "%s"' % (name, num, details))
    elif check == 'function_case' and details:
        for num, name in declarations(r'^\s*(?:export\s+)?(?:async\s+)?(?:def|function|func)\s+(\w+)'):
            if name.startswith('_'):
                continue  # private / magic methods
            if not is_case(name, details):
                warnings.append('Function "%s" (line %d) should be %s' % (name, num, details))
    elif check == 'class_case' and details:
        for num, name in declarations(r'^\s*(?:export\s+)?class\s+(\w+)'):
            if not is_case(name, details):
                warnings.append('Class "%s" (line %d) should be %s' % (name, num, details))

if warnings:
    notify('NAMING CONVENTION in %s: %s' % (PATH.rsplit('/', 1)[-1], '; '.join(warnings[:3])[:300]))
PYEOF

  run_py "$PYCODE" "$RULES_FILE"
  return 0
}

main
