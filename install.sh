#!/usr/bin/env bash
# Idempotent installer for the research-workflow kit.
# Usage: ./install.sh [--dry-run]
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) echo "Usage: $0 [--dry-run]"; exit 0 ;;
    *) echo "ERROR: unknown argument: $arg" >&2; echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
MARK_START="<!-- research-workflow-kit:start -->"
MARK_END="<!-- research-workflow-kit:end -->"

declare -a SUMMARY=()
declare -a WARNINGS=()
SKIPPED=0

run() {
  # Print and (unless dry-run) execute a command.
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    "$@"
  fi
}

# link_item <kit_source> <target>
link_item() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then
    echo "ERROR: kit source missing: $src" >&2
    exit 1
  fi
  if [[ -L "$dst" ]]; then
    local cur
    cur="$(readlink -f "$dst")"
    if [[ "$cur" == "$(readlink -f "$src")" ]]; then
      SUMMARY+=("OK      $dst -> $src (already linked)")
    else
      SUMMARY+=("SKIP    $dst is a symlink to $cur (not this kit); fix manually: ln -sfn $src $dst")
      SKIPPED=$((SKIPPED + 1))
    fi
  elif [[ -e "$dst" ]]; then
    if diff -rq "$dst" "$src" >/dev/null 2>&1; then
      SUMMARY+=("OK      $dst exists as an identical copy of $src (not linked; future kit edits will NOT reach it)")
    else
      SUMMARY+=("SKIP    $dst exists and differs from the kit; not overwritten. Compare with: diff -r $dst $src")
      SKIPPED=$((SKIPPED + 1))
    fi
  else
    run mkdir -p "$(dirname "$dst")"
    run ln -s "$src" "$dst"
    SUMMARY+=("LINK    $dst -> $src")
  fi
}

echo "Kit dir: $KIT"
[[ $DRY_RUN -eq 1 ]] && echo "(dry run: nothing will be changed)"
echo

# 1. Prerequisites (warnings only)
command -v codex  >/dev/null 2>&1 || WARNINGS+=("codex not on PATH: GPT turns (scripts/gpt_turn.sh) and /codex will not work. Install codex-cli and run 'codex login'.")
command -v claude >/dev/null 2>&1 || WARNINGS+=("info: claude CLI not on PATH (fine if you use the Claude Code desktop app).")
command -v python3 >/dev/null 2>&1 || WARNINGS+=("python3 not on PATH: codex/summarize_events.py and codex/audit_diff.py need it.")

# 2. Make scripts executable
shopt -s nullglob
exec_files=("$KIT"/scripts/*.sh "$KIT"/codex/*.sh "$KIT"/codex/*.py)
shopt -u nullglob
if [[ ${#exec_files[@]} -gt 0 ]]; then
  run chmod +x "${exec_files[@]}"
  SUMMARY+=("CHMOD   ${#exec_files[@]} scripts made executable")
fi

# 3. Skills and codex tool dir
for name in research-workflow research-debate codex; do
  link_item "$KIT/skills/$name" "$SKILLS_DIR/$name"
done
link_item "$KIT/codex" "$CLAUDE_DIR/codex"

# 4. Global CLAUDE.md pointer block, managed between start/end markers (rewritten on every run,
#    so it never goes stale). Uses ${RESEARCH_KIT:-~/research-workflow}, not an absolute path.
BLOCK="$MARK_START
# Research workflow
Research workflow: see \${RESEARCH_KIT:-~/research-workflow}/RESEARCH_WORKFLOW.md; use /research-workflow for new ideas, /research-debate for GPT<->Claude review, /codex for execution; major directional changes always require the human's decision.
$MARK_END"
if [[ -f "$CLAUDE_MD" ]] && grep -qF "$MARK_START" "$CLAUDE_MD"; then
  grep -qF "$MARK_END" "$CLAUDE_MD" || { echo "ERROR: $CLAUDE_MD has $MARK_START but no $MARK_END; fix it by hand" >&2; exit 1; }
  NEWMD="$(BLOCK="$BLOCK" S="$MARK_START" E="$MARK_END" python3 -c '
import os, sys
t = open(sys.argv[1]).read(); s, e = os.environ["S"], os.environ["E"]
a = t.index(s); b = t.index(e, a) + len(e)
sys.stdout.write(t[:a] + os.environ["BLOCK"] + t[b:])' "$CLAUDE_MD")"
  if [[ "$NEWMD" == "$(cat "$CLAUDE_MD")" ]]; then
    SUMMARY+=("OK      $CLAUDE_MD research-workflow block up to date")
  elif [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] rewrite research-workflow block in $CLAUDE_MD to:"; printf '%s\n' "$BLOCK" | sed 's/^/    | /'
    SUMMARY+=("UPDATE  research-workflow block in $CLAUDE_MD")
  else
    printf '%s\n' "$NEWMD" > "$CLAUDE_MD"; echo "+ rewrote research-workflow block in $CLAUDE_MD"
    SUMMARY+=("UPDATE  research-workflow block in $CLAUDE_MD")
  fi
else
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] append to $CLAUDE_MD:"
    printf '\n%s\n' "$BLOCK" | sed 's/^/    | /'
  else
    mkdir -p "$CLAUDE_DIR"
    printf '\n%s\n' "$BLOCK" >> "$CLAUDE_MD"
    echo "+ appended research-workflow block to $CLAUDE_MD"
  fi
  SUMMARY+=("APPEND  research-workflow block -> $CLAUDE_MD")
fi

# 5. RESEARCH_KIT hint
DEFAULT_KIT="$(readlink -f "$HOME/research-workflow" 2>/dev/null || echo "$HOME/research-workflow")"
if [[ "$KIT" != "$DEFAULT_KIT" ]]; then
  WARNINGS+=("Kit is not at ~/research-workflow. Add to your shell rc:  export RESEARCH_KIT=\"$KIT\"")
fi

# 6. Summary
echo
echo "===== Summary ====="
for s in "${SUMMARY[@]}"; do echo "  $s"; done
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "===== Warnings ====="
  for w in "${WARNINGS[@]}"; do echo "  WARN: $w"; done
fi
[[ $DRY_RUN -eq 1 ]] && echo "(dry run: no changes were made)"
if [[ $SKIPPED -gt 0 ]]; then
  echo "ERROR: $SKIPPED item(s) NOT installed, see SKIP lines above (resolve them, then re-run)." >&2
  exit 1
fi
echo "Next: codex login; claude (login); then in a project run /research-workflow"
