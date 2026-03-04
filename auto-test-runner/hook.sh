#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Auto Test Runner
# =============================================================================
# After code modifications, detects and runs related test files.
# Supports: Jest, Pytest, Go test, .NET xUnit/NUnit.
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

# Skip if the modified file is itself a test file
if echo "$FILE_PATH" | grep -qE '\.(test|spec|_test)\.(ts|tsx|js|jsx|py|go|cs)$'; then
  exit 0
fi

# --- Detect test framework and find related test file ---
RESULT=$(python3 -c "
import os, sys, glob

file_path = sys.argv[1]
base = os.path.splitext(file_path)[0]
ext = os.path.splitext(file_path)[1]
dirname = os.path.dirname(file_path)
basename_no_ext = os.path.splitext(os.path.basename(file_path))[0]

candidates = []

# JavaScript/TypeScript (Jest, Vitest, Mocha)
if ext in ('.ts', '.tsx', '.js', '.jsx'):
    for test_ext in ('.test', '.spec'):
        for e in ('.ts', '.tsx', '.js', '.jsx'):
            candidates.append(base + test_ext + e)
            # Check __tests__ directory
            candidates.append(os.path.join(dirname, '__tests__', basename_no_ext + test_ext + e))

# Python (Pytest)
elif ext == '.py':
    candidates.append(os.path.join(dirname, 'test_' + os.path.basename(file_path)))
    candidates.append(os.path.join(dirname, basename_no_ext + '_test.py'))
    candidates.append(os.path.join(dirname, 'tests', 'test_' + os.path.basename(file_path)))

# Go
elif ext == '.go':
    candidates.append(base + '_test.go')

# C# (.NET)
elif ext == '.cs':
    candidates.append(base + 'Tests.cs')
    candidates.append(base + 'Test.cs')
    # Look in parallel test project
    test_dir = dirname.replace('/src/', '/tests/').replace('\\\\src\\\\', '\\\\tests\\\\')
    candidates.append(os.path.join(test_dir, basename_no_ext + 'Tests.cs'))

for c in candidates:
    if os.path.isfile(c):
        print(c)
        break
" "$FILE_PATH" 2>/dev/null)

if [ -z "$RESULT" ]; then
  exit 0
fi

# --- Determine test command ---
TEST_CMD=$(python3 -c "
import os, sys

test_file = sys.argv[1]
project_dir = os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd())

ext = os.path.splitext(test_file)[1]

if ext in ('.ts', '.tsx', '.js', '.jsx'):
    # Check for package.json test script
    if os.path.isfile(os.path.join(project_dir, 'package.json')):
        print('npx jest --testPathPattern=\"' + os.path.basename(test_file) + '\" --no-coverage 2>&1 | tail -20')
    else:
        print('')
elif ext == '.py':
    print('python3 -m pytest \"' + test_file + '\" -v --tb=short 2>&1 | tail -20')
elif ext == '.go':
    print('go test -v -run \"\" \"' + os.path.dirname(test_file) + '/...\" 2>&1 | tail -20')
elif ext == '.cs':
    print('dotnet test --filter \"FullyQualifiedName~' + os.path.splitext(os.path.basename(test_file))[0] + '\" --no-build 2>&1 | tail -20')
else:
    print('')
" "$RESULT" 2>/dev/null)

if [ -n "$TEST_CMD" ]; then
  # Run the test and capture output
  TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
  TEST_EXIT=$?

  # Log test results
  PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  LOG_DIR="$PROJECT_DIR/.claude"
  mkdir -p "$LOG_DIR"

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  if [ $TEST_EXIT -eq 0 ]; then
    echo "[$TIMESTAMP] AUTO-TEST PASS: $RESULT" >> "$LOG_DIR/test-results.log"
  else
    echo "[$TIMESTAMP] AUTO-TEST FAIL: $RESULT" >> "$LOG_DIR/test-results.log"
    echo "$TEST_OUTPUT" >> "$LOG_DIR/test-results.log"
    echo "---" >> "$LOG_DIR/test-results.log"
  fi
fi

exit 0
