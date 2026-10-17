# ai-research-workflow

A human-in-the-loop research workflow for Claude Code + Codex CLI. GPT drafts and defends the research proposal. Claude reviews it as Reviewer #2. You make every directional decision.

## Install

```bash
git clone https://github.com/lingfengyao/ai-research-workflow.git ~/research-workflow
~/research-workflow/install.sh
codex login
```

Requires [Claude Code](https://claude.com/claude-code) and the [Codex CLI](https://github.com/openai/codex).

## Commands

| Command | What it does |
|---|---|
| `/research-workflow` | Start a new research topic, or continue an existing one from its current phase |
| `/research-debate` | Debate loop: Claude reviews the proposal, GPT responds and revises it. Stops and asks you before any directional change |
| `/codex` | Hand implementation and experiments to Codex; Claude audits the diff, the commands that actually ran, and the numbers |
| `scripts/gpt_turn.sh` | Run a single GPT turn by hand (see `-h`) |

## Usage

1. In your project, run `/research-workflow` and fill in `brief.md`: the idea, the project type (paper / tool / startup), your priorities, and the decisions you want to make yourself.
2. GPT runs a literature review with web search and writes `proposal.md`.
3. Run `/research-debate`. You make every decision that is escalated to you; they are logged in `decisions.md`.
4. Run experiments with `/codex`. Write or review the eval prompts and few-shot examples yourself.
5. Write the paper draft yourself; let AI only refine it.

Files for each topic go in `<project>/research/<topic>/`. See [RESEARCH_WORKFLOW.md](RESEARCH_WORKFLOW.md) for the full workflow.
