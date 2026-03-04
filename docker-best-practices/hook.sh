#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Docker Best Practices
# =============================================================================
# After modifying a Dockerfile, checks for common anti-patterns:
# - Using :latest tag
# - Running as root
# - No .dockerignore
# - apt-get without --no-install-recommends
# - No multi-stage build for large images
# - COPY before dependency install
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

# Only check Dockerfiles
BASENAME=$(basename "$FILE_PATH")
if ! echo "$BASENAME" | grep -qiE '^Dockerfile'; then
  exit 0
fi

WARNINGS=$(python3 -c "
import re, sys, os

file_path = sys.argv[1]
warnings = []

try:
    with open(file_path, 'r') as f:
        content = f.read()
        lines = content.split('\n')
except:
    sys.exit(0)

# Check for :latest tag
for line in lines:
    if re.match(r'^\s*FROM\s+\S+:latest', line, re.IGNORECASE):
        warnings.append('Using :latest tag (pin a specific version)')
    elif re.match(r'^\s*FROM\s+\S+\s*$', line, re.IGNORECASE):
        if not re.search(r':', line.split()[-1]) and 'scratch' not in line.lower():
            warnings.append('No tag specified on FROM (defaults to :latest)')

# Check for root user
has_user = any(re.match(r'^\s*USER\s+', line) for line in lines)
if not has_user:
    warnings.append('No USER directive (runs as root)')

# Check apt-get without --no-install-recommends
for line in lines:
    if 'apt-get install' in line and '--no-install-recommends' not in line:
        warnings.append('apt-get install without --no-install-recommends')
        break

# Check apt-get without rm cache
has_apt = any('apt-get install' in line for line in lines)
if has_apt:
    has_cleanup = any('rm -rf /var/lib/apt/lists' in line for line in lines)
    if not has_cleanup:
        warnings.append('apt-get without cleaning /var/lib/apt/lists/*')

# Check for COPY . . before dependency install
copy_all_line = -1
dep_install_line = -1
for i, line in enumerate(lines):
    if re.match(r'^\s*COPY\s+\.\s+\.', line):
        copy_all_line = i
    if re.search(r'(npm install|pip install|go mod download|dotnet restore|composer install)', line):
        dep_install_line = i

if copy_all_line >= 0 and dep_install_line >= 0 and copy_all_line < dep_install_line:
    warnings.append('COPY . . before dependency install (breaks cache)')

# Check for .dockerignore
dockerfile_dir = os.path.dirname(file_path)
if not os.path.isfile(os.path.join(dockerfile_dir, '.dockerignore')):
    warnings.append('No .dockerignore file found')

# Check for ADD instead of COPY
for line in lines:
    if re.match(r'^\s*ADD\s+', line) and 'http' not in line.lower() and '.tar' not in line.lower():
        warnings.append('Using ADD instead of COPY (use COPY for local files)')
        break

if warnings:
    print('; '.join(warnings[:4]))
else:
    print('')
" "$FILE_PATH" 2>/dev/null)

if [ -n "$WARNINGS" ]; then
  SAFE_WARNINGS=$(echo "$WARNINGS" | cut -c1-300 | sed 's/"/\\"/g')
  python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'notification': 'DOCKERFILE: ${SAFE_WARNINGS}'
    }
}
print(json.dumps(result))
"
fi

exit 0
