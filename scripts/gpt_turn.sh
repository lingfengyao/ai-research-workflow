#!/usr/bin/env bash
# Run ONE GPT (Codex CLI) turn of a research debate inside a topic dir.
#
# Usage:
#   gpt_turn.sh -d <topic_dir> -p <prompt_file> -o <output_md> [--new] [-m model]
#               [-e low|medium|high|xhigh] [--no-search] [--ro]
#               [--role <role_file>] [--session-file <path>]
#
#   -d  topic dir (<project>/research/<topic-slug>/); codex runs with -C/cwd = this dir.
#       workspace-write lets GPT write inside it (and, per codex's sandbox, /tmp and $TMPDIR).
#   -p  prompt file for this turn (e.g. debate/round-02-gpt-prompt.md); relative paths are
#       resolved against the CURRENT dir
#   -o  where GPT's final message is written (e.g. debate/round-02-gpt-response.md); relative
#       paths are resolved against the CURRENT dir. Must NOT already exist (never overwritten).
#   --new        start a new GPT session (role preamble prepended); also implied when the
#                session file does not exist
#   -m           model (default: from ~/.codex/config.toml)
#   -e           reasoning effort
#   --no-search  disable live web search (default: enabled)
#   --ro         read-only sandbox (GPT cannot edit proposal.md etc.)
#   --role       role preamble for a NEW session (default: <kit>/prompts/gpt_role_proposer.md;
#                e.g. <kit>/prompts/gpt_role_skeptic.md for results review). Error on resume.
#   --session-file  session-id file; relative paths are resolved against the TOPIC dir
#                (default: debate/.gpt_session = the proposer/debate session). Side runs
#                (results review, idea evaluation) must use their own, e.g.
#                debate/.gpt_session.results, so they never replace the debate session.
#
# Side effects (inside <topic_dir>/debate/):
#   .events/<ts>.jsonl  raw codex JSONL events     .events/<ts>.stderr.log  codex stderr
#   .events/<ts>.prompt.md  exact prompt sent      .events/<ts>.protected/  pre-turn copies of
#   protected files     <session-file>  thread id (an existing one is moved to <file>.<ts>.bak
#   when --new replaces it)                        .lock  held while the turn runs
#
# Protected files (GPT must not change them; checked by hash before/after the turn):
#   brief.md, decisions.md, debate/round-*-claude-review.md, debate/.gpt_session*
#
# Exit codes: 2 usage/missing input/lock held; codex's own non-zero code on codex failure;
#             3 codex exited 0 but no output / no session id / unparsable events;
#             4 GPT modified a protected file (originals in .events/<ts>.protected/).
# No fallbacks: any missing piece is a hard error.
set -euo pipefail

die() { echo "gpt_turn.sh: ERROR: $1" >&2; exit "${2:-2}"; }

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
KIT="$(cd "$HERE/.." && pwd)"
ROLE="$KIT/prompts/gpt_role_proposer.md"; ROLE_SET=0

TOPIC=""; PROMPT=""; OUT=""; NEW=0; MODEL=""; EFFORT=""; SEARCH=1; SANDBOX="workspace-write"
SESS_ARG="debate/.gpt_session"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) [[ $# -ge 2 ]] || die "-d needs a value"; TOPIC="$2"; shift 2;;
    -p) [[ $# -ge 2 ]] || die "-p needs a value"; PROMPT="$2"; shift 2;;
    -o) [[ $# -ge 2 ]] || die "-o needs a value"; OUT="$2"; shift 2;;
    -m) [[ $# -ge 2 ]] || die "-m needs a value"; MODEL="$2"; shift 2;;
    -e) [[ $# -ge 2 ]] || die "-e needs a value"; EFFORT="$2"; shift 2;;
    --role) [[ $# -ge 2 ]] || die "--role needs a value"; ROLE="$2"; ROLE_SET=1; shift 2;;
    --session-file) [[ $# -ge 2 ]] || die "--session-file needs a value"; SESS_ARG="$2"; shift 2;;
    --new) NEW=1; shift;;
    --no-search) SEARCH=0; shift;;
    --ro) SANDBOX="read-only"; shift;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
    *) die "unknown argument: $1";;
  esac
done

[[ -n "$TOPIC" ]]  || die "missing -d <topic_dir>"
[[ -n "$PROMPT" ]] || die "missing -p <prompt_file>"
[[ -n "$OUT" ]]    || die "missing -o <output_md>"
[[ -d "$TOPIC" ]]  || die "topic dir does not exist: $TOPIC"
[[ -f "$PROMPT" ]] || die "prompt file does not exist: $PROMPT"
[[ -s "$PROMPT" ]] || die "prompt file is empty: $PROMPT"
case "$EFFORT" in ""|low|medium|high|xhigh) ;; *) die "-e must be low|medium|high|xhigh, got: $EFFORT";; esac
command -v codex >/dev/null   || die "codex CLI not found in PATH"
command -v python3 >/dev/null || die "python3 not found in PATH"

TOPIC="$(cd "$TOPIC" && pwd)"
PROMPT="$(cd "$(dirname "$PROMPT")" && pwd)/$(basename "$PROMPT")"
OUT_DIR="$(dirname "$OUT")"
[[ -d "$OUT_DIR" ]] || die "output dir does not exist: $OUT_DIR"
OUT="$(cd "$OUT_DIR" && pwd)/$(basename "$OUT")"
[[ ! -e "$OUT" ]] || die "output exists: $OUT (move it away or pick a new name; gpt_turn.sh never overwrites)"
case "$SESS_ARG" in /*) SESS_FILE="$SESS_ARG";; *) SESS_FILE="$TOPIC/$SESS_ARG";; esac
[[ -d "$(dirname "$SESS_FILE")" ]] || die "session-file dir does not exist: $(dirname "$SESS_FILE")"

DEBATE="$TOPIC/debate"; EVDIR="$DEBATE/.events"
mkdir -p "$EVDIR"

# One turn per topic at a time (mkdir is atomic and portable; flock is missing on macOS)
LOCK="$DEBATE/.lock"
mkdir "$LOCK" 2>/dev/null || die "another gpt_turn.sh is running on $TOPIC (lock $LOCK; if no turn is running, rmdir it)"
trap 'rmdir "$LOCK"' EXIT

SID=""
if [[ $NEW -eq 0 ]]; then
  if [[ -f "$SESS_FILE" ]]; then
    SID="$(tr -d '[:space:]' < "$SESS_FILE")"
    [[ -n "$SID" ]] || die "$SESS_FILE exists but is empty; delete it or pass --new"
  else
    NEW=1
    echo "gpt_turn.sh: no $SESS_FILE -> starting a NEW session (role preamble prepended)" >&2
  fi
fi
if [[ $NEW -eq 1 ]]; then
  [[ -f "$ROLE" ]] || die "role preamble not found: $ROLE"
elif [[ $ROLE_SET -eq 1 ]]; then
  die "--role only applies to a new session; $SESS_FILE exists (pass --new, or a different --session-file)"
fi

TS="$(date +%Y%m%d-%H%M%S)-$$"
EVENTS="$EVDIR/$TS.jsonl"; ERRLOG="$EVDIR/$TS.stderr.log"; SENT="$EVDIR/$TS.prompt.md"
PROT="$EVDIR/$TS.protected"
[[ ! -e "$EVENTS" ]] || die "events file already exists (timestamp+pid collision): $EVENTS"

{
  if [[ $NEW -eq 1 ]]; then
    cat "$ROLE"
    printf '\n\n---\n\n# Topic directory\nYour working root is `%s`. Only create/edit files inside it.\n' "$TOPIC"
    printf 'Kit templates (read-only; follow their structure): `%s/templates/` (proposal.md, references.md, ...).\n' "$KIT"
    printf '\n---\n\n# This turn\n'
  fi
  cat "$PROMPT"
} > "$SENT"

# Hash manifest of protected files (python for portability: no sha256sum on macOS).
# A leading '.' in a glob component matches dot-files, so .gpt_session* is covered.
manifest() {
  (cd "$TOPIC" && python3 - <<'PY'
import glob, hashlib
pats = ["brief.md", "decisions.md", "debate/round-*-claude-review.md", "debate/.gpt_session*"]
for p in sorted({f for pat in pats for f in glob.glob(pat) if not f.endswith(".bak")}):
    print(hashlib.sha256(open(p, "rb").read()).hexdigest(), p)
PY
  )
}
BEFORE="$(manifest)" || die "could not hash protected files in $TOPIC"
mkdir "$PROT"
while read -r _ f; do
  [[ -n "$f" ]] || continue
  mkdir -p "$PROT/$(dirname "$f")"; cp -p "$TOPIC/$f" "$PROT/$f"
done <<<"$BEFORE"

# Global flags (must precede `exec`)
GLOBAL=()
[[ $SEARCH -eq 1 ]] && GLOBAL+=(--search)
# exec / exec resume flags (resume has no -C/-s, so use -c overrides + cd for both)
ARGS=(--skip-git-repo-check --json -o "$OUT"
      -c "sandbox_mode=\"$SANDBOX\"" -c 'approval_policy="never"')
[[ -n "$MODEL" ]]  && ARGS+=(-m "$MODEL")
[[ -n "$EFFORT" ]] && ARGS+=(-c "model_reasoning_effort=\"$EFFORT\"")

START=$(date +%s)
set +e
if [[ $NEW -eq 1 ]]; then
  (cd "$TOPIC" && codex ${GLOBAL[@]+"${GLOBAL[@]}"} exec -C "$TOPIC" "${ARGS[@]}" - < "$SENT") > "$EVENTS" 2> "$ERRLOG"
else
  (cd "$TOPIC" && codex ${GLOBAL[@]+"${GLOBAL[@]}"} exec resume "${ARGS[@]}" "$SID" - < "$SENT") > "$EVENTS" 2> "$ERRLOG"
fi
RC=$?
set -e
ELAPSED=$(( $(date +%s) - START ))
AFTER="$(manifest)" || die "could not hash protected files in $TOPIC after the turn"

if [[ $RC -ne 0 ]]; then
  echo "gpt_turn.sh: ERROR: codex exited with code $RC after ${ELAPSED}s" >&2
  echo "--- last 20 lines of $ERRLOG:" >&2; tail -n 20 "$ERRLOG" >&2
  echo "--- error events in $EVENTS:" >&2
  grep -E '"type":"(error|turn.failed)"' "$EVENTS" | cut -c1-400 >&2 || echo "(none)" >&2
  [[ "$BEFORE" == "$AFTER" ]] || echo "gpt_turn.sh: WARNING: protected files changed during the failed turn; originals in $PROT" >&2
  exit "$RC"
fi

# Parse events (same approach as ~/.claude/codex/summarize_events.py: thread.started -> thread_id,
# turn.completed -> usage, item.completed -> web_search / command_execution / file_change)
PARSED="$(python3 - "$EVENTS" <<'PY'
import json, sys
sid, usage, n_search, n_cmd, n_file, errors = None, {}, 0, 0, 0, []
for n, line in enumerate(open(sys.argv[1], errors="replace"), 1):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        e = json.loads(line)
    except json.JSONDecodeError as ex:
        sys.exit(f"malformed JSON on line {n}: {ex}")
    t = e.get("type")
    if t == "thread.started":
        sid = e.get("thread_id")
    elif t == "turn.completed":
        for k, v in (e.get("usage") or {}).items():
            usage[k] = usage.get(k, 0) + v
    elif t in ("error", "turn.failed"):
        errors.append(json.dumps(e)[:300])
    elif t == "item.completed":
        it = e.get("item", {}).get("type")
        n_search += it == "web_search"
        n_cmd += it == "command_execution"
        n_file += it == "file_change"
print(sid or "")
print(json.dumps(usage) if usage else "n/a")
print(f"web_search={n_search} commands={n_cmd} file_changes={n_file}")
print(" || ".join(errors))
PY
)" || die "event parse failed: $EVENTS (GPT output, if any: $OUT)" 3
NEW_SID="$(sed -n 1p <<<"$PARSED")"; USAGE="$(sed -n 2p <<<"$PARSED")"
TOOLS="$(sed -n 3p <<<"$PARSED")"; EVERR="$(sed -n 4p <<<"$PARSED")"

# Save the session id first, so it is never lost when a later check fails.
if [[ $NEW -eq 1 ]]; then
  [[ -n "$NEW_SID" ]] || die "no thread.started/thread_id in events: $EVENTS" 3
  if [[ -e "$SESS_FILE" ]]; then
    mv "$SESS_FILE" "$SESS_FILE.$TS.bak"
    echo "gpt_turn.sh: NOTE: --new replaced $SESS_FILE; previous session id kept in $SESS_FILE.$TS.bak" >&2
  fi
  echo "$NEW_SID" > "$SESS_FILE"; SID="$NEW_SID"
elif [[ -n "$NEW_SID" && "$NEW_SID" != "$SID" ]]; then
  die "resume returned a DIFFERENT thread id ($NEW_SID) than $SESS_FILE ($SID)" 3
fi

[[ -s "$OUT" ]] || die "codex exited 0 but output file is missing/empty: $OUT (see $EVENTS, $ERRLOG)" 3

if [[ "$BEFORE" != "$AFTER" ]]; then
  echo "gpt_turn.sh: ERROR: GPT modified protected files during this turn (< before, > after):" >&2
  diff <(echo "$BEFORE") <(echo "$AFTER") >&2 || true
  echo "Originals (pre-turn copies): $PROT   GPT output: $OUT   session: $SESS_FILE" >&2
  echo "Inspect, restore from $PROT, and treat this as a defect before continuing." >&2
  exit 4
fi

ESC=0; grep -q '^## ESCALATE' "$OUT" && ESC=1

echo "=== gpt_turn.sh summary ==="
echo "exit_code: $RC   elapsed: ${ELAPSED}s   mode: $([[ $NEW -eq 1 ]] && echo new || echo resume)   sandbox: $SANDBOX   search: $([[ $SEARCH -eq 1 ]] && echo on || echo off)"
[[ $NEW -eq 1 ]] && echo "role:      $ROLE"
echo "session:   $SID  (-> $SESS_FILE)"
echo "output:    $OUT"
echo "events:    $EVENTS"
echo "tools:     $TOOLS"
echo "tokens:    $USAGE"
echo "protected: unchanged"
[[ -n "$EVERR" ]] && echo "event errors (codex exited 0): $EVERR"
if [[ $ESC -eq 1 ]]; then
  echo
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!! ESCALATE: GPT requests a HUMAN decision. STOP the debate loop. !!!"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  sed -n '/^## ESCALATE/,$p' "$OUT"
  echo
else
  echo "escalate:  no"
fi
