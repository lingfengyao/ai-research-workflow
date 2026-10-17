#!/usr/bin/env bash
# Delegate one task to Codex and collect everything the supervisor needs to audit it.
#
# New task:  run_codex.sh -C <workdir> -s <spec.md> [-n name] [--sandbox|--ro] [--net] [-m model] [-e effort]
#   default: full access (GPU, conda, ~/.cache, network)
#   --sandbox  workspace-write sandbox (no GPU, writes only in workdir)   --ro  read-only investigation
#   --net      allow network inside --sandbox
# Follow-up: run_codex.sh -C <workdir> -r <prev_run_dir> -s <feedback.md> [...]
#
# Outputs in <workdir>/.codex_runs/<timestamp>-<name>/ :
#   spec.md  prompt.md  events.jsonl  report.json  session_id  changes.diff  diffstat.txt
#   audit.txt  commands.txt  stderr.log  SUMMARY.txt
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORKDIR=""; SPEC=""; NAME="task"; PREV=""; SANDBOX="danger-full-access"; NET=0
MODEL="${CODEX_MODEL:-}"; EFFORT="${CODEX_EFFORT:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) WORKDIR="$2"; shift 2;;
    -s) SPEC="$2"; shift 2;;
    -n) NAME="$2"; shift 2;;
    -r) PREV="$2"; shift 2;;
    -m) MODEL="$2"; shift 2;;
    -e) EFFORT="$2"; shift 2;;
    --full) SANDBOX="danger-full-access"; shift;;
    --sandbox) SANDBOX="workspace-write"; shift;;
    --net) NET=1; shift;;
    --ro) SANDBOX="read-only"; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -d "$WORKDIR" && -f "$SPEC" ]] || { echo "need -C <existing dir> and -s <spec file>" >&2; exit 2; }
WORKDIR="$(cd "$WORKDIR" && pwd)"

RUNS="$WORKDIR/.codex_runs"; mkdir -p "$RUNS"
RUN="$RUNS/$(date +%Y%m%d-%H%M%S)-${NAME//[^A-Za-z0-9_-]/_}"; mkdir -p "$RUN"
cp "$SPEC" "$RUN/spec.md"

IS_GIT=0
if git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1
  ex="$(git -C "$WORKDIR" rev-parse --git-path info/exclude)"; [[ "$ex" = /* ]] || ex="$WORKDIR/$ex"
  mkdir -p "$(dirname "$ex")"; grep -qx '.codex_runs/' "$ex" 2>/dev/null || echo '.codex_runs/' >> "$ex"
  BEFORE="$("$HERE/snapshot_tree.sh" "$WORKDIR")"
fi

# ---- build prompt
{
  cat "$HERE/executor_contract.md"
  echo; echo "---"; echo
  if [[ -n "$PREV" ]]; then
    echo "# Supervisor feedback on your previous attempt"
    echo "The supervisor reviewed your diff, re-ran your commands and checked your report. Address every point."
    echo "The executor contract above still applies in full."
    echo
  else
    echo "# Task spec"
  fi
  cat "$SPEC"
} > "$RUN/prompt.md"

ARGS=(--skip-git-repo-check --json --output-schema "$HERE/report_schema.json" -o "$RUN/report.json")
[[ -n "$MODEL" ]] && ARGS+=(-m "$MODEL")
[[ -n "$EFFORT" ]] && ARGS+=(-c "model_reasoning_effort=\"$EFFORT\"")
SBX=()
if [[ "$SANDBOX" == "danger-full-access" ]]; then SBX=(--dangerously-bypass-approvals-and-sandbox)
else SBX=(-c "sandbox_mode=\"$SANDBOX\"" -c "approval_policy=\"never\"")
     [[ $NET == 1 ]] && SBX+=(-c "sandbox_workspace_write.network_access=true"); fi

START=$(date +%s)
if [[ -n "$PREV" ]]; then
  SID="$(cat "$PREV/session_id" 2>/dev/null)"; [[ -n "$SID" ]] || { echo "no session_id in $PREV" >&2; exit 2; }; echo "$PREV" > "$RUN/parent_run"
  (cd "$WORKDIR" && codex exec resume "${ARGS[@]}" "${SBX[@]}" "$SID" - < "$RUN/prompt.md") > "$RUN/events.jsonl" 2> "$RUN/stderr.log"
else
  codex exec -C "$WORKDIR" "${ARGS[@]}" "${SBX[@]}" - < "$RUN/prompt.md" > "$RUN/events.jsonl" 2> "$RUN/stderr.log"
fi
RC=$?
ELAPSED=$(( $(date +%s) - START ))

python3 "$HERE/summarize_events.py" "$RUN" > /dev/null

if [[ $IS_GIT == 1 ]]; then
  AFTER="$("$HERE/snapshot_tree.sh" "$WORKDIR")"
  git -C "$WORKDIR" diff "$BEFORE" "$AFTER" > "$RUN/changes.diff"
  git -C "$WORKDIR" diff --stat "$BEFORE" "$AFTER" > "$RUN/diffstat.txt"
  python3 "$HERE/audit_diff.py" "$RUN/changes.diff" > "$RUN/audit.txt"
else
  echo "(workdir is not a git repo: no diff captured; inspect files listed in report.json manually)" | tee "$RUN/diffstat.txt" > "$RUN/audit.txt"
fi

{
  echo "run_dir:   $RUN"
  echo "exit_code: $RC   elapsed: ${ELAPSED}s   sandbox: $SANDBOX net=$NET"
  echo "session:   $(cat "$RUN/session_id" 2>/dev/null || echo '?')"
  python3 - "$RUN/report.json" <<'PY'
import json, sys
try: r = json.load(open(sys.argv[1]))
except Exception as e: print(f"report:    MISSING/INVALID ({e}) -> check stderr.log / events.jsonl"); sys.exit()
print(f"status:    {r['status']}")
print(f"summary:   {r['summary']}")
for k in ("deviations_from_spec", "workarounds_or_fallbacks", "open_issues"):
    if r[k]: print(f"{k}:"); [print(f"  - {x}") for x in r[k]]
PY
  echo "--- diffstat"; tail -n 1 "$RUN/diffstat.txt"
  echo "--- $(head -n 1 "$RUN/audit.txt")"
  echo "--- commands executed: $(grep -c "^\[exit=" "$RUN/commands.txt" 2>/dev/null) (nonzero exit: $(grep -c "^\[exit=[1-9]" "$RUN/commands.txt" 2>/dev/null)) -> commands.txt"; echo "--- tokens: $(cat "$RUN/usage.json" 2>/dev/null)"
} | tee "$RUN/SUMMARY.txt"
exit $RC
