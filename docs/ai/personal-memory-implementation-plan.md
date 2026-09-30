# Personal Memory V1 实施计划

Status: Phases 0–3 implemented; this plan owns only deferred Phases 4–5.

Last reviewed: 2026-09-30.

## Document Contract

本文保留 Personal Memory 后续 promotion、retention 和 deterministic consolidation
的触发条件、范围与验收要求。已完成 Phases 0–3 的当前行为与契约由以下 SSOT 维护，
不再在实施计划中重复历史问题、模型清单和代码地图：

- [LifeOS Shell](../architecture/lifeos-shell.md#memory-runtime)：组合、访问策略和
  [当前恢复限制](../architecture/lifeos-shell.md#current-recovery-limits)。
- [AI Architecture](ai-architecture.md)：Host/Runtime 分工、Context 与确认写入。
- [Agent Runtime](../architecture/agent-runtime-current.md)：证据校验与恢复契约。
- [KnowledgeOS](../domains/knowledgeos-domain.md)：Note、Decision、Relation，
  Decision revisit conditions 及 Memory projection。
- [LifeOS Roadmap](../roadmap/roadmap-lifeos.md)：产品优先级与交付顺序。

V1 已具备统一 active-domain 访问策略、Evidence authority/provenance/temporal/lineage、
用户确认的 Personal Profile，以及 Decision/episode/pattern/guidance 分槽。Knowledge
没有独立 Principle 或 Assumption 实体；决策理由、预期结果和 revisit conditions
保存在当前 Decision，稳定个人规则由 Profile 管理。

后续阶段仍遵守既有边界：Host 拥有权限、存储、embedding 和领域语义；Rust 拥有
通用 Context/Evidence 安全语义。Agent Artifact 不自动写入长期 Memory。

确认 Memory 与 Profile 已有完整加密备份，共享历史清理保留它们；Memory 向量由召回
按需重建。它们仍不同步，具体恢复契约由 Shell SSOT 维护。该保护属于当前用户数据
能力，不代表延期 retention 已交付，也不改变 Phase 4–5 的质量证据触发条件。

Phase 4–5 只在 V1 的检索质量、Profile 修改率和重复/过时记录数据提供触发证据后
排期；架构完整性本身不是触发条件。

## 1. Phase 4 — Episodic Promotion And Retention

该阶段保持延期；只有实际检索质量和保留成本证据触发后才排期。

### 1.1 Retention Semantics

- `valid_until` 只表示事实何时不再成立。
- 新增 `retention_until` 表示何时允许自动清理。
- 用户确认、Profile、Knowledge Decision 和 source-fact records 不自动 TTL。
- 只有低权限 deterministic/model-derived episode、pattern、guidance 可设置 TTL。
- Maintenance 记录 privacy-safe rows-affected diagnostics，不记录内容。

### 1.2 Promotion Gate

各领域 indexer 负责自己的产品语义，并显式判断：

```text
isNovel
isImportant
isRelevantToGoal
isLikelyUsefulLater
```

- 确定性且高显著的事件可自动晋升为 derived episode。
- 需要 LLM 判断的晋升只能生成 candidate。
- Core 只提供 record/retention 合同，不实现 Finance/Health-specific thresholds。
- Agent 输出不能自动反复成为新 Agent Memory 的输入。

### 1.3 Exit Evidence

- 低价值 event 不生成长期 Memory。
- Retention cleanup 不删除用户确认或 source-fact records。
- `valid_until` 与 `retention_until` 的测试分别覆盖“停止召回”和“允许删除”。
- 重复执行 promotion/indexer 不增加重复 records。

## 2. Phase 5 — Deterministic Consolidation Pilot

首个 pilot 建议使用已有确定性趋势基础的 Health sleep baseline：

```text
raw Health source rows
  -> bounded monthly pattern
  -> deterministic-derived baseline memory
```

约束：

- Consolidator 只读取原始 source rows 或 source-fact events。
- Model-derived Memory 不能成为自动 consolidation 输入。
- 输出必须记录 source fingerprint、输入窗口和 algorithm version。
- 相同输入产生相同稳定 id 和 payload；重复运行幂等。
- Derived baseline 不能覆盖 user-confirmed Profile，只能作为低权限 context 或
  建议用户确认的 Profile candidate。
- Domain-specific consolidation 位于 owning domain，通过现有 DomainPack bootstrap /
  background seam 注册；core 不导入 feature。

在 pilot 证明重复率下降、context 质量不退化后，才考虑 Finance spend baseline 等
第二个真实 caller，并据此决定是否抽出更通用的 consolidator seam。

## 3. Deferred-Scope Non-Goals

本计划不扩展以下范围：

- 将 Drift、SQLite、vector index 或领域权限移入 `agent-runtime`。
- Runtime 自行决定 Finance/Health recall policy，或新增 runtime-side Memory DB。
- 所有聊天自动 embedding 后 top-k 注入。
- 通用跨域条件 DSL、规则引擎或自动调仓。
- AI inference 自动成为 authoritative Profile。
- Conversation checkpoint 或 Agent Artifact 自动晋升长期 Memory。
- 在 Sync E2EE 决策前同步 Personal Profile。

只有出现第二个真实 Host，或静态 Context Assembly 被实测证明不足时，才考虑在
`agent-core` 增加纯接口形式的 `MemoryProvider` / `MemoryQuery`。接口仍不得携带
NaviWealth 领域模型或存储实现。

## 4. Verification And Delivery Trigger

既有访问、Context、确认写入和备份契约继续使用所属 SSOT 与
[测试策略](../development/testing-strategy.md)中的现有测试。延期工作新增的验收范围为：

- Promotion/indexer 对同一输入幂等，低价值 event 不形成长期 Memory。
- Validity 与 retention 分别覆盖“停止召回”和“允许清理”的语义。
- 自动 retention 保留用户确认、Profile、Decision 与 source-fact records。
- Consolidation 保留源窗口、fingerprint、algorithm version 与稳定 identity。
- Model-derived Memory 不成为自动 consolidation 输入，也不覆盖确认的 Profile。
- 质量评估证明重复/过时上下文减少，且权限、证据和当前事实质量不退化。

量化证据包含 Profile correction、Memory proposal approval/rejection、重复召回率、
过时事实召回率、Context omission reason 与不支持证据的输出比例。只记录 aggregate
与稳定错误枚举，不记录用户事实、文本或标识符。

开始 Phase 4 前，在 LifeOS 路线图记录质量问题、测量基线和交付范围；Phase 5 在首个
领域 pilot 证明质量收益后推进。第二个真实 consolidator caller 出现后，才决定是否
抽出更通用的 seam。
