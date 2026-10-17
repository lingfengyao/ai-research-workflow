---
name: codex
description: Delegate execution work (implementing code, debugging, running experiments/evals, data processing, plotting) to the Codex CLI as a supervised executor, then audit its diff, commands and claims. Use whenever a research task needs more than a trivial edit or command, or when the user says /codex, "让codex做", "交给codex".
---

# Opus 规划 / 审查 + Codex 执行

角色分工：**你（Opus）是 PI + reviewer**，负责理解目标、拆解任务、写 spec、审查结果、决定下一步。
**Codex 是执行者**：便宜、能力强，但会 (a) 防御性编程掩盖失败，(b) 偏离研究目标去"让它跑通"。
所以每次委派都必须：清晰的 spec → 执行 → 独立审查 → 接受 / 返工 / 回滚。

工具都在 `~/.claude/codex/`：
- `run_codex.sh` 委派入口；`executor_contract.md` 自动注入给 Codex 的硬规则（禁止防御式/改实验协议）
- 每次运行产物在 `<workdir>/.codex_runs/<时间>-<name>/`：
  `SUMMARY.txt`（先看）`report.json`（Codex 自述）`changes.diff`（真实改动）`audit.txt`（可疑模式）
  `commands.txt`（真实执行过的命令和退出码，来自事件流，不是 Codex 自述）`messages.txt` `session_id`

## 0. 判断要不要委派
自己做：读少量代码、实验设计、结果分析与判断、≤10 行的小改动（写 spec 比改还贵时）。
委派：多文件实现、写脚本、调环境、跑实验/评测、数据处理、画图、大范围代码调查（`--ro`）。
省钱原则：你不要自己读大段日志/大文件——用 `tail`/`grep`，或让 Codex `--ro` 去调查并汇报。

## 1. 写 spec（最关键）
保存到 `<workdir>/.codex_runs/specs/<name>.md`。一个 spec 只做一个可验证的交付物；大任务拆成多轮。
目标（Goal）一定写"为什么"，Codex 偏离目标几乎都是因为只拿到了"做什么"。

```markdown
## Goal (research intent)
<这一步要回答的科研问题 / 为什么要做。成功的结果长什么样。>

## Context
<相关文件路径 + 行号、已有结论、之前失败过的尝试、环境：conda env 路径、GPU、数据位置>

## Task
1. ...
2. ...

## Invariants (must NOT change)
<评测协议、指标、episode/trial 数、seed、数据划分、checkpoint、攻击预算/约束、baseline 等；列具体变量名>

## Out of scope
<不许碰的文件/目录；不要做的"顺手优化">

## Acceptance (verifiable)
- 命令：`...`  期望：<输出/数值范围/文件存在>
- 冒烟规模：<例如 1 task × 2 episodes，不要跑全量>

## Stop and report (do not work around) if
- <例如 checkpoint 加载报错、显存不足、指标与预期差距 > X、发现 spec 与代码不符>
```

## 2. 执行
```bash
~/.claude/codex/run_codex.sh -C <git 仓库目录> -s <spec.md> -n <name> [--sandbox|--ro] [--net] [-e low|medium|high]
```
- 权限：
  - 默认 **full access**：可用 GPU、conda、`~/.cache`、网络。合同里已禁止它删数据/装包/动别的仓库/抢 GPU，
    但 spec 的 Invariants / Out of scope 仍要写清楚。
  - `--sandbox`：workspace-write 沙箱（无 GPU、只能写 workdir），纯改代码又担心误操作时用。
  - `--ro`：只读调查（"X 在哪计算的？为什么 Y？"），最便宜也最安全。
  - `--net`：仅在 `--sandbox` 下开网络。
- `-e`：默认用 config 的 medium；复杂调试用 high，机械改动用 low。
- 预计 >5 分钟：Bash 用 `run_in_background: true`，等完成通知，不要轮询。
- **长实验（>10–15 分钟）不要让 Codex 盯着**：让 Codex 写好脚本并跑冒烟测试；全量运行由你用
  `nohup ... > log 2>&1 &`（或 background Bash）启动，用 Monitor/定期 `tail` 看日志。
- `-C` 必须指向 git 仓库（你的各个代码仓库），否则无法捕获 diff。
  已有未提交改动没关系：diff 是运行前后快照对比，只包含本次改动。

## 3. 审查（每次都做，按顺序）
1. `SUMMARY.txt`：status、deviations、workarounds、open_issues。status=blocked 是好事，读原因。
2. **完整读 `changes.diff`**（不是只看 audit）。逐处问：这行改动是 spec 要求的吗？
3. `audit.txt` 每个命中都要判断：broad except / silent default / exists-guard / nan_to_num /
   改了 trials/seed/epochs / 删了 assert / 子采样 `[:N]` / cpu fallback / mock/dummy。
   判断标准：它是否可能让错误的实验**静默地产生数字**？是 → 必须返工。
4. 对比 `commands.txt`（真实）与 `report.json.commands_run`（自述）：声称跑过的命令真跑了吗？退出码一致吗？
   有没有失败后换了个更"宽松"的命令重跑？
5. **独立复现关键验收命令**（自己跑，或至少检查 evidence 指向的日志/文件里确实有那个数字）。
6. 目标对齐：结果是否真的回答了 Goal 里的科研问题？数值是否合理（对比 baseline / 论文 / 之前的运行）？
   "跑通了"≠"做对了"：检查核心改动是否真生效、关键开关是否真开启、评测是否用了正确 checkpoint 等。

## 4. 决策
- **Accept**：告诉用户结论 + 证据路径。
- **Revise**（同一 session 续做，保留上下文，便宜）：
  ```bash
  ~/.claude/codex/run_codex.sh -C <同一目录> -r <上一次 run_dir> -s <feedback.md> -n <name>-fix1 [同样的沙箱 flag]
  ```
  feedback 写成编号的具体指令，引用 `file:line`，说清楚"删除哪个 fallback / 恢复哪个参数 / 必须让它报错"。
- **Revert**：`git -C <workdir> apply -R <run_dir>/changes.diff`（仅当之后没有别的改动叠加）。
  注意：diff 只包含代码类小文件；Codex 新建的大文件/无扩展名文件要按 report 手动处理。
- **Take over**：剩下的改动很小或 Codex 反复偏离时，你直接改。
- 同一任务返工 3 轮仍不达标 → 停下来，带着具体分歧问用户，不要无限循环。

## 5. 向用户汇报
简短：做了什么、你**亲自验证过**的证据（命令/文件/数值）、你拒绝或修正了 Codex 的哪些东西、仍存在的风险。
不要原样转述 Codex 的自我总结。
