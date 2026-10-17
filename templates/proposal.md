# Proposal: <title>  (v<N>)

> Author: GPT (via Codex). Reviewer: Claude (Reviewer #2). Decider: Human.
> 版本规则：header 的 `v<N>` = 当前版本号。修改前先 `cp proposal.md proposal.v<N>.md`（备份保留原版本号），再改 proposal.md 并把 header 升为 `v<N+1>`，在 §11 Changelog 加一行。所有引用必须在 references.md 中有条目。

- Version: v<N> | Date: YYYY-MM-DD

## 1. Motivation
<为什么重要；对 paper 写 impact，对 tool 写实用场景。>

## 2. Hypothesis
- H1: <可证伪的陈述>
- Falsified if: <什么结果会推翻 H1>

## 3. Closest prior work & delta
| ref id | work | what they do | our delta | evidence for delta (section / table) |
|---|---|---|---|---|
| R1 | | | | |

Novelty search evidence: <queries, sources, dates, top hits>

## 4. Contributions
1. <contribution> — type: new problem / method / finding / benchmark / system
2. ...

## 5. Threat model（安全 / 攻击类必填）
- Attacker goal:
- Attacker knowledge (white/gray/black-box):
- Capability & budget / constraints:
- Physical realizability:
- Victim models / systems:
- Defender assumptions:

## 6. Experiment plan
- Tasks / datasets / environments:
- Victim models:
- Baselines (and why each is the right comparison):
- Metrics (exact definitions):
- Ablations:
- Trials / episodes / seeds:
- Compute estimate (GPU-hours on stated hardware):
- Minimal first experiment (smoke-scale, answers the riskiest assumption first):

## 7. Risks & mitigations
| risk | likelihood | impact | mitigation |
|---|---|---|---|

## 8. Kill criteria
<什么结果 / 发现会让我们放弃这个方向>

## 9. Self-assessment against brief priorities
| criterion | weight | score (1-5) | justification |
|---|---|---|---|

## 10. Open questions for the human
<需要人决定的事项；方向性的写成 ## ESCALATE>

## 11. Changelog
| version | round | critique IDs | change |
|---|---|---|---|
| v1 | 00 | – | initial draft |
