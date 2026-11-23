#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Docker Best Practices
# =============================================================================
# After modifying a Dockerfile, checks for common anti-patterns:
# - Using :latest tag
# - Running as root
# - No .dockerignore
# - apt-get without --no-install-recommends
# - apt cache not cleaned
# - COPY before dependency install
# - ADD instead of COPY
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PYCODE REPLY

  get_file_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # Only check Dockerfiles
  shopt -s nocasematch
  [[ ${FILE_PATH##*/} == dockerfile* ]] || return 0
  shopt -u nocasematch

  IFS= read -r -d '' PYCODE <<'PYEOF'
import os

text = read_file(PATH)
if text is None:
    sys.exit(0)
lines = text.split('\n')
warnings = []

# :latest tag
for line in lines:
    if re.match(r'^\s*FROM\s+\S+:latest', line, re.I):
        warnings.append('Using :latest tag (pin a specific version)')
    elif re.match(r'^\s*FROM\s+\S+\s*$', line, re.I):
        if ':' not in line.split()[-1] and 'scratch' not in line.lower():
            warnings.append('No tag specified on FROM (defaults to :latest)')

# Root user
if not any(re.match(r'^\s*USER\s+', line) for line in lines):
    warnings.append('No USER directive (runs as root)')

# apt-get without --no-install-recommends / without cache cleanup
apt_lines = [line for line in lines if 'apt-get install' in line]
if any('--no-install-recommends' not in line for line in apt_lines):
    warnings.append('apt-get install without --no-install-recommends')
if apt_lines and not any('rm -rf /var/lib/apt/lists' in line for line in lines):
    warnings.append('apt-get without cleaning /var/lib/apt/lists/*')

# COPY . . before dependency install
copy_all_line = dep_install_line = -1
for i, line in enumerate(lines):
    if re.match(r'^\s*COPY\s+\.\s+\.', line):
        copy_all_line = i
    if re.search(r'(npm install|pip install|go mod download|dotnet restore|composer install)', line):
        dep_install_line = i
if 0 <= copy_all_line < dep_install_line:
    warnings.append('COPY . . before dependency install (breaks cache)')

# .dockerignore
if not os.path.isfile(os.path.join(os.path.dirname(PATH), '.dockerignore')):
    warnings.append('No .dockerignore file found')

# ADD instead of COPY
for line in lines:
    if re.match(r'^\s*ADD\s+', line) and 'http' not in line.lower() and '.tar' not in line.lower():
        warnings.append('Using ADD instead of COPY (use COPY for local files)')
        break

if warnings:
    notify('DOCKERFILE: ' + '; '.join(warnings[:4])[:300])
PYEOF

  run_py "$PYCODE"
  return 0
}

main
