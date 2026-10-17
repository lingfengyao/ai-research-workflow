#!/usr/bin/env bash
# Print a git tree hash of the current working tree (tracked + small untracked code files),
# using a temporary index so the user's index/branches are never touched.
set -euo pipefail
dir="$1"
cd "$dir"
tmp_index="$(mktemp)"; rm -f "$tmp_index"
export GIT_INDEX_FILE="$tmp_index"
if git rev-parse --verify -q HEAD >/dev/null; then git read-tree HEAD; else git read-tree --empty; fi
# tracked changes (modified + deleted)
git ls-files -m -d -z | xargs -0 -r git update-index --add --remove --
# untracked, not ignored, small text/code files only (skip datasets, checkpoints, videos)
git ls-files -o --exclude-standard -z \
  | python3 -c '
import sys, os
exts = {".py",".sh",".yaml",".yml",".json",".toml",".cfg",".ini",".md",".txt",".csv",".ipynb",".slurm",".sbatch"}
out = []
for p in sys.stdin.buffer.read().split(b"\0"):
    if not p: continue
    s = p.decode(errors="surrogateescape")
    if os.path.splitext(s)[1].lower() in exts and os.path.isfile(s) and os.path.getsize(s) < 1_000_000:
        out.append(p)
sys.stdout.buffer.write(b"\0".join(out))
' | xargs -0 -r git update-index --add --
git write-tree
rm -f "$tmp_index"
