# Research Workflow：先让两个 AI 吵一架，再由人拍板

> 适用：Claude Code (Opus 5.5 主控) + Codex CLI (GPT) 的科研工作流。可移植：kit 根目录 `${RESEARCH_KIT:-~/research-workflow}`。
> 核心思想：GPT 写 proposal 并辩护，Claude 当 Reviewer #2 挑刺，**人只在关键 gate 介入并对最终结论负责**。
> Human-in-the-loop 不能省。两个 AI 都同意 ≠ 正确。
> 下文命令里 `KIT=${RESEARCH_KIT:-$HOME/research-workflow}`（install.sh 不会 export `RESEARCH_KIT`；kit 不在默认位置时自己在 shell rc 里 export）。

---

## 0. 原则 & 角色分工

| 角色 | 谁 | 负责 | 不负责 |
|---|---|---|---|
| **PI / Decider** | Human（我） | 选题、priority weights、方向选择、novelty 最终判断、eval prompt / judge prompt / few-shot、写 paper draft、结论是否成立 | 复制粘贴、跑命令、格式整理 |
| **Proposer / Defender / Executor** | GPT（只能通过 Codex CLI：`codex`，默认 `gpt-6-astra`） | literature review（`--search` 实时搜索）、写 `lit_review.md` / `references.md` / `proposal.md`、回应 review（用 evidence 反驳或修改）、执行实现 / 跑实验 | 做方向性决定、改 priority |
| **Orchestrator / Reviewer #2 / Auditor** | Claude Opus 5.5 | 驱动整个流程、Reviewer #2（独立 web search 复核 novelty）、写实验 spec、审查 Codex 产出、核实数字、向人汇报 | 替人做方向选择；汇报未验证的结论 |

硬规则：
1. **Opus plans & reviews, Codex executes**（沿用项目 CLAUDE.md）：实现代码 / 调试 / 跑实验 / 数据处理 / 画图默认通过 `/codex` skill 委派；≤10 行小改动或写 spec 比自己做更贵时 Opus 自己做。
2. Codex 的防御式编程（宽泛 `try/except`、静默 fallback、默认值）和为"跑通"而改实验协议（trials、seed、预算、指标、数据子集）**一律视为缺陷**，返工或回滚。
3. **ESCALATE 协议**（见 Phase 3 的 canonical 定义）：任何一方输出以 `## ESCALATE` 开头的行，loop 立即停止，Claude 用 AskUserQuestion 问人，人的决定写入 `decisions.md`。
4. 汇报只陈述亲自验证过的结论；未验证的显式标注 `[unverified]`。
5. 所有 novelty claim 必须附搜索证据（查询词 + 结果 + 日期）；没有证据的 novelty claim 视为不存在。

---

## 目录结构（每个 topic 一个目录）

```
<project>/research/<topic-slug>/
├── brief.md                 # Phase 0：人写（AI 可起草，人确认）
├── lit_review.md            # Phase 1：GPT deep literature review
├── references.md            # Phase 1+：引用表，带 verified_by / status
├── proposal.md              # Phase 2+：当前 proposal（GPT 是作者）
├── proposal.v<N>.md         # 历史版本（每轮修改前备份）
├── decisions.md             # 人的决定日志（escalation log）
└── debate/
    ├── round-00-gpt-prompt.md / round-00-gpt-response.md     # lit review + 初稿
    ├── round-01-claude-review.md
    ├── round-01-gpt-prompt.md   # 给 GPT 的指令（指向 review）
    ├── round-01-gpt-response.md
    ├── ...
    ├── .gpt_session         # proposer/debate session id（resume 用）
    ├── .gpt_session.results / .gpt_session.ideaeval   # 旁路 run 的独立 session
    ├── .lock                # gpt_turn.sh 运行中
    └── .events/<ts>.{jsonl,stderr.log,prompt.md,protected/}
```

模板在 `$KIT/templates/`：`brief.md`、`proposal.md`、`review.md`、`decisions.md`、`references.md`。
GPT 以 workspace-write 运行在 topic dir（codex sandbox 也允许写 /tmp、$TMPDIR）。`gpt_turn.sh` 在每轮前后对 `brief.md`、`decisions.md`、`debate/round-*-claude-review.md`、`debate/.gpt_session*` 做 hash 校验，有改动 → exit 4（原件在 `.events/<ts>.protected/`）。

---

## Phase 0 — Brief（人主导，~15 分钟）

目标：在 AI 开始之前把 **preference 写死**，防止 AI 漂移到"好 implement 但不是我想研究"的方向（还浪费 token）。

1. `for f in brief proposal decisions references; do [ -e <topic_dir>/$f.md ] || cp $KIT/templates/$f.md <topic_dir>/; done`
2. 填 `brief.md`：
   - **idea**：相对宽泛但不太宽泛（来源：之前的 research 延伸 / 观察到的有趣现象）。
   - **project type** 决定 priority weights（默认值，可改；改动必须由人做）：

     | type | novelty | impact | feasibility | practicality | user value / market |
     |---|---|---|---|---|---|
     | `paper` | **0.35** | **0.30** | 0.20 | 0.15 | – |
     | `tool` (app / toolbox) | 0.10 | 0.20 | 0.25 | **0.45** | – |
     | `startup` | 0.10 | 0.15 | 0.20 | 0.15 | **0.40** |

   - venue / deadline、compute 约束（GPU 型号 × 数量、显存）、硬件、数据可得性。
   - **"我要亲自决定的事"清单**（例如 threat model、target venue、是否上真实硬件 / 做用户实验）。
3. brief 一旦确认，AI 不得修改 priority weights；任何修改都要 ESCALATE。

---

## Phase 1 — Literature Review（GPT 主力，Claude 复核，人读关键论文）

### 1.1 GPT deep research（Codex + live web search，高 effort）
```bash
# round-00-gpt-prompt.md：读 brief.md，做 literature review，写 lit_review.md + references.md（+ proposal 初稿）
$KIT/scripts/gpt_turn.sh -d <topic_dir> -p <topic_dir>/debate/round-00-gpt-prompt.md \
    -o <topic_dir>/debate/round-00-gpt-response.md --new -e high
```
- **Codex `--search` ≠ Deep Research。** 先在 lit_review.md 登记检索范围（来源、日期窗口、同义词 / 相邻社区术语、引用追踪计划），并记录实际访问失败的页面；覆盖不足要写明，novelty 结论只在已检索范围内成立。
- 可选：在 ChatGPT 网页版跑 Deep Research，把结果粘贴进 `lit_review.md`，并把引用补入 `references.md`（status 先标 `unverified`）。
- lit_review.md 必须包含：taxonomy of existing works、每个子方向的 closest works、**research gaps 及其证据**（搜过什么、没找到什么）。

### 1.2 便宜模型做收集 / 整理
- 收集 BibTeX、整理表格、去重、补 arXiv ID：Claude subagent 指定 **Haiku 5.5 / Sonnet 5.5**（subagent 默认继承主模型，必须显式指定 model），或 Codex `-e low`。
- 不要用 Fable / xhigh 做格式整理。

### 1.3 Hallucination 规则（硬性）
- **每条 novelty claim**（"没人做过 X"）必须附：搜索查询词、搜索引擎/来源、日期、最接近的 3 篇结果及差异。否则视为 hallucination。
- **每条 reference** 验证：arXiv ID / DOI / URL 能打开；title + authors + year 与来源一致；被引用的 claim 确实出现在该论文中。`references.md` 的 `verified_by` 记录谁验证的（gpt / claude / human），`status` ∈ `verified | unverified | not-found`。打不开 / 无法访问 = `unverified`；只有按准确标题在 arXiv / Scholar / DBLP 搜过确认不存在才是 `not-found`，并立即从 proposal 删除。`unverified` 引用不得单独支撑 novelty / hypothesis claim；notes 列写被引用的 claim 及其在论文中的位置。
- Claude 在 Phase 3 用**自己的 web search 独立复核** novelty（不能只读 GPT 的 lit review）。
- **人亲自读 3-5 篇 closest prior works**（至少 abstract + method + experiments），在 `references.md` 标 `verified_by: human`。AI 说 novel ≠ 新大陆。

---

## Phase 2 — Proposal（GPT 写）

GPT 用 `templates/proposal.md` 写 `proposal.md`，必须包含：
1. Motivation（为什么重要；对 paper 是 impact，对 tool 是实用场景）
2. Hypothesis（可证伪；写出"什么结果会推翻它"）
3. **Closest prior work & delta**（3-5 篇，逐篇写差异，不能只说"they don't do X"而不给证据）
4. Contributions（每条标注类型：new problem / method / finding / benchmark / system）
5. Threat model（安全/攻击类 topic 必填：attacker knowledge、capability、budget/constraints、physical realizability、victim models）
6. Experiment plan：datasets/tasks、victim models、**baselines**、**metrics**、**ablations**、trials/seeds、compute 估算（GPU-hours，对照 brief 里的硬件）
7. Risks & mitigations
8. **Kill criteria**：什么情况下放弃这个方向
9. 与 brief.md priority weights 的自评打分
10. Open questions for the human；11. Changelog（version | round | critique IDs | change）

版本规则：header `v<N>` = 当前版本。修改前 `cp proposal.md proposal.v<N>.md`（备份保留原版本号），再改并升为 `v<N+1>`、加 Changelog 行（角色 prompt 要求 GPT 做；Claude 每轮检查）。

---

## Phase 3 — Debate（Claude = Reviewer #2 ↔ GPT = Defender）

入口：`/research-debate` skill（详细流程在 `skills/research-debate/SKILL.md`）。每轮：

1. **Claude review**：按 `prompts/claude_reviewer_checklist.md` 审 `proposal.md` + `references.md`，自己做 web search 复核 novelty，用 `templates/review.md` 格式写 `debate/round-<NN>-claude-review.md`。Major issues 编号 `M1..`，minor `m1..`，questions `Q1..`；跨轮 ID 稳定。
2. **GPT response**：Claude 写短指令 `debate/round-<NN>-gpt-prompt.md`（指向 review 文件），然后
   ```bash
   $KIT/scripts/gpt_turn.sh -d <topic_dir> -p <topic_dir>/debate/round-<NN>-gpt-prompt.md \
       -o <topic_dir>/debate/round-<NN>-gpt-response.md
   ```
   （没有 `debate/.gpt_session` 时自动 `--new` 并注入 `prompts/gpt_role_proposer.md`；之后 resume 同一 session。）
   GPT 必须逐条回应 M/m/Q：`Accept`（并修改 proposal）| `Partially accept` | `Rebut`（附 evidence：论文、数据、计算）。**不允许无证据的 capitulate**，也不允许无证据的坚持。
3. **Claude 检查 response**：GPT 的 rebuttal 证据是否成立（Claude 的 critique 也可能是错的——被有效反驳就标 `conceded-by-reviewer`）；proposal 是否真的改了（diff）；新引用是否进 references.md 并验证。Issue 状态：`resolved | conceded-by-reviewer | still-open | withdrawn`；`resolved` 必须指向证据（章节 / diff / reference），"双方同意"不算。
4. 检查 ESCALATE → 检查 stop condition → 下一轮。

### ESCALATE 协议（canonical；副本在 `prompts/gpt_role_proposer.md` §5、`prompts/gpt_role_skeptic.md`、`prompts/claude_reviewer_checklist.md` K——改这里要同步）
格式（双方通用，`templates/review.md` 同）：
```markdown
## ESCALATE
- Decision needed: <一句话>
- Options: A) ... B) ... C) ...
- Claude recommends: <option + 理由>
- GPT recommends: <option + 理由>
- Evidence: <论文 / 数据 / 链接>
- Impact on brief priorities: <...>
```
**必须 ESCALATE 的情况**：
- 较大的 directional change（包括多轮小改动累积成的方向变化）；在不同 research directions 之间做选择
- 改 core hypothesis / threat model / target venue
- 放弃一个 main contribution
- 任何对 `brief.md` priority weights 的修改
- 超过 brief.md §5 的 compute/money 阈值（默认建议：>8 GPU-hours 的新实验、任何付费 API / 硬件采购）
- brief.md §6 "我要亲自决定的事"清单中的任何一项

已被 `decisions.md` 中某条决定授权的事项不必重复 ESCALATE。

Claude 遇到 ESCALATE：停止 loop → AskUserQuestion（选项即 Options，附双方推荐）→ 人的回答写入 `decisions.md`（date / question / options / AI recommendations / HUMAN decision / rationale）→ 把决定传给 GPT 后再继续。

### Stop conditions
1. 出现 ESCALATE → 停，问人。
2. **Converged**：Reviewer 没有 remaining major issues（所有 M 都 resolved 或被有效 rebut）。
3. 达到 max rounds（默认 **4**，或 brief.md 的 debate budget）→ 停，向人总结 unresolved disagreements（每条：双方立场 + 证据 + Claude 的判断）。
4. 连续两轮没有新证据（只有措辞变化）→ 停，同 3。失败重跑的 turn 计入轮数，不重置。

### 最终 summary（给人）必须包含
- proposal 当前版本 + 每轮的主要变化
- unresolved disagreements + 双方各自认为"仍可能推翻 proposal 的最强反例"
- **人需要亲自 verify 的 key papers / claims 清单**（"Both AIs agree" is NOT proof）
- references.md 中仍为 `unverified` 的条目

---

## Phase 4 — Human Decision Gate

人决定（写入 `decisions.md`）：
- **Direction**：go / pivot / kill（对照 kill criteria）
- **Scope**：哪些 contributions 保留，哪些实验是 must-have / nice-to-have
- **Priorities**：是否调整 brief.md 权重（只有人能改）
- **Novelty 判断**：读完 closest works 后，自己判断 delta 够不够 venue 要求
- **Budget**：GPU-hours / 时间 / 是否上真机
- 要自己写 / 审的 prompt 资产清单（见 Phase 5）

**进入 Phase 5 的前提**：`decisions.md` 中有当前 proposal 版本的 go 记录，且本次要用的 eval / judge prompts、few-shot、multi-agent instructions、protocol 版本已被人批准（记录文件 + 版本）。这些资产之后有改动 → 原批准失效，重新审。

---

## Phase 5 — Experiments（Opus spec → Codex 执行 → Opus 审查）

沿用现有 `/codex` skill（`~/.claude/skills/codex/SKILL.md`，工具在 `~/.claude/codex/`）：
0. **先找可复用的东西**：实现前 Claude / Codex 可以上网找现成 skills / tools / repos。采用第三方 skill 或代码需要人 review（skill 本身就是一套 instructions）。
1. **Opus 写 spec**（`<repo>/.codex_runs/specs/<name>.md`）：Goal（写"为什么"）、Context、Task、**Invariants**、Out of scope、Acceptance、Stop-and-report。
2. **Codex 执行**：
   ```bash
   ~/.claude/codex/run_codex.sh -C <git repo> -s <spec.md> -n <name> [--sandbox|--ro] [-e low|medium|high]
   ```
   长实验（>10–15 分钟）：Codex 只写脚本 + 冒烟测试，全量由 Opus 用 background / nohup 启动并监控。
3. **Opus 审查**：SUMMARY.txt → 完整读 changes.diff → audit.txt → commands.txt vs report.json → 独立复现关键数字 → 目标对齐。Accept / Revise（`-r` resume）/ Revert / Take over；同一任务 3 轮返工不达标 → 问人。

### 人必须亲自写或逐字审的东西（小的 prompt change 可能直接毁掉 experiment validity）
- LLM-as-a-judge evaluation prompts、rubric
- eval prompts / task instructions（例如任务 instruction 集合）
- multi-agent collaboration instructions——包括本 kit 自己的 `prompts/*.md` 和 `skills/*/SKILL.md`：每次改动人逐行看 git diff 后再 commit
- few-shot examples
- eval protocol：success 定义、trials 数、seeds、数据划分、攻击预算/约束
这些文件改动必须在 `decisions.md` 留记录；AI 只能提议，不能直接改。

### Invariants（永不静默改变）
trials / episodes 数、seeds、扰动 / 攻击预算（若适用）、metrics 定义、数据子集、checkpoint、baseline 配置。任何改动 → spec 返工或 ESCALATE。

### 结果 cross-check（results-review debate round）
实验结果出来后跑一轮反向 debate：Opus 写 `results/<run>/claims.md`（只含亲自验证的数字 + 文件路径），GPT 用 **skeptic 角色**（不是 proposer）、独立 session 只读挑战结论（confounds、统计显著性、是否 cherry-pick、protocol 是否被改、是否真的支持 hypothesis）：
```bash
$KIT/scripts/gpt_turn.sh -d <topic_dir> -p <topic_dir>/debate/results-<run>-gpt-prompt.md \
    -o <topic_dir>/debate/results-<run>-gpt-review.md --new --ro --no-search -e high \
    --role $KIT/prompts/gpt_role_skeptic.md --session-file debate/.gpt_session.results
```
细节见 `/research-debate` 第 6 节。分歧写进 summary 交给人判断。

---

## Phase 6 — Writing（人先写，AI refine）

1. **人先写 draft**（至少 intro / method 的论证主线）。AI 不从头到尾写 paper。
2. AI refine：语言、结构、逻辑漏洞、related work 的覆盖（引用必须来自 references.md 的 `verified` 条目）。
3. 人**一字一句**看 AI 修改版；不满意直接在文本里留 comments（例如 `<!-- COMMENT: ... -->` 或 `[[ ... ]]`），让 AI 按 comments 继续改。多轮直到表达的是自己真正想说的。
4. 所有数字必须能追溯到实验产物（文件路径 / log），AI 不得"润色"数字。
5. 可选：Claude review 稿件（Reviewer #2 模式），GPT 回应——复用 Phase 3 流程。

---

## Phase 7 — Retrospective（把经验沉淀为 skills）

每个 workstream 结束（或每个里程碑）：
- 记录：哪些 AI 建议被证伪？哪些 hallucination 漏过了初筛？哪些 gate 太松/太紧？token 花在哪？
- 沉淀：通用经验 → 改 `RESEARCH_WORKFLOW.md` / `prompts/*.md` / `templates/*.md`；个人 preference（writing style、experimental workflow）→ 新 skill 或 memory。
- 根据实际效果 refine skills（例如 reviewer checklist 加一条漏掉的检查项），git commit kit 并在新机器 pull。

---

## 8. Model selection & cost

| 任务 | 首选 | 备注 |
|---|---|---|
| Orchestrator、Reviewer #2、审查 Codex、结果判断 | **Claude Opus 5.5**（默认） | 个人体验有时比 Fable 更靠谱 |
| 最难的 novelty evaluation、research design 卡住时 | Claude Fable 5.1 | 只在 Opus 判断不了时用；贵 |
| Literature 收集、BibTeX、表格整理、去重、格式化 | **Sonnet 5.5 / Haiku 5.5 subagent** | subagent 默认继承主模型——**必须显式指定 model** |
| GPT literature review、proposal、debate 回应 | `gpt-6-astra`（Codex 默认），`-e high` | `gpt_turn.sh -e high` |
| Idea evaluation、讨论 research topic | `gpt-6.1-sol`，`-e xhigh` | `gpt_turn.sh -m gpt-6.1-sol -e xhigh --session-file debate/.gpt_session.ideaeval` |
| 实现 / 跑实验 | `gpt-6-astra` via `run_codex.sh`，`-e medium`（复杂调试 high） | |
| 机械改动（rename、格式、小修） | Codex `-e low` 或 Haiku | |

Cost 规则：
- UltraCode / multi-agent workflows 会自己 launch 多个同模型 subagents，token 消耗非常快。不是所有任务都需要最强模型。
- 并行 subagents 前先问：这个子任务需要推理还是只需整理？整理 → Haiku/Sonnet。
- Debate 默认 max 4 轮；每轮 Claude review 聚焦 major issues，不刷 minor。
- 不要让 Opus 自己读大段日志 / 大文件：`tail` / `grep`，或 Codex `--ro` 调查。

---

## 9. Human-in-the-loop checkpoints

| Gate | 谁决定 | Artifact | 检查什么 |
|---|---|---|---|
| G0 Brief | Human | `brief.md` | project type、priority weights、约束、"我要亲自决定"清单 |
| G1 Literature | Human（读论文）+ Claude（复核） | `lit_review.md`、`references.md` | 3-5 篇 closest works 亲自读；引用 status；novelty 证据 |
| G2 Escalation（随时） | Human | `decisions.md` | 方向变化、方向选择、hypothesis/threat model/venue、priority 修改、大 compute |
| G3 Post-debate | Human | `proposal.md` + debate summary | go/pivot/kill；scope；需人 verify 的 claims |
| G4 Eval assets | Human（自己写/逐字审） | judge/eval prompts、few-shot、protocol、multi-agent instructions（含 kit 的 `prompts/*.md`、`skills/*/SKILL.md`） | 是否测的是想测的；是否有 leakage / bias；批准记录到 decisions.md |
| G5 Results | Human | 结果摘要 + results-review round | 数字可追溯；confounds；结论是否真成立 |
| G6 Paper | Human（逐字） | draft + AI 修改版 | 是不是自己想说的；引用 verified；数字一致 |
| G7 Retro | Human | kit 的 git diff（skills / prompts / templates） | 经验是否沉淀；prompt / skill 改动逐行看过再 commit |

---

## 10. 红线 / Anti-patterns

- [X] 相信 AI 的 "this is novel / nobody has done this" —— 必须有搜索证据 + 人亲自读 closest works。
- [X] 让 AI 选"好 implement"的方向 —— 方向由 brief.md priorities + 人决定。
- [X] 接受 silent fallback / 宽泛 try-except / 默认值掩盖失败 —— 返工。
- [X] 为了"跑通"改 trials / seeds / budget / metrics / 数据子集 —— 返工或回滚。
- [X] "两个 AI 都 agree，所以对" —— agreement 不是 evidence；列出需人 verify 的点。
- [X] 报告里出现未验证的数字或引用 —— 标 `[unverified]` 或删掉。
- [X] AI 改 eval prompts / judge prompts / few-shot 而没有人审。
- [X] AI 从头写 paper。
- [X] Debate 无限循环 —— max rounds 到了就总结给人。
- [X] 所有事情都上最贵的模型 / UltraCode。

---

## 11. Quick-start cheat sheet

```bash
KIT=${RESEARCH_KIT:-$HOME/research-workflow}
TOPIC=<project>/research/<topic-slug>

# 新 topic
mkdir -p $TOPIC/debate
for f in brief proposal decisions references; do [ -e $TOPIC/$f.md ] || cp $KIT/templates/$f.md $TOPIC/; done
$EDITOR $TOPIC/brief.md                      # 人填 brief（G0）

# Phase 1：GPT literature review + proposal 初稿（新 session，高 effort，带 web search）
cat > $TOPIC/debate/round-00-gpt-prompt.md <<'P'
Read brief.md. Do a deep literature review with live web search. First record the search scope in
lit_review.md (sources, date window, synonyms, citation tracing). Write lit_review.md and references.md
following the kit templates; every novelty/gap claim must cite search evidence (queries, dates, closest hits).
Then fill proposal.md following the kit's templates/proposal.md structure (v1, Changelog row).
P
$KIT/scripts/gpt_turn.sh -d $TOPIC -p $TOPIC/debate/round-00-gpt-prompt.md \
    -o $TOPIC/debate/round-00-gpt-response.md --new -e high

# 手动跑一轮 GPT 回应（先写好 round-01-claude-review.md 和 round-01-gpt-prompt.md）
$KIT/scripts/gpt_turn.sh -d $TOPIC -p $TOPIC/debate/round-01-gpt-prompt.md \
    -o $TOPIC/debate/round-01-gpt-response.md

# 用 sol + xhigh 做 idea evaluation（只读，独立 session，不覆盖 debate session）
$KIT/scripts/gpt_turn.sh -d $TOPIC -p <prompt.md> -o <out.md> -m gpt-6.1-sol -e xhigh --ro \
    --new --session-file debate/.gpt_session.ideaeval

# Phase 5：委派执行（shell 版；Claude Code 里用 /codex）
~/.claude/codex/run_codex.sh -C <repo> -s <spec.md> -n <name> [--sandbox|--ro] [-e high]
```

在 Claude Code 里（不是 shell）：`/research-workflow` 开 topic / 判断当前 phase；`/research-debate <topic_dir>` 跑 Phase 3 循环；`/codex` 委派执行。
