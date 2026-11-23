#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Auto Test Runner
# =============================================================================
# After code modifications, detects and runs related test files.
# Supports: Vitest, Jest, Pytest, Go test, .NET xUnit/NUnit.
# Results are logged in .claude/test-results.log. A passing run is silent; a
# failing run is reported to Claude with the last lines of the test output.
#
# Registered as an async hook (see hook.json): the tests run in the background
# and never delay Claude; the failure report reaches it on its next turn.
# =============================================================================

# --- Configuration ---
TEST_TIMEOUT=120   # Seconds before a test run is killed (needs GNU `timeout`)

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local BASE C CANDIDATES D DIR E EXT FILE FILE_PATH LOG_FILE NAME PROJECT_DIR PY REASON REPLY
  local RUN_DIR T TAIL TEST_CMD TEST_EXIT TEST_FILE TEST_NAME TEST_OUTPUT TIMEOUT_BIN TIMESTAMP

  get_file_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # Skip if the modified file is itself a test file
  [[ $FILE_PATH =~ \.(test|spec|_test)\.(ts|tsx|js|jsx|py|go|cs)$ ]] && return 0

  # --- Find the related test file ---
  DIR=${FILE_PATH%/*}; [ "$DIR" = "$FILE_PATH" ] && DIR=.
  FILE=${FILE_PATH##*/}
  NAME=${FILE%.*}
  EXT=${FILE##*.}
  BASE="$DIR/$NAME"

  CANDIDATES=()
  case "$EXT" in
    ts|tsx|js|jsx)   # Jest, Vitest
      for T in test spec; do
        for E in ts tsx js jsx; do
          CANDIDATES+=("$BASE.$T.$E" "$DIR/__tests__/$NAME.$T.$E")
        done
      done ;;
    py)              # Pytest
      CANDIDATES=("$DIR/test_$FILE" "$DIR/${NAME}_test.py" "$DIR/tests/test_$FILE") ;;
    go)
      CANDIDATES=("${BASE}_test.go") ;;
    cs)              # .NET, including a parallel tests/ project
      CANDIDATES=("${BASE}Tests.cs" "${BASE}Test.cs" "${DIR/\/src\///tests/}/${NAME}Tests.cs") ;;
    *)
      return 0 ;;
  esac

  TEST_FILE=""
  for C in "${CANDIDATES[@]}"; do
    if [ -f "$C" ]; then TEST_FILE=$C; break; fi
  done
  [ -n "$TEST_FILE" ] || return 0

  # --- Determine test command (as an argument vector: no eval, no quoting issue) ---
  get_project_dir
  TEST_CMD=()
  RUN_DIR=$PWD
  case "$EXT" in
    ts|tsx|js|jsx)
      # Use the runner installed in the nearest node_modules (never download one)
      D=$DIR
      while :; do
        if   [ -e "$D/node_modules/.bin/vitest" ]; then TEST_CMD=(npx vitest run "$TEST_FILE"); RUN_DIR=$D; break
        elif [ -e "$D/node_modules/.bin/jest" ];   then TEST_CMD=(npx jest "${TEST_FILE##*/}" --no-coverage); RUN_DIR=$D; break
        fi
        [[ $D == "$PROJECT_DIR" || $D != */* ]] && break
        D=${D%/*}
      done ;;
    py)
      PY=python3; hash python3 2>/dev/null || PY=python
      TEST_CMD=("$PY" -m pytest "$TEST_FILE" -v --tb=short) ;;
    go)
      TEST_CMD=(go test -v ./...); RUN_DIR=$DIR ;;
    cs)
      TEST_NAME=${TEST_FILE##*/}
      TEST_CMD=(dotnet test --filter "FullyQualifiedName~${TEST_NAME%.cs}" --no-build) ;;
  esac
  (( ${#TEST_CMD[@]} )) || return 0

  # Kill runaway test runs when GNU timeout is available
  find_timeout
  [ -n "$TIMEOUT_BIN" ] && TEST_CMD=("$TIMEOUT_BIN" "$TEST_TIMEOUT" "${TEST_CMD[@]}")

  # --- Run the test and capture output + real exit status ---
  TEST_OUTPUT=$(cd "$RUN_DIR" && "${TEST_CMD[@]}" 2>&1 </dev/null)
  TEST_EXIT=$?

  # --- Log test results ---
  ensure_dir "$PROJECT_DIR/.claude"
  LOG_FILE="$PROJECT_DIR/.claude/test-results.log"
  now TIMESTAMP '%Y-%m-%d %H:%M:%S'
  if (( TEST_EXIT == 0 )); then
    printf '[%s] AUTO-TEST PASS: %s\n' "$TIMESTAMP" "$TEST_FILE" >> "$LOG_FILE"
  else
    TAIL=$(tail -n 20 <<<"$TEST_OUTPUT")
    {
      printf '[%s] AUTO-TEST FAIL: %s\n' "$TIMESTAMP" "$TEST_FILE"
      printf '%s\n' "$TAIL"
      echo "---"
    } >> "$LOG_FILE"

    # Tell Claude (and the user): an async hook's message is delivered on the next turn
    (( ${#TAIL} > 1500 )) && TAIL="...${TAIL: -1500}"
    REASON="exit code $TEST_EXIT"
    (( TEST_EXIT == 124 )) && [ -n "$TIMEOUT_BIN" ] && REASON="timed out after ${TEST_TIMEOUT}s"
    emit_post "AUTO-TEST FAIL: ${TEST_FILE} fails after the modification of ${FILE_PATH##*/} (${REASON}). Last lines of the test output:"$'\n'"${TAIL}"
  fi
  return 0
}

main
