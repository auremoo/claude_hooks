#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Complexity Guard
# =============================================================================
# After code modifications, checks for complexity indicators:
# - Function length (lines)
# - Nesting depth
# - Number of parameters
# Warns if thresholds are exceeded.
# =============================================================================

# --- Configuration ---
MAX_FUNCTION_LINES=50     # Max lines per function
MAX_NESTING_DEPTH=4       # Max nesting depth (if/for/while)
MAX_PARAMETERS=5          # Max function parameters

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
if ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|py|go|cs|java|cpp|c|rs|rb|php)$'; then
  exit 0
fi

# --- Analyze complexity ---
WARNINGS=$(python3 -c "
import re, sys

file_path = sys.argv[1]
max_lines = int(sys.argv[2])
max_depth = int(sys.argv[3])
max_params = int(sys.argv[4])

warnings = []

try:
    with open(file_path, 'r', errors='ignore') as f:
        lines = f.readlines()
except:
    sys.exit(0)

# Track function lengths
func_patterns = [
    r'^\s*(def|function|func|fn|public|private|protected|static|async)\s+\w+',
    r'^\s*(const|let|var)\s+\w+\s*=\s*(async\s+)?\(',
    r'^\s*\w+\s*\([^)]*\)\s*[:{]',
]

current_func = None
func_start = 0
brace_depth = 0
max_nesting = 0
current_nesting = 0

for i, line in enumerate(lines):
    stripped = line.strip()

    # Detect function start
    for pattern in func_patterns:
        if re.match(pattern, line):
            # Check previous function length
            if current_func and (i - func_start) > max_lines:
                warnings.append(f'Function at line {func_start+1} is {i-func_start} lines (max: {max_lines})')

            current_func = stripped[:50]
            func_start = i
            max_nesting = 0

            # Count parameters
            params_match = re.search(r'\(([^)]*)\)', line)
            if params_match:
                params = params_match.group(1)
                if params.strip():
                    param_count = len([p for p in params.split(',') if p.strip()])
                    if param_count > max_params:
                        warnings.append(f'Function at line {i+1} has {param_count} parameters (max: {max_params})')
            break

    # Track nesting depth
    nesting_keywords = len(re.findall(r'\b(if|for|while|switch|match|case|try|catch)\b', stripped))
    current_nesting += nesting_keywords
    if stripped.endswith('}') or stripped == 'end':
        current_nesting = max(0, current_nesting - 1)

    if current_nesting > max_depth:
        if f'line {i+1}' not in str(warnings):
            warnings.append(f'Deep nesting ({current_nesting} levels) at line {i+1} (max: {max_depth})')

# Check last function
if current_func and (len(lines) - func_start) > max_lines:
    warnings.append(f'Function at line {func_start+1} is {len(lines)-func_start} lines (max: {max_lines})')

if warnings:
    print('; '.join(warnings[:3]))
else:
    print('')
" "$FILE_PATH" "$MAX_FUNCTION_LINES" "$MAX_NESTING_DEPTH" "$MAX_PARAMETERS" 2>/dev/null)

if [ -n "$WARNINGS" ]; then
  SAFE_WARNINGS=$(echo "$WARNINGS" | cut -c1-300 | sed 's/"/\\"/g')
  BASENAME=$(basename "$FILE_PATH")
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'notification': 'COMPLEXITY WARNING in ${BASENAME}: ${SAFE_WARNINGS}. Consider refactoring.'
    }
}
print(json.dumps(result))
"
fi

exit 0
