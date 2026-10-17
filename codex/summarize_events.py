#!/usr/bin/env python3
"""Extract session id, the actual executed commands (ground truth, independent of Codex's own report),
and token usage from a `codex exec --json` event stream."""
import json, sys, os
run = sys.argv[1]
sid, cmds, usage, msgs = None, [], {}, []
for line in open(os.path.join(run, "events.jsonl"), errors="replace"):
    try: e = json.loads(line)
    except Exception: continue
    t = e.get("type")
    if t == "thread.started": sid = e.get("thread_id")
    elif t == "turn.completed":
        for k, v in (e.get("usage") or {}).items(): usage[k] = usage.get(k, 0) + v
    elif t == "item.completed":
        it = e.get("item", {})
        if it.get("type") == "command_execution":
            out = (it.get("aggregated_output") or "").strip().splitlines()
            tail = " | ".join(out[-3:])[:300]
            cmds.append(f"[exit={it.get('exit_code')}] {it.get('command')}\n      -> {tail}")
        elif it.get("type") == "agent_message":
            msgs.append(it.get("text", ""))
if sid: open(os.path.join(run, "session_id"), "w").write(sid)
open(os.path.join(run, "commands.txt"), "w").write("\n".join(cmds) + ("\n" if cmds else ""))
open(os.path.join(run, "messages.txt"), "w").write("\n\n".join(msgs))
json.dump(usage, open(os.path.join(run, "usage.json"), "w"))
