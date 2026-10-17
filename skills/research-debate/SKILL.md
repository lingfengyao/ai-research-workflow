---
name: research-debate
description: Run a structured research debate where Claude acts as Reviewer #2 and GPT (via Codex CLI) is the proposer/defender of a research proposal, with mandatory human escalation for directional decisions; also cross-checks experimental conclusions with GPT. Use when the user says /research-debate, "让GPT和Claude讨论", "让两个AI吵一架", "review my proposal", "帮我challenge这个idea", or wants GPT to cross-check experiment results.
---

# Research debate：Claude = Reviewer #2，GPT = Proposer / Defender，Human = PI

```
KIT=${RESEARCH_KIT:-$HOME/research-workflow}
GPT_TURN=$KIT/scripts/gpt_turn.sh
```

分工：
- **GPT**（Codex CLI，`gpt_turn.sh`）：写 literature review、proposal、references；回应 critique、修改 proposal。
  角色说明见 `$KIT/prompts/gpt_role_proposer.md`（新 session 时自动 prepend）。
- **Claude（你）**：Reviewer #2。重新 validate novelty、找遗漏的 existing works、challenge motivation /
  hypothesis / experimental design。清单见 `$KIT/prompts/claude_reviewer_checklist.md`。
- **Human PI**：所有 directional decision。你不替他做选择。

核心原则：
- **你也可能错。** GPT 拿出 evidence（可核实的 paper、逻辑、数据）时要明确 concede；不要为了"像 Reviewer #2"
  而硬挑刺。同样，不要因为 GPT 语气自信就放过。
- **两个 AI 都 agree ≠ 正确。** 最终总结必须列出 human 需要亲自核实的 key claims 和 papers。
- novelty 是最容易 hallucinate 的地方：你必须**自己**用 WebSearch / WebFetch 搜，不能只核对 GPT 给的列表。

## 0. 定位 / 创建 topic dir

Topic dir：`<project>/research/<topic-slug>/`（project 默认是当前工作目录对应的 repo 根或用户指定位置）。

如果不存在：
```bash
T=<project>/research/<topic-slug>
mkdir -p "$T/debate"
for f in brief proposal decisions references; do
  [ -e "$T/$f.md" ] || cp "$KIT/templates/$f.md" "$T/$f.md"
done
```
（`templates/review.md` 不复制到 topic 根目录，它是你每轮写 review 的模板。）缺 template 文件就报错停下，
不要自己编一个替代格式。

## 1. 确保 brief.md 填好（不能跳过）

brief.md 必须有：idea、**project type**（paper | tool | startup）、**priority weights**
（如 novelty / impact / feasibility / practicality）、venue/deadline、constraints（算力、硬件、时间）、
**PI 保留亲自决定的事项**。

缺 project type 或 priority weights → 用 AskUserQuestion 问 PI，不要自己猜。参考默认值供 PI 选：
- paper：novelty 与 potential impact 最高，feasibility 次之；
- tool / app：practicality 最高；
- startup：用户需求 / 市场 / 可落地性。

brief.md 由 PI 拥有，之后任何对 priority weights 的修改都是 mandatory escalation。

## 2. 生成初始 proposal（如果 proposal.md 还是空模板）

写 `debate/round-00-gpt-prompt.md`，让 GPT：读 brief.md → 做 deep literature review（web search，
每篇给 arXiv ID / DOI / URL）→ 写 `lit_review.md`、`references.md`、`proposal.md`（按模板结构：
motivation、hypothesis、related work & gap、contributions、experimental plan（metrics/baselines/
trials/seeds/compute/falsification criterion）、risks、Changelog）。然后：

```bash
$GPT_TURN -d "$T" -p "$T/debate/round-00-gpt-prompt.md" -o "$T/debate/round-00-gpt-response.md" --new -e high
```

如果 PI 已经有 proposal（自己写的或 GPT Deep Research 产出的），直接放进 proposal.md，从第 3 步开始。

## 3. Round loop（NN = 01, 02, ...；默认 max 4 rounds，PI 可改）

### 3a. Claude 写 review → `debate/round-NN-claude-review.md`
1. 读 brief.md、decisions.md、proposal.md、references.md、上一轮 GPT response，以及
   `diff proposal.v<N-1>.md proposal.md`（第一轮跳过 diff）。
2. **自己做 novelty search**：用 WebSearch（必要时 WebFetch 打开 arXiv/OpenReview 页面）搜核心 claim 的
   不同说法、相邻领域的叫法、最近 6–12 个月的 arXiv、workshop paper。
   - 体力活（收集候选 paper、整理 abstract、核对 arXiv ID 是否存在）可以派给便宜的 subagent
     （Agent tool，`model: sonnet` 或 `haiku`），但 **novelty 判断和 design critique 必须你自己做**。
   - 抽查 GPT 在 references.md 里标 `verified` 的条目（至少抽关键的 3 条）：链接打得开、标题作者对得上、
     paper 真的做了 GPT 说的事。你核实过的行把 `verified_by` 加上 `claude`；打不开的标 `unverified`，
     按准确标题搜过确认不存在才标 `not-found`，并作为 critique 提出。支撑核心 novelty / hypothesis 的引用全部要核。
3. 按 `$KIT/templates/review.md` 结构 + `$KIT/prompts/claude_reviewer_checklist.md` 逐项写：
   - critique 编号：major `M1, M2…`，minor `m1…`，questions `Q1…`。跨轮保持 ID 稳定，新的接着编号。
   - 每条 critique 给 **evidence**（paper + 链接、逻辑、或能 settle 它的实验）。没 evidence 的直觉要标明是直觉。
   - 上一轮的每个 ID 标状态 `resolved | conceded-by-reviewer | still-open | withdrawn`（见 templates/review.md）。
     `resolved` 必须指向证据（章节 / diff / reference）；**GPT 的 Rebut 成立就标 `conceded-by-reviewer`**。
   - 结尾给 verdict：`major issues remaining: <n>`。
   - 如果你认为需要 mandatory escalation 的改变（见第 4 节），写 `## ESCALATE` block，**本轮不发给 GPT**，
     直接进入第 4 节。

### 3b. 给 GPT 的 prompt → `debate/round-NN-gpt-prompt.md`
内容要点（短）：
```
Claude 的 review 在 debate/round-NN-claude-review.md。请：
1. 逐条回应每个 critique ID（Accept / Partially accept / Rebut + evidence），不要漏。
2. 需要时重新 web search；更新 references.md、lit_review.md。
3. 若修改 proposal：先 cp proposal.md proposal.v<next>.md，再改 proposal.md，并在 Changelog 记录 round NN 与对应 ID。
4. 遵守 brief.md 的 priority weights 和 decisions.md 中的决定；mandatory-escalation 类的改变只能写 ## ESCALATE block。
5. 按角色说明的 reply format 输出。
```
如果 PI 在上一轮做了决定，把 decisions.md 里新增那条原文贴进 prompt。

### 3c. 运行 GPT turn
```bash
$GPT_TURN -d "$T" -p "$T/debate/round-NN-gpt-prompt.md" -o "$T/debate/round-NN-gpt-response.md" [-e high]
```
- 有 `debate/.gpt_session` 时自动 resume 同一 GPT session（保留上下文）；需要换 model 或上下文太长时用 `--new`
  （会重新 prepend 角色说明，此时 prompt 里要提醒它先读全部 debate 文件）。
- 长 turn（effort high/xhigh、带 search 的通常 3–15 分钟）用 Bash `run_in_background: true`，**等完成通知，
  不要 sleep/轮询**。
- 非零 exit → 读 `debate/.events/<ts>.stderr.log` 找原因，修正后重跑；不要绕过脚本手工拼结果。
- 推荐 model/effort：debate 回应 `-e high`；简单整理 `-e medium`。单独的 idea evaluation 用
  `-m gpt-6.1-sol -e xhigh --ro --new --session-file debate/.gpt_session.ideaeval`（独立 session，不覆盖 debate session）。
- `-o` 已存在会报错（脚本从不覆盖）；重跑同一轮先把旧输出改名。失败重跑计入轮数，不重置 max rounds。
- exit 4 = GPT 改了受保护文件（brief.md / decisions.md / 你的 review / .gpt_session*）：看脚本打印的 diff，
  从 `.events/<ts>.protected/` 恢复，作为缺陷记录并告诉 PI。

### 3d. 读 GPT 的产出并检查
1. 读 `round-NN-gpt-response.md` 全文。
2. `diff -u proposal.v<N>.md proposal.md`：确认改动与它声称的一致，没有悄悄改 hypothesis / threat model /
   contributions / priority，没有为了"可行"偷偷削弱实验协议（trials、seeds、baselines、metrics、数据子集）。
   偷偷做了 mandatory-escalation 类改变 → 视为 escalation，回滚到 proposal.v<N>.md 并问 PI。
3. 受保护文件由 gpt_turn.sh 做 hash 校验（exit 4）；你另外看 summary 里的 `file_changes` 数和 events 里的
   file_change 路径，确认没写 topic dir 以外（sandbox 仍允许 /tmp、$TMPDIR）。
4. 累积漂移：对比 `proposal.v1.md` 与当前版本，多轮小改动合起来已构成方向 / main contribution 变化 → escalation。
5. 新增 reference 抽查（同 3a.2）。

### 3e. 判断是否停止
- 输出里有以 `## ESCALATE` 开头的行（gpt_turn.sh 会醒目打印）→ 第 4 节。
- 你下一轮 review 时已没有 remaining major issues → converged → 第 5 节。
- 达到 max rounds，或连续两轮没有新证据（只有措辞变化）→ 第 5 节，并在总结里列出未解决的分歧给 PI 裁决。
- 否则 NN+1，回到 3a。

## 4. Escalation（任一方触发都必须停下问人）

Mandatory triggers 与 block 格式：以 `$KIT/RESEARCH_WORKFLOW.md` 的 "ESCALATE 协议" 一节为准（canonical，
不在这里重复）。阈值统一看 brief.md §5 / §6；decisions.md 已授权的事项不重复升级。

步骤：
1. 停止 loop。
2. 用 **AskUserQuestion** 问 PI：一句话的问题；选项（每个附后果/成本）；GPT 的 recommendation；
   你的 recommendation；关键 evidence（带链接）。不要把你的偏好包装成唯一选项。
3. 把结果 append 到 `decisions.md`（按 `templates/decisions.md` 格式）：date、round、question、options、
   GPT recommendation、Claude recommendation、**HUMAN decision**、rationale（PI 原话）。
4. 若 PI 改了 brief（例如 priority），由 PI 确认后你再改 brief.md。
5. 下一轮 GPT prompt 里贴上这条 decision，继续 loop。

## 5. 结束：写 `debate/SUMMARY.md`

结构：
1. **Final position** — 当前 proposal 的一段话版本（problem、hypothesis、核心 contribution、主实验）。
2. **Resolved issues** — ID、结论、谁让步了、依据。
3. **Unresolved disagreements** — 双方立场 + evidence + 建议的 cheapest settling experiment / check；
   以及双方各自认为"仍可能推翻 proposal 的最强反例"。
4. **Human must verify personally** — 最关键的 novelty claims 与 3–8 篇 key papers（链接），以及
   每篇要看什么（"确认 X 没有做 physical-world 版本"）。注明 "两个 AI 同意 ≠ 正确"。
5. **Decisions log** — 指向 decisions.md 的条目。
6. **Recommended next step** — 例如 implementation plan → 交给 `/codex` skill 执行；或继续 literature check。
7. **Cost** — 轮数、GPT token usage（来自 gpt_turn.sh summary）。

然后向 PI 汇报 SUMMARY 的要点，并明确哪些是你亲自核实过的、哪些未核实。

## 6. Results review mode（cross-check 实验结论）

用于实验跑完后，让 GPT 独立审查结论是否成立（另一个 AI 的视角，不是盖章）。

1. 在 topic dir 下建 `results/<run-name>/`，放：实验 config、真实命令、raw metrics（json/csv）、关键日志片段、
   你写的 `claims.md`（每条结论编号 C1, C2…，附对应数字和文件）。
2. prompt 文件 `debate/results-<run-name>-gpt-prompt.md`：要求 GPT **独立**从 raw 文件重算/核对每个 claim，
   检查：样本量 / seeds / variance 与 significance、是否与 proposal 的 protocol 一致（trials、metric、数据子集、
   预算有没有被改）、baseline 是否公平、是否有 cherry-picking、LLM-as-a-judge prompt 是否会引入偏差、
   替代解释。对每条 C 输出 supported / weakened / unsupported + 理由。
3. 运行（skeptic 角色而不是 proposer；独立 session，不覆盖 debate 的 `.gpt_session`；只读，通常不需要 search）：
   ```bash
   $GPT_TURN -d "$T" -p "$T/debate/results-<run-name>-gpt-prompt.md" \
             -o "$T/debate/results-<run-name>-gpt-review.md" --new --ro --no-search -e high \
             --role "$KIT/prompts/gpt_role_skeptic.md" --session-file debate/.gpt_session.results
   ```
4. 你自己也独立核对一次，再比较两边的判断；分歧处说明谁对、依据是什么，无法判定的交给 PI。
5. LLM-as-a-judge evaluation prompts、multi-agent instructions、few-shot examples：**提醒 PI 亲自 review**，
   不要让任何 AI 单方面定稿——小的 prompt change 可能直接影响 experiment validity。

## 不做的事
- 不替 PI 做 directional decision，不改 brief.md 的 priorities（除非 PI 明确决定）。
- 不手工伪造 / 补写 GPT 的 response 文件；gpt_turn.sh 失败就修原因重跑。
- 不让 GPT 写 paper 正文全文；paper writing 走 "PI 先写 draft → AI refine → PI 逐句 review" 流程。
- 不把 "两个模型都同意" 当作结论成立的证据。
