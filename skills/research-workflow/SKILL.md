---
name: research-workflow
description: The user's end-to-end research workflow (idea -> literature review -> proposal -> GPT<->Claude debate -> human decision -> Codex experiments -> paper). Use when starting a new research idea or direction, planning a paper project, or when the user says "/research-workflow", "按我的科研流程", "开个新 topic".
---

# Research workflow (thin entry point)

1. Read `${RESEARCH_KIT:-$HOME/research-workflow}/RESEARCH_WORKFLOW.md` in full and follow its phases. If the file is missing, stop and tell the user (do not improvise a workflow).
2. Locate the topic dir `<project>/research/<topic-slug>/` (ask the user which topic if ambiguous; create it from `${RESEARCH_KIT:-$HOME/research-workflow}/templates/` for a new idea).
3. Determine the current phase from what exists in the topic dir:
   - pending `## ESCALATE` without an entry in `decisions.md` -> ask the human first, nothing else
   - no `brief.md` / brief incomplete -> Phase 0: fill brief with the user (project type, priority weights, what they decide personally)
   - `lit_review.md` missing, or `references.md` still the unfilled template -> Phase 1 literature review (GPT via `scripts/gpt_turn.sh`)
   - `proposal.md` missing or still the unfilled template -> Phase 2 proposal
   - proposal filled but no `debate/SUMMARY.md` (debate not converged / not summarized) -> Phase 3 `/research-debate`
   - no `go` entry for the current proposal version in `decisions.md` -> Phase 4 gate: ask the human (go / pivot / kill, scope, eval-asset approval)
   - go recorded, eval assets approved -> Phase 5 experiments via `/codex`
   - results verified -> Phase 6 writing (human drafts first); workstream / milestone done -> Phase 7 retro
   Tell the user which phase you think they are in before acting.

## Non-negotiable rules
- **Escalate directional changes.** Triggers and format: the "ESCALATE 协议" section of RESEARCH_WORKFLOW.md (canonical). Stop, ask the human, log the answer in `decisions.md`.
- **Verify novelty and references.** Every novelty claim and key reference must be checked (search + read); mark status in `references.md`. "Both AIs agree" is not proof; list key papers the human should read personally.
- **Human owns evaluation prompts.** LLM-as-a-judge prompts, multi-agent instructions (including this kit's `prompts/*.md` and `skills/*/SKILL.md`) and few-shot examples are written or reviewed line by line by the human; never change them silently.
- **Opus plans, Codex executes, Opus audits.** Execution goes through `/codex`; audit diffs, real commands and numbers. Defensive fallbacks or protocol changes (trials, seeds, budget, metrics, data subsets) are defects.
- **Human drafts the paper.** AI refines the user's draft and responds to their comments; never write the paper from scratch.
