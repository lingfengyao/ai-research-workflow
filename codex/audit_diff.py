#!/usr/bin/env python3
"""Flag added/removed diff lines that often indicate defensive or protocol-changing edits.
Heuristic only: every hit must be judged by the supervisor, not auto-rejected."""
import re, sys

ADDED = [
    ("broad-except", r"except\s*(Exception|BaseException)?\s*(as \w+)?\s*:"),
    ("swallow", r"^\s*(pass|continue)\s*(#.*)?$"),
    ("try", r"^\s*try\s*:"),
    ("silent-default", r"\.get\([^)]*,|getattr\([^)]*,[^)]*,|or\s+\[\]|or\s+\{\}|or\s+0\b"),
    ("existence-guard", r"os\.path\.exists|\.exists\(\)|hasattr\(|is None\s*:\s*return|if not \w+\s*:\s*return"),
    ("fallback-word", r"(?i)fallback|fall back|graceful|robust|safe_|best.effort"),
    ("mask-numeric", r"nan_to_num|isnan|isfinite|clamp\(|clip\(|\beps\s*="),
    ("fake-data", r"(?i)\b(mock|dummy|fake|placeholder|stub|hard.?coded)\b"),
    ("warnings-off", r"warnings\.(filterwarnings|simplefilter)|logging\.disable|2>/dev/null|\|\|\s*true"),
    ("protocol-knob", r"(?i)\b(seed|num_trials|n_trials|num_episodes|n_episodes|max_steps|epochs?|lr|learning_rate|batch_size|eps(ilon)?|alpha|num_iter|n_iter|split|threshold|success)\w*\s*[=:]"),
    ("subsample", r"\[:\s*\d+\s*\]|\[\s*:\s*\w+\s*\]\s*#|head\(\d+\)|random\.sample"),
    ("device-fallback", r"(?i)cuda.*else.*cpu|\"cpu\"|'cpu'"),
]
REMOVED = [
    ("removed-assert/raise", r"^\s*(assert\b|raise\b)"),
    ("removed-test", r"^\s*def test_"),
    ("removed-protocol-knob", ADDED[9][1]),
]

def main(path):
    hits, cur = [], None
    for line in open(path, errors="replace"):
        if line.startswith("+++ "):
            cur = line[6:].strip(); continue
        if line.startswith("--- "):
            continue
        if line.startswith("+"):
            for tag, pat in ADDED:
                if re.search(pat, line[1:]): hits.append((tag, cur, "+" + line[1:].rstrip()))
        elif line.startswith("-"):
            for tag, pat in REMOVED:
                if re.search(pat, line[1:]): hits.append((tag, cur, "-" + line[1:].rstrip()))
    if not hits:
        print("audit: no suspicious patterns flagged"); return
    from collections import Counter
    c = Counter(t for t, _, _ in hits)
    print("audit flags: " + ", ".join(f"{k}={v}" for k, v in c.most_common()))
    for tag, f, l in hits:
        print(f"[{tag}] {f}: {l[:200]}")

if __name__ == "__main__":
    main(sys.argv[1])
