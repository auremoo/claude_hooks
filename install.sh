#!/bin/bash
# claude_hooks — Auteur : Aurélien Moote - Moo - 2026 — Licence MIT
# =============================================================================
# Claude Code Hooks - Installer
# =============================================================================
# Usage:
#   bash install.sh /path/to/project                 # install ALL hooks
#   bash install.sh /path/to/project check-sensitive  # install one hook
#   bash install.sh                                   # install all in cwd
#   bash install.sh --standalone /path/to/project     # one settings entry per hook
#
# Auto-discovers hooks from subdirectories via hook.json metadata.
#
# Default mode: hooks are run by a dispatcher (_dispatch.sh), registered once
# per event in settings.json: a single process per tool call, whatever the
# number of hooks. The installed hooks are listed in .claude/hooks/_hooks.conf.
# Async hooks (run in the background) keep their own settings entry.
#
# --standalone: every hook gets its own settings.json entry (one process per
# hook and per tool call, slower; useful to debug or to tune a hook's timeout).
# Both modes can be mixed and switched by re-running the installer.
#
# Idempotent: safe to re-run. Hook scripts and settings.json entries are
# refreshed; user-editable config files (*.txt) are never overwritten.
# Requires: bash, python3
# =============================================================================

set -e

STANDALONE=0
ARGS=()
for ARG in "$@"; do
  case "$ARG" in
    --standalone) STANDALONE=1 ;;
    -h|--help)    sed -n '6,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            ARGS+=("$ARG") ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${ARGS[0]:-.}"
HOOK_FILTER="${ARGS[1]:-}"   # optional: install only this hook

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "=== Claude Code Hooks Installer ==="
echo "Source:  $SCRIPT_DIR"
echo "Target:  $TARGET_DIR"
echo ""

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python

# Everything (discovery, copies, settings.json merge) in one python process
"$PY" - "$SCRIPT_DIR" "$TARGET_DIR" "$HOOK_FILTER" "$STANDALONE" <<'PYEOF'
import glob, json, os, re, shutil, stat, sys

script_dir, target_dir, hook_filter, standalone = sys.argv[1:5]
standalone = standalone == '1'
hooks_dir = os.path.join(target_dir, '.claude', 'hooks')
settings_path = os.path.join(target_dir, '.claude', 'settings.json')
registry_path = os.path.join(hooks_dir, '_hooks.conf')
COMMAND = 'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/%s"'

# --- Discover hooks ---
metas = []
for meta_path in sorted(glob.glob(os.path.join(script_dir, '*', 'hook.json'))):
    hook_dir = os.path.dirname(meta_path)
    name = os.path.basename(hook_dir)
    with open(meta_path, encoding='utf-8') as f:
        metas.append((name, hook_dir, json.load(f)))

selected = [m for m in metas if not hook_filter or m[0] == hook_filter]
if not selected:
    print("[ERROR] Hook '%s' not found in %s/" % (hook_filter, script_dir))
    print('Available hooks:')
    for name, _, _ in metas:
        print('  - ' + name)
    sys.exit(1)

# --- Load settings.json (other keys are preserved) ---
settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, encoding='utf-8') as f:
            settings = json.load(f)
    except ValueError as e:
        print('[ERROR] %s is not valid JSON (%s). Fix it and re-run.' % (settings_path, e))
        sys.exit(1)
if not isinstance(settings, dict) or not isinstance(settings.get('hooks', {}), dict):
    print('[ERROR] %s has an unexpected structure.' % settings_path)
    sys.exit(1)
before = json.dumps(settings, sort_keys=True)
hooks_cfg = settings.setdefault('hooks', {})

os.makedirs(hooks_dir, exist_ok=True)

def copy(src, dst, executable=False):
    shutil.copyfile(src, dst)
    if executable:
        os.chmod(dst, os.stat(dst).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

def script_rx(script_name, argument=None):
    """Matches a settings.json command running .claude/hooks/<script_name> [argument]."""
    tail = r'(?![\w.-])' if argument is None else r'"?\s+%s\b' % re.escape(argument)
    return re.compile(r'[/\\]\.claude[/\\]hooks[/\\]%s%s' % (re.escape(script_name), tail))

def set_entry(command_rx, event, entry):
    """Make `entry` the only registration of the commands matching command_rx
    (entry=None removes them). Returns ADDED, UPDATED, SKIP, REMOVED or NONE."""
    action, placed = ('ADDED' if entry else 'NONE'), False
    for ev in list(hooks_cfg):
        groups = hooks_cfg[ev]
        if not isinstance(groups, list):
            continue
        for group in list(groups):
            handlers = group.get('hooks', []) if isinstance(group, dict) else []
            def ours(h):
                return isinstance(h, dict) and command_rx.search(str(h.get('command', '')))
            if not any(ours(h) for h in handlers):
                continue
            if entry and ev == event and not placed and group == entry:
                action, placed = 'SKIP', True
            elif entry and ev == event and not placed and len(handlers) == 1:
                groups[groups.index(group)] = entry
                action, placed = 'UPDATED', True
            else:
                # Stale registration (other event, duplicate, mixed group, or removal)
                group['hooks'] = [h for h in handlers if not ours(h)]
                if not group['hooks']:
                    groups.remove(group)
                if not entry:
                    action = 'REMOVED'
        if not groups:
            del hooks_cfg[ev]
    if entry and not placed:
        hooks_cfg.setdefault(event, []).append(entry)
    return action

# --- Hooks currently run by the dispatcher: name -> (event, matcher, timeout) ---
registry = {}
if os.path.exists(registry_path):
    with open(registry_path, encoding='utf-8') as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3 and not line.startswith('#'):
                registry[parts[2]] = (parts[0], parts[1], int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else 5)

# Shared library + dispatcher (always refreshed)
copy(os.path.join(script_dir, '_common.sh'), os.path.join(hooks_dir, '_common.sh'))
copy(os.path.join(script_dir, '_dispatch.sh'), os.path.join(hooks_dir, '_dispatch.sh'), executable=True)
print('  [OK] _common.sh (shared library)')
print('  [OK] _dispatch.sh (dispatcher)')
print('')

for name, hook_dir, meta in selected:
    event = meta.get('event', 'PreToolUse')
    matcher = meta.get('matcher', '')
    timeout = int(meta.get('timeout', 5))
    is_async = bool(meta.get('async', False))
    # The dispatcher only handles plain "ToolA|ToolB" matchers of blocking hooks
    individual = standalone or is_async or not re.match(r'^\w+(\|\w+)*$', matcher)

    print('--- Hook: %s ---' % name)
    print('  ' + meta.get('description', ''))
    print('  Event: %s | Matcher: %s | Timeout: %ss%s' % (event, matcher, timeout, ' | async' if is_async else ''))

    # Copy hook files (main script = hook.sh -> <hook-name>.sh)
    script_name = name + '.sh'
    for filename in meta.get('files', []):
        src = os.path.join(hook_dir, filename)
        if filename == 'hook.sh':
            copy(src, os.path.join(hooks_dir, script_name), executable=True)
            print('  [OK] %s (main script)' % script_name)
        elif os.path.exists(os.path.join(hooks_dir, filename)):
            print('  [SKIP] %s (already exists)' % filename)
        else:
            copy(src, os.path.join(hooks_dir, filename))
            print('  [OK] Copied %s' % filename)

    if individual:
        # Own settings.json entry
        handler = {'type': 'command', 'command': COMMAND % script_name, 'timeout': timeout}
        if is_async:
            handler['async'] = True
        action = set_entry(script_rx(script_name), event, {'matcher': matcher, 'hooks': [handler]})
        registry.pop(name, None)
        if action == 'SKIP':
            print('  [SKIP] Already in settings.json')
        else:
            print('  [OK] settings.json %s (%s: %s)' % ('updated' if action == 'UPDATED' else 'entry added', event, name))
    else:
        # Run by the dispatcher: listed in _hooks.conf, no settings entry of its own
        known = registry.get(name) == (event, matcher, timeout)
        registry[name] = (event, matcher, timeout)
        migrated = set_entry(script_rx(script_name), event, None) == 'REMOVED'
        if migrated:
            print('  [OK] Moved from its own settings.json entry to the dispatcher')
        elif known:
            print('  [SKIP] Already handled by the dispatcher')
        else:
            print('  [OK] Registered with the dispatcher (%s)' % event)
    print('')

# --- Registry file + one dispatcher entry per event ---
registry = {n: v for n, v in registry.items() if os.path.exists(os.path.join(hooks_dir, n + '.sh'))}
if registry:
    lines = ['# Hooks run by _dispatch.sh - generated by install.sh, do not edit.',
             '# EVENT MATCHER NAME TIMEOUT']
    lines += ['%s %s %s %d' % (ev, matcher, n, t) for n, (ev, matcher, t) in sorted(registry.items(), key=lambda i: (i[1][0], i[0]))]
    with open(registry_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
elif os.path.exists(registry_path):
    os.remove(registry_path)

events = sorted({ev for ev, _, _ in registry.values()} | set(hooks_cfg) | {'PreToolUse', 'PostToolUse'})
for event in events:
    members = [(matcher, t) for ev, matcher, t in registry.values() if ev == event]
    entry = None
    if members:
        tools = sorted({tool for matcher, _ in members for tool in matcher.split('|')})
        entry = {'matcher': '|'.join(tools),
                 'hooks': [{'type': 'command',
                            'command': (COMMAND % '_dispatch.sh') + ' ' + event,
                            'timeout': max(t for _, t in members)}]}
    action = set_entry(script_rx('_dispatch.sh', event), event, entry)
    if entry:
        print('  [%s] Dispatcher %s: %d hook(s), matcher %s' % ('SKIP' if action == 'SKIP' else 'OK', event, len(members), entry['matcher']))
    elif action == 'REMOVED':
        print('  [OK] Dispatcher %s removed (no hook left)' % event)

# --- Write settings.json only when something changed (atomic replace) ---
if json.dumps(settings, sort_keys=True) != before or not os.path.exists(settings_path):
    tmp_path = settings_path + '.tmp'
    with open(tmp_path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write('\n')
    os.replace(tmp_path, settings_path)

print('')
print('=== Done: %d hook(s) installed ===' % len(selected))
PYEOF

echo ""
echo "Next steps:"
echo "  1. Edit config files in $TARGET_DIR/.claude/hooks/"
echo "  2. Restart Claude Code for hooks to take effect"
echo ""
