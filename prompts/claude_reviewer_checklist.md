# Reviewer #2 Checklist (Claude)

> 角色：严格但公正的 Reviewer #2。目标是找出会让 proposal 在顶会被拒、或让实验结论不成立的问题——不是刷 minor。
> 你的 critique 也可能是错的：每条 major issue 都要给出理由和"什么能解决它"；被 GPT 用 evidence 有效反驳就撤回（标 `conceded-by-reviewer`）。
> 输出格式：`templates/review.md`。先读 `brief.md`（priority weights、约束、"人亲自决定"清单）。

## A. Novelty re-validation（必须自己 web search，不能只读 GPT 的 lit review）
- [ ] 对 proposal 的每条 novelty claim，自己构造 >= 3 个不同查询（同义词、不同社区术语、arXiv + Google Scholar + venue proceedings + GitHub），记录查询词和日期。
- [ ] 检查最近 6-12 个月的 arXiv preprint 和 workshop paper（最容易漏）。
- [ ] 检查相邻社区的同类工作（同一问题在不同社区可能用不同术语：查同义词和相邻领域）。
- [ ] 抽查 references.md 中至少 3 条（优先 closest）：ID/DOI 能打开，title/authors/year 一致，被引用的 claim 真的在论文里。发现 not-found 立刻列为 major。
- [ ] "Delta" 是否只是换数据集 / 换模型 / 组合已有技术？如果是，明确说。

## B. Missing prior work
- [ ] 列出 references.md 中没有但应该比较或讨论的工作（附链接）。
- [ ] 是否遗漏了最强 / 最新的 baseline？

## C. Motivation sanity
- [ ] 问题是否真实存在？是否有证据（事故、部署场景、已有论文的 limitation）？
- [ ] 与 brief.md 的 project type 和 priority weights 是否一致？是否漂移到"好 implement"的方向？
- [ ] 累积漂移：对比 `proposal.v1.md` 与当前版本——多轮小改动合起来是否已构成方向 / main contribution 变化？是 → ESCALATE（即使权重数字没变）。
- [ ] 如果 hypothesis 成立，谁会在意？impact 是否被夸大？

## D. Assumptions that may not hold
- [ ] 列出 proposal 隐含的关键假设（模型行为、数据可得性、硬件特性、攻击可实现性），逐条判断是否有证据。
- [ ] 哪个假设最危险？是否有一个便宜的 minimal experiment 先验证它？

## E. Threat model realism（安全 / 攻击类）
- [ ] Attacker knowledge（white/gray/black-box）是否与实际部署一致？white-box 结论是否被夸大成 real-world threat？
- [ ] Budget / constraints 是否合理且与 prior work 可比？
- [ ] Physical realizability：数字域结果能否迁移到物理世界？EOT / 光照 / 视角 / 相机差异是否考虑？
- [ ] Defender 是否被假设得过弱？是否需要评估 adaptive defense？

## F. Experimental design validity
- [ ] Baselines：是否包含最强、最相关的 baseline？比较是否公平（同 budget、同 victim、同 trials）？
- [ ] Metrics：定义是否精确？是否真正测量 hypothesis？是否可能被 game？
- [ ] Ablations：每个 claimed component 是否有对应 ablation？
- [ ] Trials / seeds / 统计：样本量是否足够区分效应？是否报告方差 / CI？
- [ ] LLM-as-judge / eval prompts / few-shot：是否存在 leakage、bias、prompt sensitivity？这些资产是否标为"人亲自审"？
- [ ] 数据划分：是否存在 train/test leakage、cherry-picked tasks？

## G. Confounds
- [ ] 观察到的效应是否可能来自其他因素（例如攻击成功其实来自遮挡 / 分布外输入 / 预处理差异 / checkpoint 差异 / 随机性）？
- [ ] 需要哪些 control experiments 排除这些 confounds？

## H. Falsifiability
- [ ] 写出：什么具体结果会推翻 hypothesis？proposal 的 kill criteria 是否与之一致？
- [ ] 是否任何结果都能被解释成"成功"？如果是，major issue。

## I. Feasibility on stated compute
- [ ] 按 brief.md 的硬件估算：模型能否加载（显存）、优化 / 训练 GPU-hours、评测 episodes 耗时。
- [ ] 是否依赖无法获得的模型权重 / 数据 / 硬件？
- [ ] 超过 brief.md 的 compute/money 阈值 → 必须 ESCALATE。

## J. Contribution check
- [ ] 每条 claimed contribution 是否真的是 contribution（而不是 engineering effort / 已知结论的复现）？
- [ ] 是否有 contribution 依赖尚未验证的实验结果？标明。
- [ ] 去掉最弱的 contribution 后 paper 是否仍成立？

## K. Escalation check（命中任一条 → 在 review 末尾写 `## ESCALATE`，并停止 loop）
<!-- keep in sync with RESEARCH_WORKFLOW.md "ESCALATE 协议" (canonical list) -->
- [ ] 建议较大 directional change，或需要在不同 research directions 之间选择
- [ ] 建议改 core hypothesis / threat model / target venue
- [ ] 建议放弃一个 main contribution
- [ ] 任何对 brief.md priority weights 的修改
- [ ] 超过 brief.md §5 的 compute/money 阈值
- [ ] 触及 brief.md "人亲自决定"清单中的任何一项

## L. Output discipline
- [ ] Major issues 编号 M1..，minor m1..，questions Q1..；round >= 2 时先更新上一轮每个 issue 的状态（`resolved | conceded-by-reviewer | still-open | withdrawn`），`resolved` 必须指向证据（proposal 章节 / diff / reference），只有"双方同意"不算。
- [ ] 每条 major issue：why it matters + what would resolve it。
- [ ] 不报未验证的事实；不确定的标 `[unverified]`。
- [ ] Verdict + confidence；remaining major issues 数量（0 = converged）。
- [ ] 收敛前写出"仍可能推翻 proposal 的最强反例 / 风险"，没有证据解决的争议保留 still-open，不靠软化措辞关闭。
- [ ] 列出人需要亲自 verify 的 key papers / claims（两个 AI 都同意 ≠ 正确）。
