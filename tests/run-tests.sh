#!/bin/bash
# claude_hooks — Auteur : Aurélien Moote - Moo - 2026 — Licence MIT
# =============================================================================
# Claude Code Hooks - Test suite
# =============================================================================
# Usage:
#   bash tests/run-tests.sh              # test the hooks of this repository
#   bash tests/run-tests.sh -v           # verbose (show hook output on failure)
#   bash tests/run-tests.sh --standalone # run each hook script directly
#   bash tests/run-tests.sh /other/dir   # test another copy of the repository
#
# Installs every hook into a throw-away git sandbox with install.sh, then feeds
# each hook the JSON Claude Code would send on stdin and checks the decision.
# By default every hook is exercised through the dispatcher (_dispatch.sh), as
# in a real installation; --standalone runs the hook scripts on their own.
# Requires: bash, git, python3 (same as the hooks themselves).
# =============================================================================

VERBOSE=0
STANDALONE=0
ROOT=""
for arg in "$@"; do
  case "$arg" in
    -v)           VERBOSE=1 ;;
    --standalone) STANDALONE=1 ;;
    *)            ROOT="$arg" ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$ROOT" && pwd)"

SANDBOX="$(mktemp -d 2>/dev/null || mktemp -d -t claude-hooks)"
OUTSIDE="$(mktemp -d 2>/dev/null || mktemp -d -t claude-hooks-out)"
trap 'rm -rf "$SANDBOX" "$OUTSIDE"' EXIT

# Claude Code sends native paths (backslashes on Windows)
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
case "$(native /tmp)" in *\\*) SEP='\' ;; *) SEP='/' ;; esac
NSANDBOX="$(native "$SANDBOX")"
NOUTSIDE="$(native "$OUTSIDE")"
NHOME="$(native "$HOME")"

PASS=0; FAIL=0; FAILED=()
SESSION="sess-1"
EVENT="PreToolUse"
OUT=""; ERR=""; JSON=""
ALL_OUT="$OUTSIDE/all-outputs.jsonl"; : > "$ALL_OUT"

# --- JSON input builders -----------------------------------------------------
jesc() {
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
  REPLY=$s
}
envelope() { # tool_name tool_input_json
  local extra=""
  [ "$EVENT" = "PostToolUse" ] && extra=',"tool_response":{"filePath":"x","success":true}'
  jesc "$NSANDBOX"
  JSON="{\"session_id\":\"$SESSION\",\"transcript_path\":\"$REPLY${SEP}${SEP}t.jsonl\",\"cwd\":\"$REPLY\",\"permission_mode\":\"default\",\"hook_event_name\":\"$EVENT\",\"tool_name\":\"$1\",\"tool_input\":$2,\"tool_use_id\":\"toolu_01\"$extra}"
}
p() { printf '%s' "$NSANDBOX$SEP${1//\//$SEP}"; }          # sandbox-relative -> native absolute
j_bash()  { jesc "$1"; envelope Bash "{\"command\":\"$REPLY\",\"description\":\"test\"}"; }
j_read()  { jesc "$1"; envelope Read "{\"file_path\":\"$REPLY\"${2:+,\"limit\":$2}}"; }
j_write() { local f; jesc "$1"; f=$REPLY; jesc "$2"; envelope Write "{\"file_path\":\"$f\",\"content\":\"$REPLY\"}"; }
j_edit()  { local f o; jesc "$1"; f=$REPLY; jesc "$2"; o=$REPLY; jesc "$3"; envelope Edit "{\"file_path\":\"$f\",\"old_string\":\"$o\",\"new_string\":\"$REPLY\",\"replace_all\":false}"; }
j_grep()  { local q mode=${3:+,\"output_mode\":\"$3\"}; jesc "$1"; q=$REPLY; if [ -n "$2" ]; then jesc "$2"; envelope Grep "{\"pattern\":\"$q\",\"path\":\"$REPLY\"$mode}"; else envelope Grep "{\"pattern\":\"$q\"$mode}"; fi; }
j_glob()  { local q; jesc "$1"; q=$REPLY; if [ -n "$2" ]; then jesc "$2"; envelope Glob "{\"pattern\":\"$q\",\"path\":\"$REPLY\"}"; else envelope Glob "{\"pattern\":\"$q\"}"; fi; }

mkfile() { mkdir -p "$SANDBOX/$(dirname "$1")"; printf '%s\n' "$2" > "$SANDBOX/$1"; }

# --- Runner ------------------------------------------------------------------
run() { # hook_name  (uses $JSON)
  HOOK=$1
  if [ "$STANDALONE" = 0 ] && grep -qE " $HOOK( |\$)" "$SANDBOX/.claude/hooks/_hooks.conf" 2>/dev/null; then
    # Through the dispatcher, restricted to this hook
    OUT=$(cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$NSANDBOX" CLAUDE_HOOKS_ONLY="$HOOK" bash ".claude/hooks/_dispatch.sh" "$EVENT" <<<"$JSON" 2>"$OUTSIDE/stderr")
  else
    OUT=$(cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$NSANDBOX" bash ".claude/hooks/$HOOK.sh" <<<"$JSON" 2>"$OUTSIDE/stderr")
  fi
  ERR=$(<"$OUTSIDE/stderr")
  [ -n "$OUT" ] && printf '%s\n' "$OUT" >> "$ALL_OUT"
}
dispatch() { # event  (uses $JSON) -> every hook registered for the tool, as Claude Code runs them
  HOOK="dispatcher"
  OUT=$(cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$NSANDBOX" bash ".claude/hooks/_dispatch.sh" "$1" <<<"$JSON" 2>"$OUTSIDE/stderr")
  ERR=$(<"$OUTSIDE/stderr")
  [ -n "$OUT" ] && printf '%s\n' "$OUT" >> "$ALL_OUT"
}
ok()   { PASS=$((PASS+1)); [ "$VERBOSE" = 1 ] && printf '  ok    %-26s %s\n' "$HOOK" "$1"; return 0; }
fail() { FAIL=$((FAIL+1)); FAILED+=("$HOOK: $1"); printf '  FAIL  %-26s %s\n' "$HOOK" "$1"
         [ "$VERBOSE" = 1 ] && { printf '        out: %s\n' "${OUT:0:300}"; [ -n "$ERR" ] && printf '        err: %s\n' "${ERR:0:300}"; }; return 0; }
# expect KIND DESCRIPTION [REGEX]   KIND = none | ask | deny | msg
expect() {
  local kind=$1 desc=$2 re=$3 good=0
  case "$kind" in
    none) [ -z "$OUT" ] && good=1 ;;
    ask)  [[ $OUT =~ \"permissionDecision\":\ ?\"ask\" ]] && good=1 ;;
    deny) [[ $OUT =~ \"permissionDecision\":\ ?\"deny\" ]] && good=1 ;;
    msg)  [[ $OUT == *'"additionalContext"'* ]] && good=1 ;;
  esac
  if [ "$good" = 1 ] && [ -n "$re" ]; then [[ $OUT =~ $re ]] || good=0; fi
  if [ "$good" = 1 ] && [ -n "$ERR" ]; then good=0; desc="$desc (unexpected stderr)"; fi
  if [ "$good" = 1 ]; then ok "$desc"; else fail "$desc [expected $kind${re:+ ~ $re}]"; fi
}
check() { # DESCRIPTION  command...   (arbitrary assertion)
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}
has() { grep -qE -e "$2" "$SANDBOX/$1"; }
hasnt() { ! grep -qE -e "$2" "$SANDBOX/$1"; }

# =============================================================================
echo "=== Installing hooks from $ROOT into sandbox ==="
( cd "$SANDBOX" && git init -q . && git config user.email t@example.com && git config user.name tester \
  && git config core.autocrlf false && git checkout -q -b main 2>/dev/null
  printf '.claude/\nnode_modules/\n' > .gitignore
  mkdir -p .claude && printf '{\n  "permissions": {"allow": ["Bash(ls:*)"]}\n}\n' > .claude/settings.json
  git add .gitignore && git commit -q -m "chore: init" )
T0=$(date +%s)
INSTALL_LOG=$(bash "$ROOT/install.sh" "$SANDBOX" 2>&1); INSTALL_RC=$?
T1=$(date +%s)
echo "    install.sh: rc=$INSTALL_RC, $((T1-T0))s"
HOOK=install
check "install.sh exits 0" [ "$INSTALL_RC" = 0 ]
count_cmds() { grep -c "\\.claude/hooks/$2" "$1/.claude/settings.json"; }
N_HOOKS=$(ls -d "$ROOT"/*/hook.json | wc -l | tr -d ' ')
N_ASYNC=$(grep -l '"async": *true' "$ROOT"/*/hook.json | wc -l | tr -d ' ')
N_SCRIPTS=$(ls "$SANDBOX/.claude/hooks/" | grep -c '^[a-z].*\.sh$')
N_REGISTRY=$(grep -c '^P' "$SANDBOX/.claude/hooks/_hooks.conf")
check "all $N_HOOKS hook scripts copied (got $N_SCRIPTS)" [ "$N_HOOKS" = "$N_SCRIPTS" ]
check "blocking hooks listed in _hooks.conf (got $N_REGISTRY)" [ "$N_REGISTRY" = $((N_HOOKS - N_ASYNC)) ]
check "one dispatcher entry per event" [ "$(count_cmds "$SANDBOX" '_dispatch\.sh')" = 2 ]
check "async hooks keep their own entry" [ "$(count_cmds "$SANDBOX" '[a-z][a-z-]*\.sh')" = "$N_ASYNC" ]
check "existing settings keys preserved" has .claude/settings.json '"permissions"'
check "config files copied" [ -f "$SANDBOX/.claude/hooks/dangerous_patterns.txt" ]
echo "# user edit" >> "$SANDBOX/.claude/hooks/dangerous_patterns.txt"
cp "$SANDBOX/.claude/settings.json" "$OUTSIDE/settings.before"
bash "$ROOT/install.sh" "$SANDBOX" >/dev/null 2>&1
check "re-install is idempotent (settings.json unchanged)" cmp -s "$SANDBOX/.claude/settings.json" "$OUTSIDE/settings.before"
check "re-install keeps user-edited config" has .claude/hooks/dangerous_patterns.txt '^# user edit'
bash "$ROOT/install.sh" "$SANDBOX" no-such-hook >/dev/null 2>&1
check "unknown hook name fails" [ $? -ne 0 ]

# Switching between dispatcher and standalone registration (second project)
P2="$OUTSIDE/proj2"; mkdir -p "$P2"
bash "$ROOT/install.sh" --standalone "$P2" >/dev/null 2>&1
check "--standalone: one entry per hook" [ "$(count_cmds "$P2" '[a-z][a-z-]*\.sh')" = "$N_HOOKS" ]
check "--standalone: no dispatcher entry, no registry" [ "$(count_cmds "$P2" '_dispatch\.sh')" = 0 -a ! -e "$P2/.claude/hooks/_hooks.conf" ]
bash "$ROOT/install.sh" "$P2" >/dev/null 2>&1
check "back to dispatcher: per-hook entries removed" [ "$(count_cmds "$P2" '[a-z][a-z-]*\.sh')" = "$N_ASYNC" -a "$(count_cmds "$P2" '_dispatch\.sh')" = 2 ]
check "same hooks section as a fresh dispatcher install" python3 -c "
import json, sys
a, b = (json.load(open(p, encoding='utf-8'))['hooks'] for p in sys.argv[1:3])
sys.exit(a != b)" "$P2/.claude/settings.json" "$SANDBOX/.claude/settings.json"
bash "$ROOT/install.sh" --standalone "$P2" check-sensitive >/dev/null 2>&1
check "mixed mode: one hook standalone, others dispatched" [ "$(count_cmds "$P2" 'check-sensitive\.sh')" = 1 -a "$(grep -c 'check-sensitive' "$P2/.claude/hooks/_hooks.conf")" = 0 -a "$(count_cmds "$P2" '_dispatch\.sh')" = 2 ]

# Project-specific sensitive patterns (the shipped file is all comments)
printf '%s\n' 'ACME-Corp' '10\.135\.' >> "$SANDBOX/.claude/hooks/sensitive_patterns.txt"

echo "=== Running hook tests ==="

# ----------------------------------------------------------------------------- dangerous-command-guard
EVENT=PreToolUse
j_bash 'git push --force origin main';            run dangerous-command-guard; expect ask  "git push --force"
j_bash 'ls -la';                                  run dangerous-command-guard; expect none "harmless command"
j_bash 'rm -rf build/';                           run dangerous-command-guard; expect ask  "rm -rf"
j_bash "rm -rf 'my dir'";                         run dangerous-command-guard; expect ask  "command containing single quotes"
j_bash 'rm -rf "C:\Users\x\new"';                 run dangerous-command-guard; expect ask  "command containing backslashes/double quotes"
j_bash $'echo start\ngit reset --hard HEAD~1';    run dangerous-command-guard; expect ask  "multi-line command"
j_bash ':(){ :|:& };:';                           run dangerous-command-guard; expect ask  "fork bomb"
BIG=$(printf 'x%.0s' $(seq 1 40000))
j_bash "cat > f.txt <<'EOF'"$'\n'"$BIG"$'\nEOF\ngit clean -fd';  run dangerous-command-guard; expect ask "40 KB command (heredoc)"
# The hook skips grep when bash can prove there is no match: the verdict must
# stay exactly the one of `grep -iE` on the patterns file, for every command.
REF_REGEX=$(grep -v '^#' "$SANDBOX/.claude/hooks/dangerous_patterns.txt" | tr -d '\r' | grep -v '^[[:space:]]*$' | paste -sd'|' -)
while IFS= read -r CMD; do
  [ -n "$CMD" ] || continue
  if grep -qiE -e "$REF_REGEX" <<<"$CMD"; then WANT=ask; else WANT=none; fi
  j_bash "$CMD"; run dangerous-command-guard; expect "$WANT" "same verdict as grep -iE ($WANT): $CMD"
done <<'CORPUS'
rm -f a.txt
RM -RF /tmp/x
rmdir --ignore-fail-on-non-empty d
shred  -u secret.key
git push origin main -f
git push -fx
git push --force-with-lease
git reset --hard
git clean -n
git clean  -xfd
git checkout -- .
git checkout -b feature
git branch -D old
git branch -d old
git rebase main --force
psql -c "DROP TABLE users"
psql -c "delete from users ;"
psql -c "DELETE FROM users WHERE id = 1"
psql -c "ALTER TABLE t DROP COLUMN c"
psql -c "truncate table t"
mkfs.ext4 /dev/sdb1
dd if=/dev/zero of=/dev/sda
dd if=a of=b
format c:
chmod -R 777 .
chmod 755 run.sh
chown -R www-data .
docker system prune -af
docker rm -f web
docker ps
kubectl delete pod web
kubectl get pods
terraform destroy
npm -g uninstall typescript
npm install
pip uninstall requests -y
apt-get remove nginx -y
kill -9 1234
kill 1234
killall node
pkill -f server
echo data > /dev/sdb
echo 127.0.0.1 x > /etc/hosts
cat /etc/hosts
grep -r "format" src
echo "informational message"
ls -la && pwd
node --version
git status; git log --oneline -5
tar -xzf archive.tgz
CORPUS

# ----------------------------------------------------------------------------- check-sensitive
mkfile docs/client.txt  "Contract with ACME-Corp signed."
mkfile docs/quote.txt   "it's for ACME-Corp \"prod\" at 10.135.4.2"
mkfile docs/clean.txt   "nothing to see"
mkfile "my dir/site plan.txt" "plant network 10.135.9.9"
j_read "$(p docs/client.txt)";          run check-sensitive; expect ask  "file with client name" 'SENSITIVE DATA'
j_read "$(p docs/quote.txt)";           run check-sensitive; expect ask  "matching line containing quotes"
j_read "$(p docs/clean.txt)";           run check-sensitive; expect none "clean file"
j_read "$(p "my dir/site plan.txt")";   run check-sensitive; expect ask  "path with spaces"
j_read "$SANDBOX/docs/client.txt";      run check-sensitive; expect ask  "forward-slash path"
j_grep 'ACME' "$(p docs/client.txt)";   run check-sensitive; expect ask  "Grep on a single file"
j_read "$(p docs/missing.txt)";         run check-sensitive; expect none "missing file"
j_grep 'Contract' "$(p docs)" content;  run check-sensitive; expect ask  "Grep content on a directory: a sensitive line would be returned" 'Grep results'
j_grep 'nothing' "$(p docs)" content;   run check-sensitive; expect none "Grep content on a directory: harmless lines only"
j_grep 'ACME' "$(p docs)";              run check-sensitive; expect none "Grep on a directory listing file names only (default mode)"
j_grep '\d+\.\d+' "$(p docs)" content;  run check-sensitive; expect ask  "Grep pattern that grep cannot reproduce: searched files are scanned" 'files searched'
j_grep 'plant' '' content;              run check-sensitive; expect ask  "Grep content without path (whole project)" 'site plan'

# ----------------------------------------------------------------------------- branch-protection
j_bash 'git commit -m "feat: x"';       run branch-protection; expect ask  "commit on main" 'main'
j_bash 'git status';                    run branch-protection; expect none "git status"
j_bash 'git push origin main';          run branch-protection; expect ask  "push on main"
j_bash 'git -c user.name=x commit -m "feat: x"'; run branch-protection; expect ask "git -c ... commit"
( cd "$SANDBOX" && git checkout -q -b feature/x )
j_bash 'git commit -m "feat: x"';       run branch-protection; expect none "commit on feature branch"
j_bash 'git push -u origin feature/x';  run branch-protection; expect none "push feature branch"
j_bash 'git push origin HEAD:main';     run branch-protection; expect ask  "push to protected branch from feature branch"
( cd "$SANDBOX" && git checkout -q main )

# ----------------------------------------------------------------------------- file-scope-guard
mkfile src/a.txt "a"
j_read "$(p src/a.txt)";                               run file-scope-guard; expect none "file inside project"
j_read "src/a.txt";                                    run file-scope-guard; expect none "relative path"
j_read "$(p src/sub)${SEP}..${SEP}a.txt";              run file-scope-guard; expect none "inside project via .."
j_read "$NHOME${SEP}.ssh${SEP}id_rsa";                 run file-scope-guard; expect deny "~/.ssh is blocked"
j_read "$NHOME${SEP}.aws${SEP}credentials";            run file-scope-guard; expect deny "~/.aws is blocked"
j_read "$NOUTSIDE${SEP}x.txt";                         run file-scope-guard; expect ask  "file outside project"
j_read "$(p src)${SEP}..${SEP}..${SEP}other${SEP}x";   run file-scope-guard; expect ask  "path traversal out of project"
j_read "${NSANDBOX}-evil${SEP}x.txt";                  run file-scope-guard; expect ask  "sibling dir sharing the project prefix"
j_glob '**/*.ts';                                      run file-scope-guard; expect none "Glob without path"
j_glob '*.txt' "$NOUTSIDE";                            run file-scope-guard; expect ask  "Glob outside project"
j_grep 'TODO';                                         run file-scope-guard; expect none "Grep without path"

# ----------------------------------------------------------------------------- no-secret-commit
# Fake credentials are assembled at run time: no secret-looking literal is stored
# in this repository (secret scanners would rightly reject it).
FAKE_AWS="AKIA""IOSFODNN7EXAMPLE"
FAKE_GITHUB="ghp""_abcdefghijklmnopqrstuvwxyz0123456789"
FAKE_STRIPE="sk""_live_""abcdefghijklmnopqrstuvwx"
mkfile cfg/aws.txt  "key = $FAKE_AWS"
mkfile cfg/ok.txt   "nothing secret"
( cd "$SANDBOX" && git add cfg/ok.txt )
j_bash 'git commit -m "chore: ok"';     run no-secret-commit; expect none "clean staged file"
( cd "$SANDBOX" && git add cfg/aws.txt )
j_bash 'git commit -m "chore: cfg"';    run no-secret-commit; expect ask  "staged AWS key" 'aws\.txt'
j_bash 'git status';                    run no-secret-commit; expect none "not a commit"
( cd "$SANDBOX" && git reset -q && rm cfg/aws.txt )
mkfile cfg/pw.txt   "password = 'S3cr3t-with-quote'"
( cd "$SANDBOX" && git add cfg/pw.txt )
j_bash 'git commit -m "chore: cfg"';    run no-secret-commit; expect ask  "secret line containing quotes"
( cd "$SANDBOX" && git reset -q && rm cfg/pw.txt )
mkfile cfg/new.txt  "token: $FAKE_GITHUB"
j_bash 'git add cfg/new.txt && git commit -m "chore: cfg"';  run no-secret-commit; expect ask "git add && git commit in one command (untracked file)"
( cd "$SANDBOX" && rm cfg/new.txt && git add cfg/ok.txt && git commit -q -m "chore: ok" )
printf '%s\n' "$FAKE_STRIPE" >> "$SANDBOX/cfg/ok.txt"
j_bash 'git commit -am "chore: cfg"';   run no-secret-commit; expect ask  "git commit -a (unstaged tracked change)"
( cd "$SANDBOX" && git checkout -q -- cfg/ok.txt )
MANY=""; for i in $(seq 1 60); do mkfile "many/f$i.txt" "file $i"; done
( cd "$SANDBOX" && git add many )
S0=$(date +%s); j_bash 'git commit -m "chore: many"'; run no-secret-commit; S1=$(date +%s)
expect none "60 clean staged files"
check "60 staged files scanned in < 5s (took $((S1-S0))s)" [ $((S1-S0)) -lt 5 ]
( cd "$SANDBOX" && git reset -q && rm -rf many )

# ----------------------------------------------------------------------------- auto-backup
mkfile "src/my file.txt" "v1"
j_edit "$(p "src/my file.txt")" v1 v2;  run auto-backup; expect none "silent"
check "backup created (path with spaces)" ls "$SANDBOX/.claude/backups/"*"my file.txt."*.bak
check "backup content is the original" grep -q v1 "$SANDBOX/.claude/backups/"*"my file.txt."*.bak
j_edit "$(p "src/my file.txt")" v1 v2;  run auto-backup
N=$(ls "$SANDBOX/.claude/backups/" | grep -c 'my file')
check "second backup in the same second is kept too (got $N)" [ "$N" = 2 ]
for i in $(seq 10 34); do : > "$SANDBOX/.claude/backups/src_my file.txt.20200101_0000$i.bak"; done
j_edit "$(p "src/my file.txt")" v1 v2;  run auto-backup
N=$(ls "$SANDBOX/.claude/backups/" | grep -c 'my file')
check "old backups pruned to 20 (got $N)" [ "$N" = 20 ]
check "newest backup survives pruning" grep -lq v1 "$SANDBOX/.claude/backups/"*"my file.txt."*.bak
j_write "$(p src/brand-new.txt)" hello; run auto-backup; expect none "new file: nothing to back up"

# ----------------------------------------------------------------------------- large-file-guard
head -c 2200000 /dev/zero | tr '\0' 'a' > "$SANDBOX/big.log"
j_read "$(p big.log)";                  run large-file-guard; expect ask  "2 MB file" 'LARGE FILE'
j_read "$(p src/a.txt)";                run large-file-guard; expect none "small file"

# ----------------------------------------------------------------------------- commit-convention
j_bash 'git commit -m "feat: add login"';           run commit-convention; expect none "valid message"
j_bash 'git commit -m "feat(auth)!: drop v1 API"';  run commit-convention; expect none "breaking-change marker"
j_bash "git commit -m 'chore: bump deps'";          run commit-convention; expect none "single-quoted message"
j_bash 'git commit -m "added some stuff"';          run commit-convention; expect ask  "invalid message" 'added some stuff'
j_bash 'git commit -m "it'"'"'s broken"';            run commit-convention; expect ask  "invalid message with apostrophe"
j_bash 'git commit -am "wip"';                      run commit-convention; expect ask  "-am form"
j_bash 'git commit --amend --no-edit';              run commit-convention; expect none "amend is skipped"
j_bash 'git log --oneline';                         run commit-convention; expect none "not a commit"
HEREDOC_OK='git commit -m "$(cat <<'"'"'EOF'"'"'
fix(parser): handle empty input

Longer body here.

Co-Authored-By: Someone <x@example.com>
EOF
)"'
j_bash "$HEREDOC_OK";                               run commit-convention; expect none "valid heredoc message (Claude Code style)"
HEREDOC_BAD='git commit -m "$(cat <<'"'"'EOF'"'"'
Fixed the parser
EOF
)"'
j_bash "$HEREDOC_BAD";                              run commit-convention; expect ask  "invalid heredoc message" 'Fixed the parser'

# ----------------------------------------------------------------------------- infra-cost-estimator
S0=$(date +%s)
j_bash 'terraform apply -auto-approve';   run infra-cost-estimator; expect ask  "terraform apply" 'TERRAFORM APPLY'
S1=$(date +%s)
check "terraform apply warning is immediate (took $((S1-S0))s)" [ $((S1-S0)) -lt 4 ]
j_bash 'helm upgrade api ./chart';        run infra-cost-estimator; expect ask  "helm upgrade"
j_bash "echo \"don't\" && pulumi up";     run infra-cost-estimator; expect ask  "pulumi up after quotes"
j_bash 'terraform plan';                  run infra-cost-estimator; expect none "terraform plan"

# ----------------------------------------------------------------------------- architecture-boundary
IMPORT_SQ="import { Db } from '../infrastructure/db';"
j_edit "$(p src/domain/user.ts)" x "$IMPORT_SQ";            run architecture-boundary; expect ask  "domain imports infrastructure" 'ARCHITECTURE'
j_edit "$(p src/infrastructure/repo.ts)" x "$IMPORT_SQ";    run architecture-boundary; expect none "infrastructure imports infrastructure"
j_write "$(p src/domain/order.py)" $'# \xe2\x9c\x85 r\xc3\xa8gle \xf0\x9f\x9a\x80\nfrom app.infrastructure.db import Session\n'
run architecture-boundary; expect ask  "content with emoji / accents"
j_edit "$(p src/domain/user.ts)" x 'const total = a + b;';  run architecture-boundary; expect none "no import"
j_edit "$(p README.md)" x "$IMPORT_SQ";                     run architecture-boundary; expect none "file outside any layer"

# ----------------------------------------------------------------------------- import-validator
j_write "$(p src/a.py)" 'x = eval(data)';                              run import-validator; expect ask  "eval()"
j_write "$(p src/a.py)" "os.system('ls')";                             run import-validator; expect ask  "match containing single quotes"
j_write "$(p src/a.py)" 'cfg = yaml.load(f)';                          run import-validator; expect ask  "yaml.load without Loader"
j_write "$(p src/a.py)" 'cfg = yaml.load(f, Loader=yaml.SafeLoader)';  run import-validator; expect none "yaml.load with Loader"
j_write "$(p src/a.py)" $'def add(a, b):\n    return a + b\n';         run import-validator; expect none "clean code"
j_write "$(p notes.md)" 'never use eval(data)';                        run import-validator; expect none "not a code file"

# ----------------------------------------------------------------------------- env-guard
j_write "$(p .env.production)" 'API_URL=http://localhost:3000';        run env-guard; expect ask  "localhost in .env.production" 'ENV GUARD'
j_write "$(p .env.production)" 'API_URL=https://api.example.com';      run env-guard; expect none "clean .env.production"
j_write "$(p config.dev.json)" '{"api": "https://prod.example.com"}';  run env-guard; expect ask  "prod URL in dev config"
j_write "$(p src/client.ts)" 'const u = "https://staging.acme.io";';   run env-guard; expect ask  "hardcoded staging URL in source"
mkfile deploy/.env.production "DB_HOST=127.0.0.1"
j_read "$(p deploy/.env.production)";                                  run env-guard; expect ask  "Read scans the file on disk"
j_write "$(p notes.md)" 'see http://localhost:3000';                   run env-guard; expect none "file without rule"

# ----------------------------------------------------------------------------- plc-safety-guard
j_write "$(p plc/main.st)" '%QX0.1 := TRUE;';                          run plc-safety-guard; expect ask  "direct output write" 'PLC SAFETY'
j_write "$(p plc/main.st)" $'WHILE TRUE DO\n  x := x + 1;\nEND_WHILE';  run plc-safety-guard; expect ask  "WHILE TRUE without watchdog"
j_write "$(p plc/main.st)" 'x := 1;';                                  run plc-safety-guard; expect none "benign statement"
j_write "$(p src/a.py)" '%QX0.1 := TRUE;';                             run plc-safety-guard; expect none "not a PLC file"

# ----------------------------------------------------------------------------- protocol-validator
j_write "$(p cfg/bus.yaml)" $'modbus:\n  unit_id: 300\n';              run protocol-validator; expect ask  "Modbus unit id > 247" 'unit ID 300'
j_write "$(p cfg/opc.yaml)" $'opcua:\n  security_mode: None\n';        run protocol-validator; expect ask  "OPC-UA SecurityMode None"
j_write "$(p cfg/mq.yaml)" 'broker: mqtt://10.0.0.5:1883';             run protocol-validator; expect ask  "MQTT without TLS"
j_write "$(p cfg/bus.yaml)" $'modbus:\n  unit_id: 12\n  register: 40001\n'; run protocol-validator; expect none "valid Modbus config"
j_write "$(p cfg/app.yaml)" 'name: demo';                              run protocol-validator; expect none "no protocol"

# ----------------------------------------------------------------------------- network-segmentation
j_write "$(p cfg/net.yaml)" $'erp: 10.1.2.3\nplc: 192.168.50.10\n';    run network-segmentation; expect ask  "IT + OT addresses" 'IT and OT'
j_write "$(p cfg/net.yaml)" 'erp: 10.1.2.3';                           run network-segmentation; expect none "IT address only"
j_write "$(p cfg/net.yaml)" 'plc: 10.135.1.1';                         run network-segmentation; expect none "single OT address inside the IT supernet"
j_bash 'ssh admin@192.168.200.5';                                      run network-segmentation; expect ask  "SAFETY zone in a Bash command" 'SAFETY'
j_bash 'echo version 1.2';                                             run network-segmentation; expect none "no IP address"

# ----------------------------------------------------------------------------- realtime-constraint
j_write "$(p fw/isr.c)" 'buf = malloc(64);';                           run realtime-constraint; expect ask  "malloc" 'REAL-TIME'
j_write "$(p fw/isr.c)" $'while (1) {\n  poll();\n}';                  run realtime-constraint; expect ask  "while(1) without break/timeout"
j_write "$(p fw/isr.c)" 'int x = 1;';                                  run realtime-constraint; expect none "benign C"
j_write "$(p src/a.py)" 'buf = malloc(64)';                            run realtime-constraint; expect none "not an embedded file"

# ----------------------------------------------------------------------------- safety-standard-check
j_write "$(p fw/m.c)" 'goto fail;';                                    run safety-standard-check; expect ask  "goto" 'IEC61508'
j_write "$(p fw/m.c)" 'p = malloc(4);';                                run safety-standard-check; expect ask  "rule whose regex contains |" 'R\.21\.3'
j_write "$(p fw/m.c)" 'char *pwd = "hunter22";';                       run safety-standard-check; expect ask  "hardcoded credentials (SR 1.1)" 'SR1\.1'
j_write "$(p fw/m.c)" 'int x = 1;';                                    run safety-standard-check; expect none "benign C"

# ----------------------------------------------------------------------------- hardware-register-guard
j_write "$(p fw/wdg.c)" 'IWDG->KR = 0xAAAA;';                          run hardware-register-guard; expect ask  "watchdog key register write" 'watchdog'
j_write "$(p fw/wdg.c)" 'NVIC_SystemReset();';                         run hardware-register-guard; expect ask  "system reset call"
j_write "$(p fw/wdg.c)" '__WFI();';                                    run hardware-register-guard; expect ask  "__WFI()"
j_write "$(p fw/wdg.c)" 'int x = 1;';                                  run hardware-register-guard; expect none "benign C"

# ============================================================================= PostToolUse
EVENT=PostToolUse

# ----------------------------------------------------------------------------- context-usage-monitor
seq 1 30   > "$SANDBOX/small.txt"
seq 1 9990 > "$SANDBOX/huge.txt"
j_read "$(p small.txt)";       run context-usage-monitor; expect none "small read"
check "counter = 30" has .claude/context-usage.txt '^30( |$)'
j_read "$(p huge.txt)" 9990;   run context-usage-monitor; expect msg  "crossing the warning threshold" 'CONTEXT WARNING'
j_read "$(p small.txt)";       run context-usage-monitor; expect none "no repeated warning once past the threshold"
j_read "$(p huge.txt)" 50;     run context-usage-monitor
check "Read with limit=50 counts 50 lines" has .claude/context-usage.txt '^10100( |$)'
SESSION="sess-2"
j_read "$(p small.txt)";       run context-usage-monitor; expect none "new session"
check "counter resets on new session" has .claude/context-usage.txt '^30( |$)'
SESSION="sess-1"

# ----------------------------------------------------------------------------- session-recap
j_edit "$(p src/a.txt)" 'old "value"' $'new\nvalue';   run session-recap; expect none "silent"
check "edit logged" has .claude/session-recap.md '\*\*Edited\*\* .*a\.txt'
j_write "$(p src/b.txt)" hi;                            run session-recap
check "write logged" has .claude/session-recap.md '\*\*Created/Wrote\*\* .*b\.txt'
j_bash 'git commit -m "feat: x"';                       run session-recap
check "git command logged" has .claude/session-recap.md '\*\*Ran\*\* `git commit'
j_bash 'ls -la';                                        run session-recap
check "trivial command not logged" hasnt .claude/session-recap.md 'ls -la'
check "single header" [ "$(grep -c '^# Session Recap' "$SANDBOX/.claude/session-recap.md")" = 1 ]

# ----------------------------------------------------------------------------- change-logger
j_edit "$(p src/a.txt)" a b;                            run change-logger; expect none "silent"
check "edit logged" has .claude/changelog.log '\] Edit: .*a\.txt'
j_bash 'git commit -m "feat: x"';                       run change-logger
check "git commit logged" has .claude/changelog.log '\] Bash: git commit'
j_bash 'ls -la';                                        run change-logger
check "ls not logged" hasnt .claude/changelog.log 'ls -la'

# ----------------------------------------------------------------------------- complexity-guard
mkfile src/params.py $'def build(a, b, c, d, e, f, g):\n    return a\n'
j_edit "$(p src/params.py)" x y;        run complexity-guard; expect msg  "7 parameters" '7 parameters'
{ echo "def flat(x):"; for i in 1 2 3 4 5 6 7 8; do printf '    if x == %s:\n        return %s\n' $i $i; done; echo "    return 0"; } > "$SANDBOX/src/flat.py"
j_edit "$(p src/flat.py)" x y;          run complexity-guard; expect none "8 sequential ifs are not nesting"
mkfile src/deep.py $'def deep(x):\n    if x:\n        for a in x:\n            while a:\n                if a > 1:\n                    try:\n                        a -= 1\n                    except ValueError:\n                        pass\n    return x\n'
j_edit "$(p src/deep.py)" x y;          run complexity-guard; expect msg  "5 nested levels (Python)" 'Deep nesting'
mkfile src/deep.ts $'export function deep(x: number[]): number {\n  if (x) {\n    for (const a of x) {\n      while (a) {\n        if (a > 1) {\n          try {\n            return a;\n          } catch (e) {\n            return 0;\n          }\n        }\n      }\n    }\n  }\n  return 0;\n}\n'
j_edit "$(p src/deep.ts)" x y;          run complexity-guard; expect msg  "5 nested levels (TypeScript)" 'Deep nesting'
{ echo "function long(a) {"; for i in $(seq 1 60); do echo "  a += $i;"; done; echo "  return a;"; echo "}"; } > "$SANDBOX/src/long.js"
j_edit "$(p src/long.js)" x y;          run complexity-guard; expect msg  "62-line function" 'lines \(max: 50\)'
mkfile src/ok.ts $'export function add(a: number, b: number): number {\n  if (a > b) {\n    return a - b;\n  }\n  return a + b;\n}\n\nexport const twice = (n: number) => {\n  return check(n, 1, 2, 3, 4, 5, 6, 7) ? n * 2 : n;\n};\n'
j_edit "$(p src/ok.ts)" x y;            run complexity-guard; expect none "simple code (call with many arguments is not a declaration)"
j_edit "$(p notes.md)" x y;             run complexity-guard; expect none "not a code file"

# ----------------------------------------------------------------------------- naming-convention
mkfile src/user.ts $'export interface User {\n  id: number;\n}\n'
j_edit "$(p src/user.ts)" x y;          run naming-convention; expect msg  "TS interface without I prefix" 'Interface'
mkfile src/bad.py $'def BadName():\n    pass\n'
j_edit "$(p src/bad.py)" x y;           run naming-convention; expect msg  "Python function not snake_case" 'BadName'
mkfile src/good.py $'class Order:\n    def total_price(self):\n        return 1\n'
j_edit "$(p src/good.py)" x y;          run naming-convention; expect none "conforming Python"
mkfile src/main.go $'package main\n\nfunc main() {\n}\n\nfunc Exported() {\n}\n'
j_edit "$(p src/main.go)" x y;          run naming-convention; expect none "Go: unexported camelCase and exported PascalCase"

# ----------------------------------------------------------------------------- docker-best-practices
mkfile docker/a/Dockerfile $'FROM node:latest\nCOPY . .\nRUN npm install\n'
j_edit "$(p docker/a/Dockerfile)" x y;  run docker-best-practices; expect msg  "bad Dockerfile" 'latest'
mkfile docker/b/Dockerfile $'FROM node:20.11-alpine\nCOPY package.json .\nRUN npm install\nCOPY . .\nUSER node\n'
mkfile docker/b/.dockerignore 'node_modules'
j_edit "$(p docker/b/Dockerfile)" x y;  run docker-best-practices; expect none "good Dockerfile"
j_edit "$(p src/a.txt)" x y;            run docker-best-practices; expect none "not a Dockerfile"

# ----------------------------------------------------------------------------- firmware-changelog
mkfile fw/drivers/gpio.c $'void led_on(void) {\n  GPIOA->ODR |= 1;\n}\nvoid EXTI0_IRQHandler(void) {}\n'
j_edit "$(p fw/drivers/gpio.c)" x y;    run firmware-changelog; expect none "silent"
check "entry with peripheral tags" has .claude/firmware-changelog.md 'gpio\.c\*\* \[GPIO,IRQ,REGISTERS\]'
j_edit "$(p src/a.txt)" x y;            run firmware-changelog
check "non-firmware file ignored" hasnt .claude/firmware-changelog.md 'a\.txt'

# ----------------------------------------------------------------------------- auto-test-runner
# A fake "pytest" module: fails when the test file contains the word FAIL.
mkfile pytest.py $'import sys\nargs = [a for a in sys.argv[1:] if not a.startswith("-")]\nsys.exit(1 if "FAIL" in open(args[0]).read() else 0)\n'
mkfile calc/good.py 'x = 1';  mkfile calc/test_good.py '# passes'
mkfile calc/bad.py  'x = 1';  mkfile calc/test_bad.py  '# FAIL'
mkfile calc/lonely.py 'x = 1'
wait_log() { local i; for i in $(seq 1 40); do grep -qE -e "$1" "$SANDBOX/.claude/test-results.log" 2>/dev/null && return 0; sleep 0.25; done; return 1; }
j_edit "$(p calc/good.py)" x y;         run auto-test-runner; expect none "silent"
check "passing test logged as PASS" wait_log 'AUTO-TEST PASS: .*test_good\.py'
j_edit "$(p calc/bad.py)" x y;          run auto-test-runner; expect msg  "failing test reported to Claude" 'AUTO-TEST FAIL: .*test_bad\.py'
check "failing test logged as FAIL" wait_log 'AUTO-TEST FAIL: .*test_bad\.py'
j_edit "$(p calc/lonely.py)" x y;       run auto-test-runner; expect none "no related test"
check "nothing logged without related test" hasnt .claude/test-results.log 'lonely'

# ============================================================================= Dispatcher
# Every hook registered for the tool runs at once and the answers are merged.
EVENT=PreToolUse
j_bash 'git push --force origin main';            dispatch PreToolUse
expect ask  "ask reasons of several hooks are merged" '(DANGEROUS COMMAND.* \| .*BRANCH PROTECTION|BRANCH PROTECTION.* \| .*DANGEROUS COMMAND)'
j_bash 'ls -la';                                  dispatch PreToolUse; expect none "silent when no hook objects"
j_write "$(p src/a.py)" 'x = eval(data)';         dispatch PreToolUse; expect ask  "a single objection passes through" 'IMPORT/CODE VIOLATION'
j_write "$NHOME${SEP}.aws${SEP}x.py" 'x = eval(data)'; dispatch PreToolUse
expect deny "deny wins over ask" 'BLOCKED'
check "the losing ask reason is dropped" [ "${OUT/IMPORT/}" = "$OUT" ]
EVENT=PostToolUse
mkfile src/both.py $'def BadName(a, b, c, d, e, f, g):\n    return a\n'
j_edit "$(p src/both.py)" x y;                    dispatch PostToolUse
expect msg  "PostToolUse warnings of several hooks are merged" '(COMPLEXITY WARNING.*NAMING CONVENTION|NAMING CONVENTION.*COMPLEXITY WARNING)'
check "merged warning also reaches the user (systemMessage)" [ "${OUT/systemMessage/}" != "$OUT" ]
j_edit "$(p src/good.py)" x y;                    dispatch PostToolUse; expect none "silent PostToolUse"
check "loggers ran through the dispatcher" has .claude/changelog.log 'Edit: .*good\.py'

# ----------------------------------------------------------------------------- in-process safety
# The dispatcher sources every hook in one process: a hook must not call `exit`
# and must not leave variables or shell options behind.
HOOK=isolation
BAD_EXIT=$(grep -nE '(^|[[:space:];&|])exit([[:space:]]+[0-9]+)?[[:space:]]*(;|$)' "$ROOT"/*/hook.sh | grep -v '|| exit 1; fi$')
check "no hook calls exit outside the library-loading line${BAD_EXIT:+ ($BAD_EXIT)}" [ -z "$BAD_EXIT" ]
NOT_WRAPPED=$(grep -L '^main$' "$ROOT"/*/hook.sh)
check "every hook body is a main() function${NOT_WRAPPED:+ ($NOT_WRAPPED)}" [ -z "$NOT_WRAPPED" ]

cat > "$OUTSIDE/leaks.sh" <<'LEAKS'
# Sources every installed hook in this process and reports what each one leaves behind.
HOOK_DIR=.claude/hooks
. "$HOOK_DIR/_common.sh"
NL=$'\n'; before=""; after=""; v=""; f=""
for f in "$HOOK_DIR"/[a-z]*.sh; do
  before=$(compgen -v)
  . "$f" >/dev/null 2>&1
  [ "$(shopt -p nocasematch)" = "shopt -u nocasematch" ] || shopt -u nocasematch
  after=$(compgen -v)
  for v in $after; do
    case "$NL$before$NL" in *"$NL$v$NL"*) continue ;; esac
    [ "$v" = BASH_REMATCH ] && continue   # set by bash itself on the first [[ =~ ]]
    # Configuration constants assigned at the top of the file are re-assigned on every run
    grep -q "^$v=" "$f" || echo "${f##*/}:$v"
  done
done
LEAKS
leaks() { # (uses $JSON) -> variables leaked by any hook when run in-process
  ( cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$NSANDBOX" bash "$OUTSIDE/leaks.sh" <<<"$JSON" 2>&1 | tr '\n' ' ' )
}
( cd "$SANDBOX" && git add cfg/ok.txt >/dev/null 2>&1 )
for scenario in "PreToolUse:bash:git push --force origin main" "PreToolUse:bash:git add . && git commit -am 'wip'" \
                "PreToolUse:write:src/domain/x.py" "PreToolUse:write:fw/x.c" "PreToolUse:read:docs/client.txt" \
                "PreToolUse:grep:docs" "PostToolUse:edit:src/both.py" "PostToolUse:edit:fw/drivers/gpio.c" \
                "PostToolUse:bash:git commit -m x" "PostToolUse:read:small.txt"; do
  EVENT=${scenario%%:*}; rest=${scenario#*:}; kind=${rest%%:*}; arg=${rest#*:}
  case "$kind" in
    bash)  j_bash "$arg" ;;
    write) j_write "$(p "$arg")" $'import os\nfrom app.infrastructure import db\nx = eval("1")\nIWDG->KR = 0xAAAA; malloc(4); host = "10.1.2.3 192.168.50.1 modbus unit_id: 300"\n' ;;
    read)  j_read "$(p "$arg")" ;;
    grep)  j_grep 'Contract' "$(p "$arg")" content ;;
    edit)  j_edit "$(p "$arg")" x y ;;
  esac
  LEAKED=$(leaks)
  check "no state leaks between hooks ($scenario)${LEAKED:+ -> $LEAKED}" [ -z "$LEAKED" ]
done
( cd "$SANDBOX" && git reset -q >/dev/null 2>&1 )

# ============================================================================= Output validity
HOOK=output
if [ -s "$ALL_OUT" ]; then
  BAD=$(python3 -c "
import json, sys
bad = 0
for n, line in enumerate(open(sys.argv[1], encoding='utf-8', errors='replace'), 1):
    try:
        d = json.loads(line)
        h = d.get('hookSpecificOutput', {})
        assert h.get('hookEventName') in ('PreToolUse', 'PostToolUse')
        assert not (set(h) - {'hookEventName', 'permissionDecision', 'permissionDecisionReason', 'additionalContext'}), 'unknown field'
        assert not (set(d) - {'hookSpecificOutput', 'systemMessage'}), 'unknown top-level field'
    except Exception as e:
        bad += 1
print(bad)" "$ALL_OUT" 2>&1)
  check "every hook output is valid JSON with documented fields only ($BAD invalid)" [ "$BAD" = 0 ]
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" = 0 ]
