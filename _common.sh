#!/bin/bash
# claude_hooks — Auteur : Aurélien Moote - Moo - 2026 — Licence MIT
# =============================================================================
# Claude Code Hooks - Shared library (sourced by every hook)
# =============================================================================
# Installed next to the hooks as .claude/hooks/_common.sh by install.sh.
#
# Design goals:
#   - No process spawn on the common "nothing to report" path: the hook JSON is
#     read and its scalar fields (tool_name, file_path, command, ...) extracted
#     with bash builtins only. Starting python costs 20 ms (Linux) to 300 ms
#     (Windows), so it is reserved for hooks that really need to analyse content.
#   - Never interpolate untrusted text (file content, commands, paths) into
#     code: JSON output is built by json_escape / json.dumps only.
#   - Compatible with bash 3.2 (macOS), Git Bash, Cygwin, WSL and Linux.
#
# The caller must set HOOK_DIR (directory of the running hook) before sourcing.
#
# Writing a hook - the rules that let _dispatch.sh run every hook of an event
# inside one single process (checked by tests/run-tests.sh):
#   - the body lives in a main() function called on the last line of the file;
#   - every variable it assigns is declared `local` (no state leaks to the next
#     hook); only configuration constants are assigned at the top of the file;
#   - it leaves with `return 0`, never `exit` (which would stop the other hooks);
#   - run_py, when used, is the last action of the hook.
# =============================================================================

# Already loaded: the hook is being run by _dispatch.sh, which read stdin once
# for every hook of the event. Functions and INPUT are inherited.
[ -n "${_CLAUDE_HOOKS_COMMON:-}" ] && return 0
_CLAUDE_HOOKS_COMMON=1

# Whole hook input (JSON on stdin). $(<file) avoids spawning `cat`.
INPUT=$(</dev/stdin)

case "${OSTYPE:-}" in
  msys*|cygwin*|win32*) IS_WIN=1 ;;
  *)                    IS_WIN=0 ;;
esac

# Matches "git [global options] " so that `git -C dir commit` or
# `git -c key=value commit` are recognised. Append the subcommand, e.g.
#   [[ $COMMAND =~ ${GIT_RE}commit([^[:alnum:]_-]|$) ]]
GIT_RE='(^|[^[:alnum:]_./-])git[[:space:]]+(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*'

# --- JSON input ---------------------------------------------------------------
# Inside a JSON string every double quote is escaped, so `"key":"` can only
# match a real key, never text inside a value.
_JSON_STR_TAIL='"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'

# json_unescape RAW -> REPLY (decoded JSON string body)
json_unescape() {
  REPLY=$1
  [[ $REPLY == *\\* ]] || return 0
  REPLY=${REPLY//\\\\/$'\001'}        # protect escaped backslashes
  REPLY=${REPLY//\\\"/\"}
  REPLY=${REPLY//\\\//\/}
  REPLY=${REPLY//$'\001'/\\\\}
  printf -v REPLY '%b' "$REPLY"       # \n \t \r \b \f \\ \uXXXX
}

# json_str KEY -> REPLY = decoded value of the first string field named KEY.
# Returns 1 when the key is absent or not a string.
json_str() {
  REPLY=
  [[ $INPUT == *"\"$1\""* ]] || return 1
  local re="\"$1$_JSON_STR_TAIL"
  [[ $INPUT =~ $re ]] || return 1
  json_unescape "${BASH_REMATCH[1]}"
}

# json_prefix KEY N -> REPLY = at most the first N characters of a string field
# (cheap even when the value is huge, e.g. old_string / content).
json_prefix() {
  REPLY=
  [[ $INPUT == *"\"$1\""* ]] || return 1
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.){0,$2})"
  [[ $INPUT =~ $re ]] || return 1
  json_unescape "${BASH_REMATCH[1]}"
}

# json_num KEY -> REPLY = integer value of the first numeric field named KEY.
json_num() {
  REPLY=
  local re="\"$1\"[[:space:]]*:[[:space:]]*(-?[0-9]+)"
  [[ $INPUT =~ $re ]] || return 1
  REPLY=${BASH_REMATCH[1]}
}

# --- Paths ----------------------------------------------------------------------
# norm_path PATH -> REPLY with forward slashes (Claude Code sends C:\dir\file on
# Windows; forward slashes work with every tool of Git Bash / Cygwin).
norm_path() {
  REPLY=$1
  if (( IS_WIN )) || [[ $REPLY =~ ^[A-Za-z]:\\ ]]; then
    REPLY=${REPLY//\\//}
  fi
}

# get_file_path [or_path] -> FILE_PATH from tool_input.file_path (falls back to
# tool_input.path when an argument is given: Grep / Glob). Returns 1 if none.
get_file_path() {
  FILE_PATH=
  json_str file_path && [ -n "$REPLY" ] || { [ -n "${1:-}" ] && json_str path && [ -n "$REPLY" ]; } || return 1
  norm_path "$REPLY"
  FILE_PATH=$REPLY
}

# has_ext 'c|h|cpp' [nocase] -> 0 when FILE_PATH ends with one of the extensions.
has_ext() {
  local re="\\.($1)\$" rc
  [ -n "${2:-}" ] && shopt -s nocasematch
  [[ $FILE_PATH =~ $re ]]; rc=$?
  [ -n "${2:-}" ] && shopt -u nocasematch
  return $rc
}

# get_project_dir -> PROJECT_DIR (no trailing slash), without spawning git when
# Claude Code provides CLAUDE_PROJECT_DIR or the hook lives in <project>/.claude/hooks.
get_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    norm_path "$CLAUDE_PROJECT_DIR"; PROJECT_DIR=$REPLY
  elif [[ $HOOK_DIR == */.claude/hooks ]]; then
    PROJECT_DIR=${HOOK_DIR%/.claude/hooks}
  else
    PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_DIR=$PWD
  fi
  PROJECT_DIR=${PROJECT_DIR%/}
}

ensure_dir() { [ -d "$1" ] || mkdir -p "$1"; }

# find_timeout -> TIMEOUT_BIN = path of GNU `timeout`, or empty when unavailable.
find_timeout() {
  case "${OSTYPE:-}" in
    msys*|cygwin*) TIMEOUT_BIN=/usr/bin/timeout ;;   # not Windows' own timeout.exe
    *)             TIMEOUT_BIN=$(type -P timeout) ;;
  esac
  [ -n "$TIMEOUT_BIN" ] && [ -x "$TIMEOUT_BIN" ] || TIMEOUT_BIN=
}

# now VAR STRFTIME_FORMAT -> VAR = formatted current time (builtin on bash >= 4.2).
now() {
  printf -v "$1" "%($2)T" -1 2>/dev/null || printf -v "$1" '%s' "$(date "+$2")"
}

# --- Pattern files --------------------------------------------------------------
# load_patterns FILE -> REGEX = non-comment lines joined with "|" (grep -E syntax).
# Returns 1 when the file is missing or holds no pattern. CRLF-safe.
load_patterns() {
  REGEX=
  [ -f "$1" ] || return 1
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in '#'*|'') continue ;; esac
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    REGEX+=${REGEX:+|}$line
  done < "$1"
  [ -n "$REGEX" ]
}

# path_gate RULES_FILE SEPARATOR -> 0 when FILE_PATH may match the file pattern
# (text before SEPARATOR) of at least one rule, 1 when it certainly matches none.
# Lets rule-based hooks exit without starting python. Patterns using syntax that
# bash and python may interpret differently (\w, \d, lookaheads...) are never
# trusted: the gate then answers "maybe" and python decides.
path_gate() {
  [ -f "$1" ] || return 1
  local line pat rc
  shopt -s nocasematch
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in '#'*|'') continue ;; esac
    [[ $line == *"$2"* ]] || continue
    pat=${line%%"$2"*}
    pat=${pat#"${pat%%[![:space:]]*}"}; pat=${pat%"${pat##*[![:space:]]}"}
    if [[ $pat == *\\[[:alnum:]]* || $pat == *'(?'* || $pat == *'['* ]]; then
      shopt -u nocasematch; return 0
    fi
    [[ $FILE_PATH =~ $pat ]]; rc=$?
    if (( rc != 1 )); then shopt -u nocasematch; return 0; fi
  done < "$1"
  shopt -u nocasematch
  return 1
}

# --- JSON output ----------------------------------------------------------------
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//[$'\001'-$'\037']/ }
  REPLY=$s
}

# A hook answers with one JSON line: printed when it runs on its own, kept in
# memory when the dispatcher runs several hooks and merges their answers.
_emit_line() {
  if [ -n "${_HOOKS_IN_DISPATCHER:-}" ]; then
    _HOOK_OUT+=$1$'\n'
  else
    printf '%s\n' "$1"
  fi
}

# emit_pre ask|deny|allow REASON   (PreToolUse decision)
emit_pre() {
  json_escape "$2"
  _emit_line "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"$1\",\"permissionDecisionReason\":\"$REPLY\"}}"
}

# emit_post MESSAGE   (PostToolUse warning: systemMessage is shown to the user,
# additionalContext is given to Claude next to the tool result)
emit_post() {
  json_escape "$1"
  _emit_line "{\"systemMessage\":\"$REPLY\",\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$REPLY\"}}"
}

# emit_warning MESSAGE   (non-blocking warning shown to the user, any event)
emit_warning() {
  json_escape "$1"
  _emit_line "{\"systemMessage\":\"$REPLY\"}"
}

# surely_no_match TEXT REGEX -> 0 only when it is CERTAIN that `grep -iE REGEX`
# would not match TEXT. Lets a hook skip spawning grep (20-50 ms on Windows) for
# the vast majority of inputs. The check uses bash's own regex engine on a
# wider pattern (a superset of what grep accepts): GNU escapes are translated
# (\s \S \w \W) or dropped (\b: dropping an assertion can only match more).
# Anything not provably equivalent answers "maybe" (1) and grep decides.
surely_no_match() {
  local text=$1 r rc bracket='\[[^]]*\\'
  # Per-line anchors and non-ASCII case folding differ between engines
  [[ $text == *$'\n'* || $text == *[![:ascii:]]* || $2 == *[![:ascii:]]* ]] && return 1
  r=${2//\\\\/$'\001'}                       # protect escaped backslashes
  [[ $r =~ $bracket ]] && return 1           # backslash inside a [...] expression
  r=${r//\\s/[[:space:]]}
  r=${r//\\S/[^[:space:]]}
  r=${r//\\w/[[:alnum:]_]}
  r=${r//\\W/[^[:alnum:]_]}
  r=${r//\\b/}
  [[ $r == *\\[[:alnum:]]* ]] && return 1     # any other escape: not trusted
  r=${r//$'\001'/\\\\}
  shopt -s nocasematch
  [[ $text =~ $r ]]; rc=$?
  shopt -u nocasematch
  (( rc == 1 ))                               # 0 = match, 2 = regex not usable here
}

# grep_failed HOOK_NAME FILE   (call when grep exits with status >= 2)
grep_failed() {
  emit_warning "$1: invalid regular expression in ${2##*/} - the hook cannot scan until it is fixed."
}

# --- Python (only for hooks that analyse content) -------------------------------
# run_py CODE [ARGS...] -> runs CODE after a common prelude, hook JSON on stdin.
# Prelude: D (input), TOOL, INP (tool_input), PATH (forward slashes), CONTENT
# (new_string or content), ARGS, ask(), notify(), rules(), rx(), scan(), read_file().
#
# On its own a hook runs python at once. Inside the dispatcher the call is only
# queued: once all the hooks of the event have run, run_py_queue executes every
# queued analysis in ONE python process (starting the interpreter is the
# expensive part: 20 ms on Linux, up to 300 ms on Windows).
_PY_SEP=$'\037'     # between the arguments of one analysis
_PY_RS=$'\036'      # between the documents sent to python on stdin
_PY_PRELUDE=""      # loaded on first use
_PY_RUNNER=""
run_py() {
  local code=$1 arg joined=""
  shift
  for arg in "$@"; do joined+=$arg$_PY_SEP; done
  if [ -n "${_HOOKS_IN_DISPATCHER:-}" ]; then
    _PY_CODE+=("$code")
    _PY_ARGS+=("$joined")
    return 0
  fi
  local -a _PY_CODE=("$code") _PY_ARGS=("$joined")
  run_py_queue
}

# run_py_queue -> runs the queued analyses in a single python process.
#   stdin: hook JSON, prelude, then one code block per analysis (RS-separated;
#          JSON never contains a raw control character, so RS cannot collide)
#   argv : for each analysis, its number of arguments followed by the arguments
#          (kept on the command line so that Git Bash converts POSIX paths)
run_py_queue() {
  local i rest count stream py=python3
  local -a argv=()
  hash python3 2>/dev/null || py=python
  [ -n "$_PY_PRELUDE" ] || _py_load_prelude
  stream=$INPUT$_PY_RS$_PY_PRELUDE
  for i in "${!_PY_CODE[@]}"; do
    stream+=$_PY_RS${_PY_CODE[i]}
    argv+=("")                       # placeholder for the argument count
    count=0; rest=${_PY_ARGS[i]}
    while [ -n "$rest" ]; do
      argv+=("${rest%%"$_PY_SEP"*}")
      rest=${rest#*"$_PY_SEP"}
      count=$((count + 1))
    done
    argv[${#argv[@]}-count-1]=$count
  done
  "$py" -c "$_PY_RUNNER" "${argv[@]}" <<<"$stream"
}

_py_load_prelude() {
  # Runner: executes each analysis in its own namespace; one failing or calling
  # sys.exit() does not prevent the others from running.
  IFS= read -r -d '' _PY_RUNNER <<'PYEOF'
import io, sys, traceback
_parts = sys.stdin.buffer.read().decode('utf-8', 'replace').split('\x1e')
_data, _prelude, _argv = _parts[0].encode('utf-8'), _parts[1], sys.argv[1:]
class _Stdin(object):
    def __init__(self, data):
        self.buffer = io.BytesIO(data)
for _code in _parts[2:]:
    _n = int(_argv[0])
    sys.argv = ['hook'] + _argv[1:1 + _n]
    _argv = _argv[1 + _n:]
    sys.stdin = _Stdin(_data)
    try:
        exec(compile(_prelude + '\n' + _code, '<hook>', 'exec'), {'__name__': '__main__'})
    except SystemExit:
        pass
    except Exception:
        traceback.print_exc()
    sys.stdout.flush()
PYEOF
  IFS= read -r -d '' _PY_PRELUDE <<'PYEOF'
import json, re, sys
try:
    D = json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace'))
except Exception:
    sys.exit(0)
if not isinstance(D, dict):
    sys.exit(0)
def _s(v):
    return v if isinstance(v, str) else ''
TOOL = _s(D.get('tool_name'))
INP = D.get('tool_input') if isinstance(D.get('tool_input'), dict) else {}
PATH = (_s(INP.get('file_path')) or _s(INP.get('path'))).replace('\\', '/')
CONTENT = _s(INP.get('new_string')) or _s(INP.get('content'))
ARGS = sys.argv[1:]

def _emit(obj):
    sys.stdout.write(json.dumps(obj) + '\n')

def ask(reason):
    _emit({'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                                  'permissionDecision': 'ask',
                                  'permissionDecisionReason': reason}})

def notify(message):
    _emit({'systemMessage': message,
           'hookSpecificOutput': {'hookEventName': 'PostToolUse',
                                  'additionalContext': message}})

def rules(path):
    """Non-empty, non-comment lines of a rules/patterns file."""
    try:
        with open(path, encoding='utf-8-sig', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    yield line
    except OSError:
        return

def rx(pattern, flags=0):
    """Compile a user-supplied regex; an invalid one is reported, not fatal."""
    try:
        return re.compile(pattern, flags)
    except re.error as e:
        sys.stderr.write('claude-hooks: invalid regex %r: %s\n' % (pattern, e))
        return None

def line_of(text, pos):
    """(line number, stripped line) of the character offset pos."""
    start = text.rfind('\n', 0, pos) + 1
    end = text.find('\n', pos)
    if end < 0:
        end = len(text)
    if end < start:
        end = start
    return text.count('\n', 0, start) + 1, text[start:end].strip()

def first_hit(regex, text):
    """Stripped line of the first match of a compiled regex, or None."""
    m = regex.search(text)
    return line_of(text, m.start())[1] if m else None

def scan(patterns_file, text, flags=0, limit=3):
    """'N:line' for the first lines of text matched by any pattern of the file."""
    found = {}
    for pattern in rules(patterns_file):
        r = rx(pattern, flags | re.M)
        if not r:
            continue
        for n, m in enumerate(r.finditer(text)):
            if n >= limit:
                break
            num, line = line_of(text, m.start())
            found.setdefault(num, line)
    return ['%d:%s' % (num, found[num]) for num in sorted(found)[:limit]]

def read_file(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return None
PYEOF
}
