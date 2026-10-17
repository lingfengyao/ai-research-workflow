# Brief: <topic title>

> 人填写（AI 可起草，人确认）。确认后 AI 不得修改 priority weights；任何修改必须 `## ESCALATE`。

- Date: YYYY-MM-DD
- Owner: <name>
- Topic slug: <topic-slug>

## 1. Idea
<相对宽泛但不太宽泛的 idea，2-5 句。来源：之前 research 的延伸 / 观察到的现象 / ...>

## 2. Project type
`paper` | `tool` | `startup`   <- 选一个

## 3. Priority weights（总和 = 1.0）
| criterion | weight | 说明 |
|---|---|---|
| novelty | 0.35 | paper 默认高 |
| potential impact | 0.30 | paper 默认高 |
| feasibility (compute/time/data) | 0.20 | |
| practicality | 0.15 | tool 默认最高 |
| user value / market | 0.00 | startup 默认最高 |

默认参考：paper = 0.35/0.30/0.20/0.15/0；tool = 0.10/0.20/0.25/0.45/0；startup = 0.10/0.15/0.20/0.15/0.40。

## 4. Target
- Venue / deadline: <e.g. CVPR 2027, abstract deadline YYYY-MM-DD>
- What success looks like: <一句话>

## 5. Constraints
- Compute: <GPU 型号 × 数量；GPU-hours budget>
- Hardware / devices: <...>
- Data / models available: <...>
- Time: <...>
- Escalation threshold for compute/money: <e.g. 任何新实验 > 8 GPU-hours 或任何付费支出>  ← 唯一阈值，所有 prompt 都引用这里
- Debate budget: <e.g. max 4 rounds；GPT/Claude token 或时间上限>

## 6. Things I (the human) decide personally
- [ ] core hypothesis
- [ ] threat model（安全类）
- [ ] target venue
- [ ] eval protocol / judge prompts / few-shot examples
- [ ] <其他>

## 7. Out of scope / not interested in
<明确不想做的方向，防止 AI 漂移到好 implement 的方向>

## 8. Prior context
<已有结果、失败尝试、相关 memory / notes 的路径>
