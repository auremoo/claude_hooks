#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Complexity Guard
# =============================================================================
# After code modifications, checks for complexity indicators:
# - Function length (lines)
# - Nesting depth of control structures (if/for/while/try...) inside a function
# - Number of parameters
# Warns if thresholds are exceeded.
#
# Heuristic, language-agnostic analysis: indentation for Python/Ruby, braces
# for the C family (TS/JS, Go, C#, Java, C/C++, Rust, PHP).
# =============================================================================

# --- Configuration ---
MAX_FUNCTION_LINES=50     # Max lines per function
MAX_NESTING_DEPTH=4       # Max nesting depth (if/for/while)
MAX_PARAMETERS=5          # Max function parameters

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PYCODE REPLY

  get_file_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # Only check code files
  has_ext 'ts|tsx|js|jsx|py|go|cs|java|cpp|c|rs|rb|php' || return 0

  IFS= read -r -d '' PYCODE <<'PYEOF'
max_lines, max_depth, max_params = (int(a) for a in ARGS[:3])
text = read_file(PATH)
if text is None:
    sys.exit(0)
lines = text.split('\n')
ext = PATH.rsplit('.', 1)[-1].lower()
warnings = []   # (line index, message)

def warn(index, message):
    warnings.append((index, message))

def count_params(params, ignore=()):
    """Number of top-level, comma-separated parameters."""
    depth, count, current = 0, 0, ''
    for ch in params + ',':
        if ch in '([{<':
            depth += 1
        elif ch in ')]}>':
            depth = max(depth - 1, 0)
        if ch == ',' and depth == 0:
            name = current.strip().split(':')[0].split('=')[0].strip()
            if name and name not in ignore:
                count += 1
            current = ''
        else:
            current += ch
    return count

def closed_groups(header):
    """Outermost balanced (...) groups of a header, as inner texts."""
    groups, stack = [], []
    for pos, ch in enumerate(header):
        if ch == '(':
            stack.append(pos)
        elif ch == ')' and stack:
            start = stack.pop()
            groups = [g for g in groups if g[0] < start] + [(start, pos)]
    return [header[a + 1:b] for a, b in groups]

def check_params(index, params, ignore=()):
    n = count_params(params, ignore)
    if n > max_params:
        warn(index, 'Function at line %d has %d parameters (max: %d)' % (index + 1, n, max_params))

def check_length(start, end):
    length = end - start + 1
    if length > max_lines:
        warn(start, 'Function at line %d is %d lines (max: %d)' % (start + 1, length, max_lines))

def check_depth(index, depth, scope):
    if depth > max_depth and not scope.get('flagged'):
        scope['flagged'] = True
        warn(index, 'Deep nesting (%d levels) at line %d (max: %d)' % (depth, index + 1, max_depth))

# ---------------------------------------------------------------- Python / Ruby
def analyse_indent():
    is_py = ext == 'py'
    def_rx = re.compile(r'^\s*(?:async\s+)?def\s+[\w.?!]+')
    ctrl_rx = re.compile(r'^\s*(?:async\s+)?(?:if|elif|else|for|while|try|except|finally|with|match|'
                         r'unless|elsif|until|case|when|begin|rescue|ensure)\b')
    module = {'indent': -1, 'ctrl': []}
    funcs = [module]
    header_end = -1     # last line of a multi-line "def (...):" signature
    for i, raw in enumerate(lines):
        code = re.sub(r'\s+#.*$', '', raw).rstrip()
        stripped = code.strip()
        if not stripped or stripped.startswith('#') or i <= header_end:
            continue
        expanded = code.expandtabs(4)
        indent = len(expanded) - len(expanded.lstrip())
        while len(funcs) > 1 and indent <= funcs[-1]['indent']:
            f = funcs.pop()
            check_length(f['start'], f['last'])
        for f in funcs[1:]:
            f['last'] = i
        scope = funcs[-1]
        while scope['ctrl'] and indent <= scope['ctrl'][-1]:
            scope['ctrl'].pop()
        if def_rx.match(code):
            header = code
            header_end = i
            while header.count('(') > header.count(')') and header_end + 1 < min(len(lines), i + 30):
                header_end += 1
                header += ' ' + lines[header_end].strip()
            groups = closed_groups(header)
            if groups:
                check_params(i, groups[0], ignore=('self', 'cls', '*', '/'))
            funcs.append({'indent': indent, 'start': i, 'last': i, 'ctrl': []})
        elif ctrl_rx.match(code) and (not is_py or stripped.endswith(':')):
            scope['ctrl'].append(indent)
            check_depth(i, len(scope['ctrl']), scope)
    for f in funcs[1:]:
        check_length(f['start'], f['last'])

# ---------------------------------------------------------------- C family
def analyse_braces():
    strings = r'"(?:\\.|[^"\\])*"|`(?:\\.|[^`\\])*`|'
    strings += r"'(?:\\.|[^'\\])'" if ext == 'rs' else r"'(?:\\.|[^'\\])*'"
    string_rx = re.compile(strings)
    ctrl_rx = re.compile(r'^[}\s]*(?:else\s+)?(?:if|for|foreach|while|switch|catch|try|else|do|finally|'
                         r'match|loop|select|lock|using|synchronized|unsafe|elseif|when)\b')
    func_rx = re.compile(r'\b(?:function|func|fn)\b|=>\s*$|'
                         r'\)\s*(?:(?::|->)\s*[^;={]+|const\b|override\b|final\b|noexcept\b|'
                         r'throws\s+[\w.,\s]+|where\s+[^;{]+)*\s*$')
    anonymous_class_rx = re.compile(r'\bnew\s+[\w.<>, ]+\([^()]*\)\s*$')
    module = {}
    stack = []          # entries: {'kind': 'f'|'c'|'o', ...}
    cleaned = []
    in_comment = False
    for i, raw in enumerate(lines):
        line = raw
        if in_comment:
            end = line.find('*/')
            if end < 0:
                cleaned.append('')
                continue
            line, in_comment = line[end + 2:], False
        line = string_rx.sub('""', line)
        line = re.sub(r'/\*.*?\*/', '', line)
        line = re.sub(r'//.*$', '', line)
        start = line.find('/*')
        if start >= 0:
            line, in_comment = line[:start], True
        cleaned.append(line)

        last_cut = 0
        for pos, ch in enumerate(line):
            if ch == '}':
                last_cut = pos + 1
                if stack:
                    entry = stack.pop()
                    if entry['kind'] == 'f' and not entry['inline']:
                        check_length(entry['start'], i)
            elif ch == '{':
                header = line[last_cut:pos]
                if header.count(')') > header.count('('):
                    header = line[:pos]       # e.g. "function f({ a, b }) {"
                last_cut = pos + 1
                first = i
                # Allman style / multi-line signature: look at the previous lines
                back = i - 1
                while back >= 0 and i - back <= 20 and (
                        not header.strip() or header.count(')') > header.count('(')):
                    previous = cleaned[back]
                    if previous.strip():
                        if re.search(r'[;{}]\s*$', previous):
                            break
                        header = previous + ' ' + header
                        first = back
                    back -= 1
                h = header.strip()
                entry = {'kind': 'o'}
                inline = h.count('(') > h.count(')')
                if ctrl_rx.match(h) or (ext == 'rs' and h.endswith('=>')):
                    entry['kind'] = 'c'
                elif func_rx.search(h) and not anonymous_class_rx.search(h) and \
                        (not inline or re.search(r'\bfunction\b|=>\s*$', h)):
                    entry = {'kind': 'f', 'start': first, 'inline': inline}
                    groups = closed_groups(h)
                    if h.endswith('=>'):
                        if groups and re.search(r'\)\s*(?::[^=]+)?=>$', h):
                            check_params(first, groups[-1])
                    elif groups:
                        receiver = re.match(r'^func\s*\(', h) and len(groups) > 1
                        check_params(first, groups[1] if receiver else groups[0])
                stack.append(entry)
                if entry['kind'] == 'c':
                    depth, scope = 0, module
                    for e in reversed(stack):
                        if e['kind'] == 'f':
                            scope = e
                            break
                        if e['kind'] == 'c':
                            depth += 1
                    check_depth(i, depth, scope)

if ext in ('py', 'rb'):
    analyse_indent()
else:
    analyse_braces()

if warnings:
    warnings.sort()
    summary = '; '.join(message for _, message in warnings[:3])[:300]
    notify('COMPLEXITY WARNING in %s: %s. Consider refactoring.' % (PATH.rsplit('/', 1)[-1], summary))
PYEOF

  run_py "$PYCODE" "$MAX_FUNCTION_LINES" "$MAX_NESTING_DEPTH" "$MAX_PARAMETERS"
  return 0
}

main
