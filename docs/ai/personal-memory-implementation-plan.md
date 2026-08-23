# Personal Memory V1 实施计划

Status: V1 implemented (Phases 0–3); Phases 4–5 deferred.

## Document Contract

本文定义 NaviWealth Personal Memory V1 的交付范围、实施顺序、迁移边界和
验收证据。它不拥有跨域架构、Memory Runtime 当前行为、AI wire contract、
KnowledgeOS 决策语义或产品优先级；发生冲突时分别以以下 SSOT 为准：

- [`lifeos-architecture-northstar.md`](../architecture/lifeos-architecture-northstar.md)
- [`lifeos-shell.md`](../architecture/lifeos-shell.md)
- [`ai-architecture.md`](ai-architecture.md)
- [`ai-protocol.md`](ai-protocol.md)
- [`agent-runtime-current.md`](../architecture/agent-runtime-current.md)
- [`knowledgeos-domain.md`](../domains/knowledgeos-domain.md)
- [`roadmap-lifeos.md`](../roadmap/roadmap-lifeos.md)

Phases 0–3 的稳定行为已经写回对应 SSOT。本文保留交付范围、验收矩阵和后续
Phases 4–5 的计划，不作为第二份当前架构定义；发生差异时始终以对应 SSOT 为准。

## 1. Outcome

Personal Memory V1 的目标不是扩大向量库，而是建立一个可纠正、可追溯、
有时间语义且服从领域权限的个人模型：

```text
NaviWealth Host

PersonalProfileStore ── PersonalProfileSnapshot
KnowledgeDecision    ── Decision Memory projection
MemoryRuntime        ── Episodes / patterns
EventStore           ── Recent events
Domain repositories  ── Current state
                               │
                               ▼
                     LifeContextAssembler
                               │
                      ContextBlock[]
                               │
───────────────────────────────┼──────────────
                               ▼
agent-runtime
validate / evidence semantics / temporal filter / budget / hash / snapshot
```

边界保持为：

> `agent-runtime` 拥有 Evidence/Context 的通用安全语义；NaviWealth Host
> 拥有 Personal Profile、Memory、Decision、存储、权限和 consolidation。

V1 不向 Rust 移动 Drift、SQLite、embedding、领域权限或 Finance/Health
业务模型，也不新增 runtime 主动召回。

## 2. Pre-Implementation Baseline And Resolved Gaps

现有实现已经具备以下基础，不应重复建设：

- `MemoryRecord` 已区分 semantic、procedural、episodic 和 event，并带有
  `validFrom` / `validUntil`。
- `MemoryRuntime.supersede` 会结束旧记录的有效期并保留历史。
- `propose_memory -> memory_candidates -> user approval -> memories` 已支持
  create、supersede、forget、reject、retry 和 undo。
- Conversation checkpoint 与长期 Memory 已明确分离。
- App-level Context Assembler 已对自动注入的 memory 和 recent events 应用
  active `DomainPack.memorySourcePrefixes` allow-list。
- KnowledgeOS Decision 已保存 question、options、selected option、rationale、
  assumptions、expected/actual outcome、review date 和 lifecycle，并投影为
  Memory Runtime 记录。

本次 V1 已解决的主要缺口：

1. `build_context` 和 `query_memory` 主动工具召回没有复用 active-domain
   allow-list；自动注入与主动召回存在权限差异。
2. `source` 同时承担业务来源和 provenance，ContextBlock 又统一标记为
   `domain_indexed`，无法区分用户确认、源事实、确定性派生和模型派生。
3. `related_decisions` 当前实际接收所有 episodic records，不只是 Decision。
4. 没有独立、无 embedding、稳定进入上下文的 Personal Profile。
5. Supersede 有时间边界，但没有显式 lineage pointer。
6. `valid_until` 表示事实有效期，不能同时承担 retention/TTL。

## 3. Delivery Scope

V1 在 Phase 3 完成后即可发布：

| Phase | Outcome | Release role |
|---|---|---|
| 0 | 统一 active-domain Memory 访问策略 | 已完成 |
| 1 | Evidence authority、provenance、temporal 和 lineage 语义 | 已完成 |
| 2 | Personal Profile V1、用户确认和 Context 注入 | 已完成 |
| 3 | Decision Memory 分槽和 assumption/review context | 已完成 |
| 4 | Episodic promotion 与 retention | 发布后增强 |
| 5 | Deterministic consolidation pilot | 质量验证后增强 |

Phase 4–5 应依据 V1 的检索质量、Profile 修改率和重复/过时记录数据再排期，
不能只因架构完整性自动进入开发。

## 4. Phase 0 — Memory Access Boundary

### 4.1 Problem

`app_chat_context_assembler.dart` 已使用 active domain source prefixes，但
`BuildContextTool` 和 `QueryMemoryTool` 直接调用 `ContextBuilder` /
`MemoryRuntime`，未传入同一 allow-list。`ProposeMemoryTool` 读取 supersede /
forget target 时也只校验 owner。

### 4.2 Changes

- 在 domain-neutral core 中增加 `MemoryAccessPolicy`，默认 deny-all。
- App composition 根据 `activeDomainPacksProvider` 生成允许的 source prefixes。
- 自动 Context Assembly、`build_context`、`query_memory`、`propose_memory`
  target lookup 和 proposal apply 全部复用同一个 policy。
- Apply 时重新读取当前 policy；用户确认前若领域被关闭，操作必须 fail closed。
- 直接面向用户的 Memory/Profile 管理页可以显示本地数据，但 AI recall 和 AI
  proposal 必须服从 active-domain policy。

### 4.3 Exit Evidence

- HealthOS 关闭后，Health memory/event 在自动 context、`build_context` 和
  `query_memory` 中均不可见。
- 猜测 inactive-domain memory id 不能 supersede 或 forget。
- 切换领域启用状态后无需重启即可生效。
- FinanceOS recall 保持可用。

## 5. Phase 1 — Evidence Semantics

### 5.1 Host Contracts

增加 domain-neutral 数据可信度与来源合同：

```text
EvidenceAuthority
  user_confirmed
  source_fact
  deterministic_derived
  model_derived
  legacy_unknown

EvidenceProvenance
  source
  source_id
  source_event_id
  candidate_id
  algorithm_version
  observed_at
```

`user_confirmed` 表示高可信数据，不表示 instruction。任何 Memory、Profile、
Resource 或外部内容都不能通过 authority 获得指令权限。

扩展 `MemoryRecord`：

- `authority`
- `provenance`
- `role`: `decision | episode | pattern | guidance | legacy`
- `supersedesId`

保留现有 `MemoryKind` 作为记忆本体分类；`role` 用于 Context 分槽，避免
把所有 episodic records 都称为 Decision。

### 5.2 Persistence And Migration

- 为 `memories` 增加 authority、provenance JSON、role 和 supersedes id。
- 既有行统一标记 `legacy_unknown`，不根据自由字符串 `source` 猜测 authority。
- 各 domain indexer 在重新索引时显式写入正确 authority 和 role：
  - Knowledge Decision 等源表镜像：`source_fact / decision`
  - 领域事件和历史片段：`source_fact / episode`
  - Health trend 等确定性计算：`deterministic_derived / pattern|guidance`
  - LLM Agent 产物：`model_derived / episode|guidance`
  - 用户确认的 AI proposal：`user_confirmed`
- Supersede 时旧行写 `valid_until`，新行通过 `supersedes_id` 指向旧行。
- Forget 继续物理删除正式 record 与 embedding；undo 使用现有受限本地 undo
  payload 恢复，不把被忘记内容长期保留在另一份正式表中。

### 5.3 Runtime Contract

在 standalone `agent-runtime` 增加可选通用合同：

```text
ContextEvidence {
  authority
  provenance
  valid_from
  valid_until
  supersedes
}
```

同时增加 generic `profile` ContextBlock kind。Runtime 负责：

- 校验时间区间和 evidence enum。
- 过滤已失效或被同批 block supersede 的 evidence。
- 为 profile evidence 提供有上限的保留预算，但仍低于 instruction authority。
- 在 `ContextSnapshot` 中记录 `expired`、`superseded`、`over_budget` 等省略原因。
- `evidence` 保持可选，以便不需要可信度元数据的通用 Host context 继续使用同一合同。

实现顺序为：agent-runtime schema/fixture/tests → Dart mapping → Host assembly/tests。

### 5.4 Exit Evidence

- Context metadata 不再统一硬编码为 `domain_indexed`。
- Expired evidence 在 Host 和 Runtime 两层均不能进入 provider request。
- `ignore previous instructions` 出现在 user-confirmed Profile 中仍只按 evidence
  渲染。
- 领域 indexer 重建的记录具有明确 authority；未知来源保持 `legacy_unknown`。

## 6. Phase 2 — Personal Profile V1

### 6.1 Data Model

新增无 embedding 的 Host-owned `personal_profile_facts`：

```text
PersonalProfileFact {
  id
  owner_user_id
  kind                 // goal | preference | constraint | rule
  key
  value_json
  summary
  domain_scope         // null = global
  authority
  provenance_json
  confidence
  confirmed_at
  valid_from
  valid_until
  supersedes_fact_id
  created_at
  updated_at
}
```

建议代码位置：

```text
apps/mobile/lib/core/lifeos/personal_profile/
  personal_profile_fact.dart
  personal_profile_store.dart
  personal_profile_snapshot.dart
  providers.dart

apps/mobile/lib/app/agent_runtime/context/
  app_personal_profile_context.dart

apps/mobile/lib/features/settings/
  personal_memory/
```

### 6.2 Store Rules

- Profile 不生成 embedding，也不通过 semantic top-k 召回。
- 同一 `owner + domain_scope + kind + key` 只能有一个当前有效事实。
- Supersede 必须在一个数据库事务内结束旧事实并创建新事实。
- Snapshot 只返回在当前时间有效、未 supersede、且属于 active domain 或 global
  的 facts。
- Snapshot 使用确定性排序和严格 fact/token 上限；冲突 active facts 必须暴露
  diagnostics，不能静默 last-write-wins。
- V1 Profile kinds 只包括 goal、preference、constraint 和 rule。确定性 baseline
  先作为 derived pattern/current state，不自动升级为 authoritative Profile。

### 6.3 Write Paths

用户在 Settings 直接创建或编辑 ProfileFact，视为明确确认并写
`authority=user_confirmed`。

AI 只能走候选路径。扩展现有 candidate 协议：

- `target_type = memory | profile_fact`
- 使用 generic `target_record_id`
- `propose_memory` 使用 `record_type` 和 `profile_kind`
- Apply/undo 继续执行 owner、terminal status、target identity、重复确认和目的地
  冲突检查

Model-derived inference 不能直接写 Profile；即使 confidence 很高，也必须先展示
候选并由用户确认。

### 6.4 Context Assembly

- `PersonalProfileSnapshot` 每轮都由 Host 组装。
- 每个 fact 映射为独立 `ContextBlock(kind=profile)`，便于 runtime 精确预算、
  snapshot 和 omission trace。
- Profile blocks 优先于 retrieved decision/episode/event，但仍是
  `trusted_as_instruction=false`。
- Current net worth、HRV、todo count、cashflow 等继续作为 live resource/current
  state，不写入 Profile。
- App Context Assembler 继续分别组装 Profile、Memory、Events、Current State 和
  Conversation Checkpoint，不创建统一的“大记忆库”。

### 6.5 Portability

V1 Profile 不进入 Sync v3。原因是它包含跨域敏感个人信息，而当前 Sync E2EE 尚未
完成产品决策。

但用户维护的 Profile 必须进入加密 Backup：

- 允许 Backup registry 注册 backup-only、非 syncable 表。
- Restore 不写 Sync outbox。
- Profile backup/restore 必须覆盖 authority、provenance、validity 和 lineage。
- Memory embeddings、events 和 model-derived cache 仍可保持可重建/local-only。

### 6.6 Exit Evidence

- 用户可查看、创建、编辑、supersede 和删除 Profile facts。
- 中英文 ARB 同步，Web 可管理 Profile，但 Web 不加载 AI runtime。
- Profile 不依赖 embedder 是否安装或可用。
- AI proposal 未确认前不改变 Snapshot。
- 关闭一个 optional domain 后，其 Profile facts 保留在本地但不进入 AI context。
- 加密 backup/restore 后 Profile 精确恢复。

## 7. Phase 3 — Decision Memory

### 7.1 Source Of Truth

不新增 `decision_memories` 真值表。`knowledge_decisions` 继续是唯一业务真值；
Memory Runtime record 只是可删除、可重建的 cross-domain retrieval projection。

### 7.2 Knowledge Decision Changes

- 增加可选、用户可编辑的 `revisit_conditions`。
- 条件首版保存为结构化 statement + source references，不实现通用指标 DSL 或
  跨域规则引擎。
- 更新 Knowledge Decision UI、repository、sync serialization 和 proposal path。
- Agent 可以建议 review，但不能自动改写 Decision、Profile 或业务状态。

### 7.3 Projection And Retrieval

Decision projection 必须写入：

- `authority=source_fact`
- `role=decision`
- question、完整 options、selected option、rationale
- linked principles/assumptions
- expected outcome、actual outcome、review date、status
- revisit conditions
- source row identity 和更新时间 provenance

Context Builder 分为：

```text
personal_profile
related_decisions
related_episodes
derived_patterns
derived_guidance
recent_events
related_events
```

历史 Decision 即使 superseded 仍可用于“当时为什么”类查询，但当前建议必须明确
读取 Decision status、当前 Profile 和 live Current State。

### 7.4 Exit Evidence

- 非 Decision episodic records 不再进入 `related_decisions`。
- KnowledgeOS 关闭后，Decision projection 在自动和主动 recall 中均不可见。
- Decision 更新后 projection 幂等覆盖；soft delete/merge 后旧 projection 清理。
- Agent 能识别“过去 Decision 的假设与当前状态不一致”，只建议 Review，不自动
  执行业务变更。

## 8. Phase 4 — Episodic Promotion And Retention

该阶段在 V1 发布后实施。

### 8.1 Retention Semantics

- `valid_until` 只表示事实何时不再成立。
- 新增 `retention_until` 表示何时允许自动清理。
- 用户确认、Profile、Knowledge Decision 和 source-fact records 不自动 TTL。
- 只有低权限 deterministic/model-derived episode、pattern、guidance 可设置 TTL。
- Maintenance 记录 privacy-safe rows-affected diagnostics，不记录内容。

### 8.2 Promotion Gate

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

### 8.3 Exit Evidence

- 低价值 event 不生成长期 Memory。
- Retention cleanup 不删除用户确认或 source-fact records。
- `valid_until` 与 `retention_until` 的测试分别覆盖“停止召回”和“允许删除”。
- 重复执行 promotion/indexer 不增加重复 records。

## 9. Phase 5 — Deterministic Consolidation Pilot

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

## 10. Explicit Non-Goals

V1 不实施：

- 将 Drift、SQLite、vector index 或 embedding model 移入 `agent-runtime`。
- Runtime 主动决定 Finance/Health recall policy。
- `MemoryProvider` trait 或 runtime-side Memory DB。
- 所有聊天自动 embedding 后 top-k 注入。
- 通用跨域条件 DSL、规则引擎或自动调仓。
- AI inference 自动成为 authoritative Profile。
- Conversation checkpoint 自动晋升长期 Memory。
- 在 Sync E2EE 决策前同步 Personal Profile。

只有出现第二个真实 Host，或静态 Context Assembly 被实测证明不足时，才考虑在
`agent-core` 增加纯接口形式的 `MemoryProvider` / `MemoryQuery`。即使触发，该接口也
不能携带任何 NaviWealth 领域模型或存储实现。

## 11. End-To-End Acceptance Scenario

以现金缓冲为 V1 的跨域验收场景：

1. 用户确认 ProfileFact：`cash_buffer_months = 12`。
2. Knowledge Decision 记录“继续持有高杠杆暴露”，前提为现金缓冲至少 12 个月。
3. Finance Current State 返回当前现金缓冲为 8 个月。
4. Context 同时包含 user-confirmed Profile、source-fact Decision 和 live state。
5. Agent 输出“原假设已不成立，建议 Review”，不得声称已经调仓或修改 Decision。
6. 将 Profile 由 12 supersede 为 9 后，只有 9 作为当前事实进入 context；旧值保留
   temporal lineage，并可在 proposal undo 窗口内恢复。
7. Forget 当前 Profile 后，正式 fact 不再召回；在 undo 窗口内可以恢复。
8. 关闭 KnowledgeOS 后，Decision 在自动注入、`build_context`、`query_memory`
   中均不可见。
9. Memory 内容包含 `ignore previous instructions` 时仍只能作为 evidence。
10. 加密 backup/restore 后 Profile 完整恢复，且不会产生 Sync outbox row。

## 12. Verification Matrix

### Mobile Unit And Integration

- `MemoryAccessPolicy`：active/inactive domain、empty policy、runtime opt-in changes。
- `MemoryRecord`：authority/provenance/role/lineage JSON round-trip。
- `MemoryStore`：schema migration、validity、supersede chain、physical forget。
- `PersonalProfileStore`：CRUD、唯一 active fact、transactional supersede、owner
  isolation、domain filtering。
- Candidate/Proposal：profile create/supersede/forget、reject、retry、undo、tamper、
  duplicate apply、domain disabled before apply。
- `ContextBuilder`：decision/episode/pattern/guidance 分槽和 per-slot bounds。
- App Context Assembler：profile priority、inactive-domain exclusion、instruction
  isolation。
- Backup/Restore：Profile 精确恢复、无 outbox enqueue、失败原子性。
- Data management：owner-scoped count/delete 和 candidate pruning。

### Runtime Contracts

- `agent-core` DTO/schema/fixture round-trip。
- `agent-chat` expired/superseded evidence filtering。
- Profile budget 与 instruction preservation。
- ContextSnapshot omission reasons。
- Invalid authority、invalid temporal interval 和 duplicate block ids fail closed。
- CLI contract fixtures 与 Flutter FRB JSON mapping 一致。

### Quality Evaluation

在现有 deterministic Memory answer quality eval 中增加：

- 新旧冲突 Profile 只使用当前有效值。
- Decision assumption 与 Current State 冲突时建议 review。
- 关闭领域后不得出现对应 claim/evidence id。
- Model-derived guidance 不得覆盖 user-confirmed constraint。
- 无召回结果时不得断言“用户从未做过”。

### Architecture Gates

实施阶段至少运行受影响的 focused Flutter tests、standalone runtime contract tests，
以及 LifeOS Shell 列出的 architecture lint、FRB entrypoint 和 AI wire enum gates。
只有修改 FRB-visible API 时才运行 codegen；生成文件不得手改。

## 13. Delivery And Observability

V1 已按以下依赖顺序交付：

1. schema、authority 和 access-policy 修复。
2. Profile Store、加密 Backup 和用户管理 UI。
3. Profile ContextBlock、角色分槽和 Runtime evidence 过滤。
4. AI Profile proposal 与 apply-time policy recheck。
5. Phase 4–5 只在 V1 有实际质量证据后排期。

可记录的 local-only、privacy-safe diagnostics：

- active Profile fact count
- selected/omitted block count by role and authority
- expired/superseded conflict count
- proposal accept/reject/undo count
- consolidation input/output count and algorithm version

不得记录 Profile value、Memory summary、Decision rationale 或 event payload。
