#!/bin/bash
# =============================================================================
# Claude Code PreToolUse Hook - File Scope Guard
# =============================================================================
# Restricts Claude to only access files within allowed directories.
# Blocks access to sensitive system paths (SSH keys, credentials, etc.).
#
# Paths are compared in a canonical form (forward slashes, "." and ".."
# resolved, /c/dir and C:\dir unified, case-insensitive on Windows), so
# C:\Users\me\.ssh, /c/Users/me/.ssh and project/../../.ssh are all recognised.
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local ALLOWED_FILE BASE_DIR BLOCKED BLOCKED_PATHS CONFIGURED FILE_PATH HOME_DIR ORIGINAL_PATH
  local PROJECT_DIR REPLY TARGET line

  # canon PATH -> REPLY (absolute, normalised, no trailing slash)
  canon() {
    local p=$1 seg out="" root="/"
    local -a stack=()
    [[ $p == "~" || $p == "~/"* || $p == "~\\"* ]] && p=$HOME${p:1}
    norm_path "$p"; p=$REPLY
    if (( IS_WIN )) && [[ $p =~ ^/([A-Za-z])(/.*)?$ ]]; then
      p="${BASH_REMATCH[1]}:${BASH_REMATCH[2]:-/}"                                     # /c/dir -> c:/dir
    fi
    if [[ $p =~ ^([A-Za-z]:)/?(.*)$ ]]; then
      root="${BASH_REMATCH[1]}/"; p=${BASH_REMATCH[2]}
    elif [[ $p != /* ]]; then
      canon "$BASE_DIR/$p"; return
    fi
    # Resolve "." and ".." segment by segment (in memory: no process, no temp file)
    p=$p/
    while [ -n "$p" ]; do
      seg=${p%%/*}; p=${p#*/}
      case "$seg" in
        ''|.) ;;
        ..)   (( ${#stack[@]} )) && unset "stack[${#stack[@]}-1]" ;;
        *)    stack+=("$seg") ;;
      esac
    done
    for seg in "${stack[@]}"; do out+="/$seg"; done
    REPLY="${root%/}$out"
    [ -n "$REPLY" ] || REPLY=/
  }

  # Relative paths are resolved against the working directory reported by Claude Code
  json_str cwd && [[ $REPLY == /* || $REPLY =~ ^[A-Za-z]:[\\/] ]] && BASE_DIR=$REPLY || BASE_DIR=$PWD

  # Target: file_path (Read/Write/Edit), path (Grep/Glob), or an absolute Glob pattern
  if ! get_file_path or_path; then
    json_str pattern || return 0
    [[ $REPLY == /* || $REPLY == "~"* || $REPLY =~ ^[A-Za-z]:[\\/] ]] || return 0
    FILE_PATH=${REPLY%%[*?[]*}
  fi
  ORIGINAL_PATH=$FILE_PATH
  canon "$FILE_PATH"; TARGET=$REPLY

  # Windows file systems are case-insensitive: compare paths accordingly
  (( IS_WIN )) && shopt -s nocasematch

  # --- Always-blocked paths (sensitive system files) ---
  canon "$HOME"; HOME_DIR=$REPLY
  BLOCKED_PATHS=(
    "$HOME_DIR/.ssh"
    "$HOME_DIR/.gnupg"
    "$HOME_DIR/.aws"
    "$HOME_DIR/.config/gh"
    "$HOME_DIR/.env"
    "/etc/shadow"
    "/etc/passwd"
    "/etc/sudoers"
  )

  for BLOCKED in "${BLOCKED_PATHS[@]}"; do
    if [[ $TARGET == "$BLOCKED"* ]]; then
      emit_pre deny "FILE SCOPE GUARD: access to ${ORIGINAL_PATH} is BLOCKED (sensitive system path)."
      return 0
    fi
  done

  # --- Load allowed paths ---
  ALLOWED_FILE="$HOOK_DIR/allowed_paths.txt"
  [ -f "$ALLOWED_FILE" ] || return 0

  get_project_dir

  # If no allowed paths are configured, allow everything (except blocked above)
  CONFIGURED=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    CONFIGURED=1
    canon "${line//\$PROJECT_DIR/$PROJECT_DIR}"
    # Allowed when equal to, or located under, an allowed directory
    if [[ $TARGET == "$REPLY" || $TARGET == "${REPLY%/}"/* ]]; then
      return 0
    fi
  done < "$ALLOWED_FILE"

  (( CONFIGURED )) || return 0

  # File is outside allowed scope
  emit_pre ask "FILE SCOPE GUARD: ${ORIGINAL_PATH} is outside allowed project scope. Confirm access?"
  return 0
}

main
