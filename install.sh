#!/bin/bash
# =============================================================================
# Claude Code Hooks - Installer
# =============================================================================
# Usage:
#   bash install.sh /path/to/project                 # install ALL hooks
#   bash install.sh /path/to/project check-sensitive  # install one hook
#   bash install.sh                                   # install all in cwd
#
# Auto-discovers hooks from subdirectories via hook.json metadata.
# Idempotent: safe to re-run (won't duplicate or overwrite user configs).
# Requires: bash, python3
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:-.}"
HOOK_FILTER="${2:-}"   # optional: install only this hook

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

CLAUDE_DIR="$TARGET_DIR/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "=== Claude Code Hooks Installer ==="
echo "Source:  $SCRIPT_DIR"
echo "Target:  $TARGET_DIR"
echo ""

# --- Discover hooks ---
INSTALLED=0

for HOOK_META in "$SCRIPT_DIR"/*/hook.json; do
  [ -f "$HOOK_META" ] || continue

  HOOK_DIR="$(dirname "$HOOK_META")"
  HOOK_NAME="$(basename "$HOOK_DIR")"

  # Filter if user specified a specific hook
  if [ -n "$HOOK_FILTER" ] && [ "$HOOK_NAME" != "$HOOK_FILTER" ]; then
    continue
  fi

  echo "--- Hook: $HOOK_NAME ---"

  # Read metadata via python3
  HOOK_INFO=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
print(m.get('event', 'PreToolUse'))
print(m.get('matcher', ''))
print(m.get('timeout', 5))
print(m.get('description', ''))
# files is a JSON list
print(json.dumps(m.get('files', [])))
" "$HOOK_META" 2>/dev/null)

  EVENT=$(echo "$HOOK_INFO" | sed -n '1p')
  MATCHER=$(echo "$HOOK_INFO" | sed -n '2p')
  TIMEOUT=$(echo "$HOOK_INFO" | sed -n '3p')
  DESCRIPTION=$(echo "$HOOK_INFO" | sed -n '4p')
  FILES_JSON=$(echo "$HOOK_INFO" | sed -n '5p')

  echo "  $DESCRIPTION"
  echo "  Event: $EVENT | Matcher: $MATCHER | Timeout: ${TIMEOUT}s"

  # Create target directory for this hook
  mkdir -p "$HOOKS_DIR"

  # Copy hook files (main script = hook.sh -> <hook-name>.sh)
  MAIN_SCRIPT=""
  python3 -c "
import json, sys, shutil, os, stat

hook_dir = sys.argv[1]
hooks_dir = sys.argv[2]
hook_name = sys.argv[3]
files = json.loads(sys.argv[4])

for f in files:
    src = os.path.join(hook_dir, f)
    if f == 'hook.sh':
        dst = os.path.join(hooks_dir, hook_name + '.sh')
        print('MAIN:' + hook_name + '.sh')
    else:
        dst = os.path.join(hooks_dir, f)

    if f != 'hook.sh' and os.path.exists(dst):
        print('SKIP:' + f + ' (already exists)')
        continue

    shutil.copy2(src, dst)
    if f == 'hook.sh':
        os.chmod(dst, os.stat(dst).st_mode | stat.S_IEXEC)
    print('COPY:' + os.path.basename(dst))
" "$HOOK_DIR" "$HOOKS_DIR" "$HOOK_NAME" "$FILES_JSON" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      MAIN:*) echo "  [OK] ${line#MAIN:} (main script)" ;;
      COPY:*) echo "  [OK] Copied ${line#COPY:}" ;;
      SKIP:*) echo "  [SKIP] ${line#SKIP:}" ;;
    esac
  done

  MAIN_SCRIPT="$HOOK_NAME.sh"

  # Build settings.json entry for this hook
  HOOK_ENTRY=$(python3 -c "
import json
entry = {
    'matcher': '$MATCHER',
    'hooks': [{
        'type': 'command',
        'command': 'bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/$MAIN_SCRIPT\"',
        'timeout': int('$TIMEOUT')
    }]
}
print(json.dumps(entry))
" 2>/dev/null)

  # Create or update settings.json
  python3 -c "
import json, sys, os

settings_path = sys.argv[1]
event = sys.argv[2]
new_entry = json.loads(sys.argv[3])
hook_name = sys.argv[4]

# Load or create settings
if os.path.exists(settings_path):
    with open(settings_path, 'r') as f:
        settings = json.load(f)
else:
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

if event not in settings['hooks']:
    settings['hooks'][event] = [new_entry]
    action = 'ADDED'
else:
    # Check if this hook is already registered
    existing_commands = []
    for h in settings['hooks'][event]:
        for sub in h.get('hooks', []):
            existing_commands.append(sub.get('command', ''))

    if any(hook_name in cmd for cmd in existing_commands):
        action = 'SKIP'
    else:
        settings['hooks'][event].append(new_entry)
        action = 'ADDED'

if action == 'ADDED':
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('[OK] settings.json updated (' + event + ': ' + hook_name + ')')
else:
    print('[SKIP] Already in settings.json')
" "$SETTINGS_FILE" "$EVENT" "$HOOK_ENTRY" "$HOOK_NAME" 2>&1 | sed 's/^/  /'

  INSTALLED=$((INSTALLED + 1))
  echo ""
done

if [ -n "$HOOK_FILTER" ] && [ "$INSTALLED" -eq 0 ]; then
  echo "[ERROR] Hook '$HOOK_FILTER' not found in $SCRIPT_DIR/"
  echo "Available hooks:"
  for d in "$SCRIPT_DIR"/*/hook.json; do
    [ -f "$d" ] && echo "  - $(basename "$(dirname "$d")")"
  done
  exit 1
fi

echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Edit config files in $HOOKS_DIR/"
echo "  2. Restart Claude Code for hooks to take effect"
echo ""
