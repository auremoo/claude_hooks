#!/bin/bash
# claude_hooks — Auteur : Aurélien Moote - Moo - 2026 — Licence MIT
# =============================================================================
# Claude Code Hooks - Dispatcher
# =============================================================================
# Usage (from .claude/settings.json):  bash _dispatch.sh PreToolUse|PostToolUse
#
# One process per tool call instead of one per hook: the hook JSON is read
# once, then every installed hook matching the tool runs INSIDE this process,
# one after the other (no fork: on Windows a fork costs almost as much as
# starting bash). The python analyses requested by the hooks are queued and
# executed at the end by one single python process. The answers are then
# merged into the single JSON document Claude Code expects:
#   - PreToolUse : deny wins over ask; the reasons of the winning decision are joined
#   - PostToolUse: warnings are concatenated
#
# The hooks to run are listed in _hooks.conf (written by install.sh), one per
# line: EVENT MATCHER NAME TIMEOUT. Each hook stays a standalone script: it can
# still be run on its own, or registered individually (install.sh --standalone).
#
# Debug: CLAUDE_HOOKS_ONLY=<hook-name> restricts the dispatcher to one hook.
# =============================================================================

EVENT=${1:-}

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
DISPATCH_DIR=$HOOK_DIR
. "$DISPATCH_DIR/_common.sh" || exit 1

REGISTRY="$DISPATCH_DIR/_hooks.conf"
json_str tool_name && [ -n "$REPLY" ] && [ -f "$REGISTRY" ] || exit 0
TOOL=$REPLY

# --- Hooks registered for this event whose matcher contains the tool ---
SELECTED=()
while read -r ev matcher name _ || [ -n "$ev" ]; do
  [ "$ev" = "$EVENT" ] || continue
  name=${name%$'\r'}
  case "|$matcher|" in *"|$TOOL|"*) ;; *) continue ;; esac
  [ -n "${CLAUDE_HOOKS_ONLY:-}" ] && [ "$CLAUDE_HOOKS_ONLY" != "$name" ] && continue
  [ -f "$DISPATCH_DIR/$name.sh" ] && SELECTED+=("$name")
done < "$REGISTRY"

(( ${#SELECTED[@]} )) || exit 0

# A single hook: run it in this very process, its output is the answer
if (( ${#SELECTED[@]} == 1 )); then
  . "$DISPATCH_DIR/${SELECTED[0]}.sh"
  exit 0
fi

# --- Run the hooks in this process; each answers with at most one JSON line ---
# Hooks keep their variables local and never call `exit` (see _common.sh), so
# sourcing them in sequence is safe. Their answers accumulate in _HOOK_OUT and
# the python analyses they request are queued, then run together.
_HOOKS_IN_DISPATCHER=1
_HOOK_OUT=""
_PY_CODE=(); _PY_ARGS=()
for _hook in "${SELECTED[@]}"; do
  . "$DISPATCH_DIR/$_hook.sh"
  shopt -u nocasematch
done
OUT=$_HOOK_OUT
if (( ${#_PY_CODE[@]} )); then
  OUT+=$(run_py_queue)
fi
[ -n "$OUT" ] || exit 0

# --- Merge the answers ---
# raw_field LINE KEY -> REPLY = string value, still JSON-escaped
raw_field() {
  local re="\"$2$_JSON_STR_TAIL"
  [[ $1 =~ $re ]] || return 1
  REPLY=${BASH_REMATCH[1]}
}

DENY_REASONS=""; ASK_REASONS=""; CONTEXT=""; SYSMSG=""
while IFS= read -r line; do
  line=${line%$'\r'}
  [ -n "$line" ] || continue
  if raw_field "$line" permissionDecision; then
    decision=$REPLY
    raw_field "$line" permissionDecisionReason || REPLY=""
    case "$decision" in
      deny) DENY_REASONS+=${DENY_REASONS:+' | '}$REPLY ;;
      ask)  ASK_REASONS+=${ASK_REASONS:+' | '}$REPLY ;;
    esac
  fi
  raw_field "$line" additionalContext && CONTEXT+=${CONTEXT:+'\n'}$REPLY
  raw_field "$line" systemMessage     && SYSMSG+=${SYSMSG:+'\n'}$REPLY
done <<<"$OUT"

JSON=""
[ -n "$SYSMSG" ] && JSON="\"systemMessage\":\"$SYSMSG\""
SPECIFIC=""
if [ -n "$DENY_REASONS" ]; then
  SPECIFIC="\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$DENY_REASONS\""
elif [ -n "$ASK_REASONS" ]; then
  SPECIFIC="\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"$ASK_REASONS\""
elif [ -n "$CONTEXT" ]; then
  SPECIFIC="\"additionalContext\":\"$CONTEXT\""
fi
[ -n "$SPECIFIC" ] && JSON+="${JSON:+,}\"hookSpecificOutput\":{\"hookEventName\":\"$EVENT\",$SPECIFIC}"

[ -n "$JSON" ] && printf '{%s}\n' "$JSON"
exit 0
