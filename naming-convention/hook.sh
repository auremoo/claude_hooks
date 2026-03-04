#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Naming Convention
# =============================================================================
# Checks modified code for naming convention violations based on
# configurable rules per file type.
# =============================================================================

INPUT=$(cat)

FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    print(inp.get('file_path', '') or '')
except:
    print('')
" "$INPUT" 2>/dev/null)

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Only check code files
if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|py|go|cs|java|rs|rb|php)$'; then
  exit 0
fi

# --- Load and apply rules ---
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_FILE="$HOOK_DIR/naming_rules.txt"

if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

WARNINGS=$(python3 -c "
import re, sys, os

file_path = sys.argv[1]
rules_file = sys.argv[2]
warnings = []

try:
    with open(file_path, 'r', errors='ignore') as f:
        content = f.read()
        lines = content.split('\n')
except:
    sys.exit(0)

# Load rules for this file type
rules = []
with open(rules_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [p.strip() for p in line.split('|')]
        if len(parts) == 3:
            file_pattern, check_type, details = parts
            if re.search(file_pattern, file_path):
                rules.append((check_type, details))

if not rules:
    sys.exit(0)

def is_case(name, case_type):
    if case_type == 'camelCase':
        return bool(re.match(r'^[a-z][a-zA-Z0-9]*$', name))
    elif case_type == 'PascalCase':
        return bool(re.match(r'^[A-Z][a-zA-Z0-9]*$', name))
    elif case_type == 'snake_case':
        return bool(re.match(r'^[a-z][a-z0-9_]*$', name))
    elif case_type == 'UPPER_SNAKE_CASE':
        return bool(re.match(r'^[A-Z][A-Z0-9_]*$', name))
    elif case_type == 'kebab-case':
        return bool(re.match(r'^[a-z][a-z0-9-]*$', name))
    return True

for check_type, details in rules:
    if check_type == 'interface_prefix' and details:
        # Find interface declarations without prefix
        for i, line in enumerate(lines):
            match = re.match(r'^\s*(export\s+)?interface\s+(\w+)', line)
            if match:
                name = match.group(2)
                if not name.startswith(details):
                    warnings.append(f'Interface \"{name}\" (line {i+1}) should start with \"{details}\"')

    elif check_type == 'function_case':
        for i, line in enumerate(lines):
            # Match function declarations
            match = re.match(r'^\s*(?:export\s+)?(?:async\s+)?(?:def|function|func)\s+(\w+)', line)
            if match:
                name = match.group(1)
                if name.startswith('_') or name.startswith('__'):
                    continue  # Skip private/magic methods
                if not is_case(name, details):
                    warnings.append(f'Function \"{name}\" (line {i+1}) should be {details}')

    elif check_type == 'class_case' or check_type == 'class_prefix':
        for i, line in enumerate(lines):
            match = re.match(r'^\s*(?:export\s+)?class\s+(\w+)', line)
            if match:
                name = match.group(1)
                if check_type == 'class_case' and not is_case(name, details):
                    warnings.append(f'Class \"{name}\" (line {i+1}) should be {details}')

if warnings:
    print('; '.join(warnings[:3]))
else:
    print('')
" "$FILE_PATH" "$RULES_FILE" 2>/dev/null)

if [ -n "$WARNINGS" ]; then
  SAFE_WARNINGS=$(echo "$WARNINGS" | cut -c1-300 | sed 's/"/\\"/g')
  BASENAME=$(basename "$FILE_PATH")
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'notification': 'NAMING CONVENTION in ${BASENAME}: ${SAFE_WARNINGS}'
    }
}
print(json.dumps(result))
"
fi

exit 0
