# KnowledgeOS 域 SSOT

> **Status**: **已实现 — 用户显式 override 落地（2026-05-28）**。原 2026-05-27 版本标记 "未触发 + 不允许提前实现"；用户在 §10 触发条件 0/5 成立、§12 反规划条款仍在的前提下，明确授权按 §3-§9 全量实现。
>
> 历史 Status 行（2026-05-27）：未触发；触发前置为 HealthOS D-2 稳定 dogfood ≥ 6 个月 + §10 全部成立 + 单独 ADR。保留 §10 / §12 作为**回滚契约**：如果 dogfood 6 个月后发现 KnowledgeOS 已偏离 §0 定位，按 §8 反目标逐项 sunset。
>
> 实现进度 / TODO 见 §14（2026-05-28 落地快照）。
>
> 上位文档：`lifeos-architecture-northstar.md`（§1.8 + §4）/ `lifeos-shell.md`（shell 复用面）/ `lifeos-decision-2026-05-24.md`（Phase D 启动 ADR）。

---

## 0. 一句话定位

> KnowledgeOS = 面向**长期个人决策**的 AI-native 第二大脑——LifeOS 的 **Personal Cognitive Infrastructure** 层。**不是** Notion / Obsidian 替代品。

差异化 anchor（防止做成"又一个笔记 app"）：

| 维度 | Notion / Obsidian | KnowledgeOS |
|---|---|---|
| 主要对象 | Page / Note | **Decision** + Experiment + Memory（Note 是入口而非终点） |
| 时间维度 | 弱（按 file mtime） | **强**——决策有 `valid_from / review_date / outcome` |
| 检索 | 全文 / wiki link | **混合检索 + 跨域 Context Builder**（复用 Memory Layer §6） |
| 跨域 | 单 silo | 直接消费 Finance / Health 的 events 和 memories |
| AI | bolt-on copilot | **Contradiction / Assumption / Review** 三个 agent 是核心 affordance，不是 plugin |

如果某天发现 "我们做的就是带 AI 的 Obsidian"——按 ADR-2026-05-24 立即停手。

---

## 1. Scope

**包含**：

- 用户**显式创建**的知识对象：Note / Decision / Experiment / Concept
- **Decision Log**——KnowledgeOS 的最高优先级 affordance（含 assumptions / expected_outcome / review_date / actual_outcome）
- **Inbox** 捕获流（quick capture：网页 / PDF / 摘录 / 语音转写 / AI chat 片段）
- 跨域 **Recall**（"我之前为什么决定 X"——基于 Memory Layer §6 的 Context Builder）
- **Weekly Review**（自动列出 review_date 到期的 Decision + 未验证的 assumption）

**不包含**：

- 实时协作 / multi-user（与 northstar §1.7 冲突）
- 富文本 WYSIWYG / block-based editor（Markdown 即可；§8 反目标）
- 知识图谱可视化（Force-directed graph 是好看不好用，等真有交互场景再做）
- 自动爬虫 / RSS 抓取 / Read Later 队列（KnowledgeOS 是**消化**层不是**获取**层；浏览器分享够用）
- 全文 OCR / 视频转写 pipeline（触发性，等单独 ADR）
- 公开发布 / blog publishing（与"个人决策记忆库"定位冲突）
- 第三方知识管理同步（Notion / Obsidian / Logseq import 不在 MVP，触发性）

**核心约束（贯穿所有 §3 对象）**：

> **高信噪比** —— 只记录"会影响长期决策与认知演化"的内容。普通生活流水（今天喝了咖啡）不入 KnowledgeOS；它的合法归宿是 Memory Layer 的自动 events，不是 KnowledgeOS 的显式对象。长期系统的对手不是检索算法，是信息熵。

---

## 2. 与已有 substrate 的关系（关键澄清）

ADR-2026-05-24 拒绝 KnowledgeOS 的理由是 "Memory Layer 通电 ≠ 独立域"。这条**仍然成立**。本文档对此的回答：

| Substrate | KnowledgeOS 关系 | 决定 |
|---|---|---|
| **Memory Runtime**（shell §6 已落地） | 复用其 `MemoryStore` / `EventStore` / `ContextBuilder` / `hybridScore` | **不复制不重写**。KnowledgeOS 写入是 `source='knowledge:*'`，与 trade journal / health 共享同一张 `memories` 表 |
| Memory `kind` 枚举（`event` / `semantic` / `episodic` / `procedural`） | 已经覆盖用户提议的 5 类对象的 3 类 | 不扩 kind 枚举；新增结构靠**单独 Drift 表 + payload** 表达 |
| `EventStore` | 复用为知识对象的时间线（"2026-08-01 修订了决策 X"） | KnowledgeOS 写 `source='knowledge:decision_revised'` 等 |
| Agent Runtime（shell §7.3 已落地） | 复用 `Agent` interface + `AgentRunner.tick` | Review/Contradiction/Assumption agent 作为 `features/knowledge/agents/` 注册 |
| Embedder（Rust EmbeddingGemma-300M） | 直接复用 | 知识对象的 summary 走相同 embedder，fingerprint 自动一致 |
| AI tool `build_context` / `query_memory` | 直接复用，无需新写 | KnowledgeOS 的 Recall 是 UI shell，底层是这两个 tool |
| Sync v2 row family（shell §8） | 新增 `know:*` 前缀（与 `fin:` / `health:` 同级） | `know:notes` / `know:decisions` / `know:experiments` / `know:concepts` |

**结论**：KnowledgeOS 的工程量 = 4 张 Drift 表 + 一组 repository + UI tabs + 3 个 agent + ~6 个 AI tool；Memory 索引 / 检索 / 上下文 / embedder 全是 0 新代码。如果实现起来 > 这个规模，说明在做不该做的事（见 §8）。

---

## 3. 七类知识对象 → 落地映射

用户原案 5 类 + 2026-05-27 review 升级的 2 类（**Assumption** / **Principle**）。按 "worldview → action" 渐进排序：

| 对象 | 落地方式 | 位置 |
|---|---|---|
| **Note** | 新增 `knowledge_notes` Drift 表（id / title / body_md / source_url? / created_at / tags / project_id?） | `features/knowledge/data/` |
| **Concept** | 新增 `knowledge_concepts` 轻量表（id / name / aliases / summary_md / related_concept_ids[]） | `features/knowledge/data/` |
| **Memory**（用户级 statement） | **直接用** Memory Layer `kind='semantic'`（已有 schema：`statement / confidence / scope / evidence_ids / last_verified_at` 全覆盖） | 复用，无新表 |
| **Principle** ⭐ | 新增 `knowledge_principles` 表——长期 worldview primitive（例："默认 edge-first" / "避免高维护成本系统"）。是 Decision 之上的 **AI alignment layer**，让 ContradictionAgent 能判断"新决策是否偏离已声明价值观"。**不可证伪**，只可主动 retire | `features/knowledge/data/` |
| **Assumption** ⭐ | 新增 `knowledge_assumptions` 表——从 Decision payload **提升为一等公民**。理由：单条假设跨 Decision 复用（例："长期指数增长高于通胀"同时影响 FIRE / Allocation / Withdrawal / Housing），失效时所有引用决策需联动重审。**可证伪** | `features/knowledge/data/` |
| **Decision** | 新增 `knowledge_decisions` 表（id / question / options[] / selected / rationale / **principle_ids[]** / **assumption_ids[]** / expected_outcome / review_date / result? / **status (7 态，见 §9)** / **context_snapshot_json**） + 镜像为 `kind='episodic'` memory | `features/knowledge/data/` + Memory Layer |
| **Experiment** | 新增 `knowledge_experiments` 表（id / hypothesis / method / metrics[] / status / result? / conclusion? / **target_assumption_id?**） | `features/knowledge/data/` |
| **Routine** ⭐ (2026-05-29) | 新增 `knowledge_routines` 表（id / statement / interval_days / last_done_at? / next_due_at / scope / status `active\|paused\|archived` / created_at）——用户定义的定期提醒（"港卡每 6 个月活跃一次"）。**不是** Note（Note 一次性）也不是 Decision（不是判断）；它的独立性来自 `nextDueAt` 必须是一行能 advance 的 state。`markDone` → `lastDoneAt = now`, `nextDueAt = now + intervalDays`。RoutineDueAgent 扫 `nextDueAt <= now + 7d` 每日提醒 | `features/knowledge/data/` |

**Drift schema**：七张表都 `with SyncableTable`，row_kind `know:{notes,concepts,principles,assumptions,decisions,experiments,routines}`。Memory 仍走 Memory Layer 表，零新增。

**Decision.context_snapshot_json**：决策落库时跨域抓"当时状态"（HRV / 睡眠 / market regime / 当周交易计数），让"为什么当时做错"可解释。Memory Layer 现成 events 直接读，无新 pipeline——Finance + Health 域不存在这列写不了，存在了几乎免费。

**为什么 Decision 同时入 `knowledge_decisions` + `memories`**：前者是 UI source-of-truth（CRUD / review / supersede），后者让 cross-domain Recall 不必特判 KnowledgeOS（"我去年为什么换了 FIRE 现金流策略" 直接走 `build_context`）。**写一份，索引两次**——KnowledgeOS indexer 跟 trade journal indexer 同模式（shell §6.4）。

---

## 4. AI tools（预想，read 优先）

位置 `features/knowledge/ai_tools/`。注册：`kKnowledgeDeviceTools` → bootstrap `deviceToolsProvider` override（仅在 `domainOptInsProvider.contains(DomainScope.knowledge)` 时拼入）。

| 工具 | 输入 | 输出 | 用途 |
|---|---|---|---|
| `recall_decision` | `query / topic? / time_range?` | `decisions[{id, question, selected, rationale, assumptions[], outcome?, age_days}]` | "我之前为什么决定 X" 主路径 |
| `list_open_assumptions` | `confidence_max?` | `assumptions[{statement, source_decision_id, last_verified_at, days_since_verify}]` | Assumption agent 喂数据 |
| `list_due_reviews` | `as_of?` | `decisions[{id, question, days_overdue, review_date}]` | Weekly Review 主面板 |
| `search_notes` | `query / tags? / project?` | `notes[{id, title, excerpt, score}]` | 全文 + 语义混合（复用 hybridScore） |
| `propose_concept_link` ⚠ write | `from_concept_id, to_concept_id, relation, reason` | proposal envelope | LLM 提议建联，需用户确认（northstar 行为契约） |
| `summarize_topic_evolution` | `concept_or_topic, time_range` | `timeline[{ts, source, change_summary}]` | "我对 X 的看法这半年怎么变" |
| `propose_inbox_classification` ⚠ write | `note_id` | proposal envelope `{kind: note\|decision_candidate\|concept_candidate, confidence}` | InboxTriageAgent 用,建议归类——见 §5 异步 triage |
| `propose_inbox_tags` ⚠ write | `note_id` | proposal envelope `{tags[], project_tag?}` | InboxTriageAgent 用,建议标签 |
| `propose_link_to_decision` ⚠ write | `note_id` | proposal envelope `{related_decision_ids[], reason}` | InboxTriageAgent 用,挂到现有 Decision |
| `list_due_routines` | `as_of?` (默认 now+7d) | `routines[{id, statement, interval_days, next_due_at, last_done_at, days_until_due}]` | RoutineDueAgent + Review tab + "我现在有什么定期事项要做" |
| `propose_routine` ⚠ write | `statement, interval_days, scope?, next_due_at?, reason` | proposal envelope `{statement, interval_days, scope, next_due_at}` | 用户表达「每 X 时间做一次 Y」/「需要定期续期 / 活跃」时由 AI 提议,一键确认 |

**写 tool 全部走 ProposalEnvelope**（northstar / ai-architecture.md 行为契约）；read tool 默认可调。

**不做**（MVP）：
- AI 自动生成 Note / Decision（用户自己写 / dictate；AI 只**整理** / **关联** / **质疑**）
- AI 直接改用户笔记内容（只能 propose）
- **保存时同步 LLM**——Inbox 写入零延迟、零网络成本；所有 AI 建议走 §7 异步 InboxTriageAgent 落到 Review tab（理由：保护"无摩擦捕获"体验,见 §5）

---

## 5. IA placement（Option B domain dock 下，3 tabs）

匹配 shell §3 的 Option B 双层 shell + `DomainShellSpec`（与 HealthOS Today/Trend/Plan 同模式）：

- **Inbox** — Quick capture（语音 / 粘贴 / 分享 intent）→ 原文直存 `knowledge_notes`,**保存路径不调 LLM**(零延迟、零成本、零失败模式)。归类 / 标签 / 挂决策建议由 §7 `InboxTriageAgent` 异步产出
- **Library** — Notes / Decisions / Concepts / Experiments 四 segmented control；list + detail；最高优先级是 Decision 视图（含 status badge：active / verified / falsified / overdue-review）
- **Review** — Weekly Review 卡片：to-review decisions / unverified assumptions / contradictions detected / **inbox triage suggestions**(InboxTriageAgent 输出的 ProposalEnvelope 列表,每条 ✓/✗) / recent agent runs

**Inbox triage flow**(异步设计,2026-05-28 定):

```
用户保存 Note  ─►  repo.upsertNote  ─►  EventStore: know:notes inserted
                                              │
                                              │ (cadence: 15min/手动 Run)
                                              ▼
                                       InboxTriageAgent
                                       (§7) reads untriaged
                                              │
                                              ├─► propose_inbox_classification
                                              ├─► propose_inbox_tags
                                              └─► propose_link_to_decision
                                              │
                                              ▼
                                       ProposalEnvelope 列表
                                              │
                                              ▼
                                       Review tab "AI 建议" 卡片
                                              │
                              ✓ accept  ─────►─────  ✗ dismiss
                                  │                    │
                                  ▼                    ▼
                         走 Repository           记 dismissed_at,
                         (升级为 Decision /        InboxTriageAgent
                         加 tag / 挂关联)         下次不再提议
```

零保存延迟;LLM 失败不影响原文落库;用户始终可不看建议直接 dogfood。

共用全局 Settings（Data section 加 Knowledge opt-in）+ Search。**不**单独建 `/inbox` `/notes` `/decisions` `/projects` 一堆 top-level 路由——那是 Notion 范式，与 LifeOS 4-tab IA 哲学不符。

用户原案的 `/projects` 域**故意省略**：在 LifeOS 里 "Project" 既不属于 KnowledgeOS 也不属于 Finance / Health；要么是未来的 ProjectOS 触发，要么是 Note 的 `project` tag（MVP 走 tag 路径）。

---

## 6. Cross-domain hooks

KnowledgeOS 注册自己的 shell §4 seam（与 Finance / Health 并列）：

- `chat_rail_provider` override：Recall 建议 chip（"想起 2026-03 你说 QQQ + 期权 vs 股息股的对比……"）
- `device_tools_provider` override：append `kKnowledgeDeviceTools`
- `ai_context_summary` override：在 AI Chat 系统提示里附 "本周到期 reviews / 高置信开放假设" 摘要（小，每次 ≤ 500 token）

**反向消费**：KnowledgeOS 的 Decision indexer 监听 `EventStore` 的 cross-domain events（`source.startsWith('fin:')` 或 `'health:'`），当一条决策的 review_date 到期且最近 7 天有相关域事件，触发 Review 卡片提醒。这条**完全经 Memory Runtime**，不直接 import 兄弟 feature（northstar §2.4）。

---

## 7. 四个核心 agent（complement 已有 Morning Briefing）

| Agent | Schedule | 读 | 写 |
|---|---|---|---|
| **ReviewAgent** | 每周日 09:00 local | `list_due_reviews` | Episodic memory（"X 决策已到 review 期"）+ 通知（复用 health 的 `lifeos.knowledge.review` channel） |
| **AssumptionAgent** | 月初 + 任何决策被新事件触及时 | `list_open_assumptions` + 跨域 events | Episodic memory + Review tab 卡片（不直接通知避免噪音） |
| **ContradictionAgent** | 每次新 Decision / Note 落库 | 该对象 vs 最近 90 天同 scope memories + **当前 active Principles** + 引用的 Assumptions（cosine + LLM judge） | 若检出冲突（事实/价值观偏离），写 `kind='semantic'` memory + Review tab 提示。**不**自动覆盖原对象 |
| **InboxTriageAgent** | 15min cadence + 手动 Run + 可选每条 Note insert 触发 | 未 triage 的 `knowledge_notes`（用 side-table `knowledge_inbox_triage` 记 last_triaged_at，**local-only never-sync**）+ 现有 Decisions/Concepts/tags | 调用 `propose_inbox_classification` / `propose_inbox_tags` / `propose_link_to_decision`，输出 ProposalEnvelope 列表落到 Review tab。**永不改 `body_md`**(§8) |
| **RoutineDueAgent** | 每日 08:00 local | `list_due_routines(as_of = now + 7d)` | Episodic memory + 单次 local notification（`NotificationChannelSpec.knowledgeReview` 通道,复用 HealthOS `flutter_local_notifications` 通道矩阵）。Review tab "本周到期的 Routine" 卡片同源（StreamBuilder 直读 repo）。**通知通道与 ReviewAgent 共用** "Knowledge Review" 通道,用户只需一个 mute 开关 |

复用 shell §7.3 的 `Agent` / `AgentRunner` 框架。**反目标**：不做 "Agent 之间相互调用"（northstar §1.1 边界 / shell §7.3 反目标）。

**InboxTriageAgent 工程约束(完整流图见 §5)**：单次 Note ≤ 1 LLM round-trip(3 个 propose 工具批量调);无 LLM 配置时 skip,不报错;side-table `knowledge_inbox_triage(note_id, last_triaged_at, dismissed_at?)` 是 local-only,never-sync;dismissed 提议不再重提。

---

## 8. 反目标（永远不做）

- ❌ **"AI Notion" 陷阱**：任何 "既然有 Note 就支持 rich block / database / table / collaboration" 的延伸——**直接拒绝**。KnowledgeOS 的核心 affordance 永远是 Decision / Review / Recall，不是 document authoring
- ❌ **低信噪比记录**：日常生活流水（今天喝了咖啡 / 看了某部剧）不进 KnowledgeOS；它的合法入口是 Memory Layer 自动 events（已有），不是 KnowledgeOS UI
- ❌ **WYSIWYG block editor**（Notion 范式）；坚持 Markdown + 渐进增强
- ❌ **强制双链 / backlinks 自动生成**（Obsidian 范式）；KnowledgeOS 用 `[[concept]]` 软链 + AI 建议建联（user confirm）
- ❌ **公开发布 / blog 模式**（KnowledgeOS 是私域决策库，不是 publishing platform）
- ❌ **协作 / 评论 / 分享链接**（northstar §1.7）
- ❌ **AI 自动生成知识内容**（用户为知识来源；AI 只整理、关联、质疑、提醒；防止 LLM hallucinated knowledge 污染长期记忆库）
- ❌ **图数据库 / 单独 graph store**（关系存在 Drift JSON 列足够；> 100k 节点才考虑，触发性）
- ❌ **import Notion / Obsidian / Logseq**（MVP 不做；触发性）
- ❌ **OCR / 视频转写 / 全网爬虫**（KnowledgeOS 是消化层，触发性）
- ❌ **把 Memory Layer 替换为自家 store**（违反 §2 决议）

---

## 9. Drift schema（草案）

> 仅作触发后的 starting point，**不是**当下要建的表。届时 schema 版本号 ≠ 18。

```dart
// features/knowledge/data/db/ (届时已是按域拆库，shell §9 follow-up)
class KnowledgeNotes extends Table with SyncableTable {
  TextColumn get id => text()();            // UUID PK
  TextColumn get title => text()();
  TextColumn get bodyMd => text()();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get tagsJson => text()();       // ["fire","strategy"]
  TextColumn get projectTag => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  // + SyncableTable: ownerUserId / updatedAt / updatedByDevice / hlc / deletedAt
}

class KnowledgePrinciples extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get statement => text()();           // "默认 edge-first"
  TextColumn get rationaleMd => text()();
  TextColumn get scope => text()();               // 'investing' | 'life' | '*'
  TextColumn get status => text()();              // active | paused | retired
  DateTimeColumn get declaredAt => dateTime()();
}

class KnowledgeAssumptions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get statement => text()();           // "长期指数增长高于通胀"
  RealColumn get confidence => real()();          // 0..1
  TextColumn get scope => text()();
  TextColumn get evidenceIdsJson => text()();     // memory / note ids
  DateTimeColumn get status => text()();          // active | weakened | falsified | retired
  DateTimeColumn get lastVerifiedAt => dateTime().nullable()();
}

class KnowledgeDecisions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get question => text()();
  TextColumn get optionsJson => text()();         // [{label, rationale}]
  TextColumn get selectedLabel => text()();
  TextColumn get rationaleMd => text()();
  TextColumn get principleIdsJson => text()();    // FK → knowledge_principles
  TextColumn get assumptionIdsJson => text()();   // FK → knowledge_assumptions
  TextColumn get expectedOutcome => text().nullable()();
  DateTimeColumn get reviewDate => dateTime().nullable()();
  TextColumn get actualOutcomeMd => text().nullable()();
  TextColumn get status => text()();              // draft | active | paused | expired | verified | falsified | superseded
  TextColumn get supersededByDecisionId => text().nullable()();
  TextColumn get contextSnapshotJson => text().nullable()();  // 跨域 state-of-mind 抓拍
  DateTimeColumn get decidedAt => dateTime()();
}

class KnowledgeConcepts extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get aliasesJson => text()();
  TextColumn get summaryMd => text()();
  TextColumn get relatedConceptIdsJson => text()();
}

class KnowledgeExperiments extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get hypothesis => text()();
  TextColumn get methodMd => text()();
  TextColumn get metricsJson => text()();
  TextColumn get status => text()();              // planned | running | done | abandoned
  TextColumn get resultMd => text().nullable()();
  TextColumn get conclusionMd => text().nullable()();
  TextColumn get targetAssumptionId => text().nullable()();  // FK → assumption being tested
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
}
```

**Decision.status 7 态**：`superseded` 是关键——"认知演化而非推翻"（例：2026 QQQ+covered call → 2028 QQQ+BOXX+dynamic hedge），通过 `supersededByDecisionId` 形成历时链。

索引最少：`(owner_user_id, updated_at)` + Decisions 加 `(owner_user_id, status, review_date)` + Assumptions 加 `(owner_user_id, status)`。

---

## 10. 触发条件（全部成立才考虑 ADR）

按 northstar §1.8 / decision-2026-05-24 的标准，KnowledgeOS 触发**全部**条件：

1. ✅ HealthOS 在用户自己设备上日常使用 **≥ 6 个月** 且稳定（无月级 P0）
2. ✅ Memory Layer **第二个非 Finance caller**（HealthOS sleep/hrv indexer）连续 ≥ 3 个月有用户实际查询命中（不是空转）
3. ✅ 用户在 ≥ 4 周内**自发**记录过 ≥ 20 条 "想存进知识库" 的内容（在 inbox 草稿 / AI chat / 临时 markdown），并明确表达"现在的承载形式不够"
4. ✅ Obsidian / Notion / Apple Notes 实际试用 ≥ 3 个月后，能**具体说出**至少 3 条 KnowledgeOS 才能解决的痛点（不是抽象"集成度更高"）
5. ✅ shell 自身在 D-2/D-3 期间无重大重构需求（避免 KnowledgeOS 与 shell 演进互相拖累）

任一条不成立 → 继续等。本文档**不**为推进触发条件做主动工作。

---

## 11. 与 shell 的依赖

| 上游 | 必须状态 |
|---|---|
| Sync v2 row family namespace（shell §8） | 已落地（D-1.4）✅ |
| Memory Runtime（shell §6） | 已落地（D-1.7b）✅ |
| Embedder（shell §6.6） | 已落地（D-1.7c）✅ |
| Multi-domain IA shell（shell §3，Option B dock） | 已落地（D-2.3b）✅ |
| AI tool 分层 / `domain` 字段（shell §7.1 / §7.2） | 已落地（D-1.2 / D-1.3）✅ |
| Auth domain scopes（shell §5） | 已落地（D-1.5）—— 需扩 `DomainScope.knowledge` enum 值，1 行 |
| Agent runtime（shell §7.3） | 已落地（D-2.5）✅ |

**惊喜**：触发后 shell 侧新增工作 ≈ 1 行 enum + sync namespace `know:` 注册。其余全是 `features/knowledge/` 内部建设。这也是 LifeOS Phase D 投资的兑现——shell 的真实成本摊到第三域已经非常薄。

---

## 12. 反规划条款（自我约束）

> **2026-05-28 override note**: 用户显式授权 override，下列前 2 条已经被打破（`features/knowledge/` 目录已存在 + 实现已落地）。保留这一节的目的是**回滚契约**——如果未来要 sunset，按这里逐条反向执行；以及**防扩**——下列其余条款仍生效，新增工作前对照核对。

- ❌ ~~不写 "KnowledgeOS Phase 0–N" 任务列表~~ → §14 现在维护一个**已落地快照** + TODO，不是 Phase 0-N。新增条目前自问：是不是 dogfood 真发现该补，而不是"完善设计"
- ❌ ~~不在 `features/` 下提前创建 `knowledge/` 空目录~~ → 已实现，目录非空。回滚 = 整目录删除 + 撤回 §11 enum 行
- ❌ 不在 `core/ai/contracts/` 加任何 knowledge-specific 字段（northstar §2.5）— **仍生效**
- ❌ 不为本文档写 detail 子文档（`knowledgeos-*.md`）；先 dogfood 再拆 — **仍生效**
- ❌ 本文档目标长度：**< 450 行**（override 后含 §14 落地快照 + §5 Inbox triage 流图）。改本文档前自问：是不是 dogfood 真发现需要改，而不是"完善设计"

---

## 13. 一句话总结

> KnowledgeOS = 面向长期生活决策的 AI-native 第二大脑——记忆、整理、**质疑**、复盘、辅助决策；长期沉淀形成 **Personal Cognitive Infrastructure**：你的认知模型本身。

只有当 Memory Layer + Agent + 跨域 shell 都已被 HealthOS 充分压测后，让这个愿景**少写代码就能成真**，KnowledgeOS 才值得做。在那之前最大价值是**给 shell 演进当北极星**——任何 shell 决策不能堵死本文档复用路径。

---

## 14. 实现进度 / TODO（2026-05-28 override 落地快照）

> 本节是**已落地状态 + 未完成条目**的现实快照，不是 Phase 0-N 任务列表（见 §12 注）。新增条目前先问：dogfood 是否真发现需要？

### 14.1 已落地（MVP 闭环）

**Shell / Schema**
- ✅ `DomainScope.knowledge` enum (`core/auth/domain_scope.dart`)
- ✅ Sync v2 row family `know:` 前缀注册（`core/sync/domain_prefix.dart` + `kSyncableTables`）
- ✅ Schema v18→v19 + 6 张 Drift 表（`core/persistence/knowledge_tables.dart`）：notes / principles / assumptions / decisions / concepts / experiments；全部 SyncableTable，含索引
- ✅ Schema v19→v20 + `knowledge_inbox_triage` 侧表（`core/persistence/local_only_tables.dart`，DDL raw SQL）：**local-only / never-sync**，1 行/note，`proposals_json` 内联三类 envelope（§5 异步 triage 流图所需）
- ✅ Schema v20→v21 + `knowledge_routines` Drift 表（2026-05-29）：`statement / interval_days / last_done_at / next_due_at / scope / status` + sync 列；索引 `(owner, status, next_due_at)` 给 `listDueRoutines`
- ✅ Schema v21→v22 + `merged_into_id` 列（notes + concepts，§15.3 去重指针；2026-05-29）：additive nullable ALTER，被合并的重复条目软删 + 记保留方 id
- ✅ `KnowledgeRepository`（`features/knowledge/data/knowledge_repository.dart`）：7 类对象 CRUD + status 过滤 + due-review / due-routine query + `mergeNotes` / `mergeConcepts`（§15.3 事务内并集 + tombstone + concept 入边重指）+ `listConcepts`
- ✅ `InboxTriageRepository`（`features/knowledge/data/inbox_triage_repository.dart`）：侧表 upsert / resolve / pending feed；dismissed 合并保护

**AI tools**（`features/knowledge_ai_tools.dart` → `kKnowledgeDeviceTools`）
- ✅ Read：`recall_decision`、`list_open_assumptions`、`list_due_reviews`、`list_due_routines`（2026-05-29）、`search_notes`（hybrid via `MemoryRuntime.recall(source='know:notes')` + tag/project 后过滤；cold start 或空 query 回落 substring 扫）、`summarize_topic_evolution`、`find_similar_knowledge`（2026-05-29，§15.3 去重读：遍历 `kKnowledgeMemorySources` 具体 source + cosine + Jaccard token 复核）、`search_knowledge`（2026-05-29，跨 7 类语义检索）、`review_knowledge_health`（2026-05-29，聚合到期/未校验/孤儿/到期 routine 给「本周建议」）
- ✅ Write（全部 ProposalEnvelope，§4 行为契约）：`propose_concept_link`、`propose_inbox_classification`、`propose_inbox_tags`、`propose_link_to_decision`、`propose_routine`（2026-05-29）、`propose_capture`（2026-05-29，统一 7 类分类器，目前 routine heuristic 稳定，其余走 note 兜底）、`propose_merge`（2026-05-29，§15.3 去重写：`knowledge_merge` envelope + diff，note/concept；chat-apply 接线待办见 §15.6）
- ✅ `propose_inbox_*` 三件套同时持久化到 `knowledge_inbox_triage` —— §5 异步 triage 的 LLM 写端口
- ✅ 通过 `deviceToolsProvider` 在 bootstrap 拼入，gated on `domainOptInsProvider.contains(DomainScope.knowledge)`

**Agents**（`features/knowledge/agents/`，复用 shell §7.3）
- ✅ `ReviewAgent`（每周日 09:00 local）—— §5 "到期 Decision + 未校验 assumption"：除 `listDueReviews` 外也扫 > `kAssumptionStaleDays` 未校验的 active 假设，二者皆空才 skip（2026-05-29 补齐）
- ✅ `AssumptionAgent`（30d cadence，扫 > 90d 未校验 active 假设）
- ✅ `ContradictionAgent`（每 6h，principle mismatch + assumption invalidation 启发式）
- ✅ `InboxTriageAgent`（15min cadence，§5/§7 核心）：heuristic-only MVP —— 分类（长文 + 选项语言 → decision_candidate；短定义 → concept_candidate）、tag 词典命中、token-overlap 决策建联；每 run ≤ `kInboxTriageMaxNotesPerRun` (10) 条；输出落 `knowledge_inbox_triage`；dismissed kind 永不重提。LLM round-trip 替换 heuristic 是 §14.2 P1 一项，不阻塞 dogfood
- ✅ `RoutineDueAgent`（daily 08:00 local，2026-05-29）：扫 `next_due_at <= now + 7d` 的 active routines，写 episodic memory + 单次 local notification（`NotificationChannelSpec.knowledgeReview` 通道，与 ReviewAgent 共用）。Review tab "本周到期的 Routine" 卡片 + 单按钮"已处理"（`lastDoneAt = now`, `nextDueAt = now + intervalDays`）

**Memory Layer 接入**（§3 "写一份，索引两次"）
- ✅ `KnowledgeDecisionMemoryIndexer`：Decision → `kind='episodic'` Memory，跟 trade journal indexer 同模式；接入 `memoryLayerBootstrapProvider`
- ✅ `knowledge_object_memory_indexers.dart`：Note / Concept / Experiment → `kind='episodic'`（带 createdAt 锚的时间事件），Principle / Assumption → `kind='semantic'`（worldview / belief）。importance 按 status 与 confidence 调整(falsified assumption 留在库里但 importance 0.2,让 ContradictionAgent 仍可见)。全部 gate 在 Knowledge opt-in
- ✅ Agent 输出 → `kind='episodic'` / `'semantic'` Memory（Review / Assumption / Contradiction）
- ✅ `DecisionContextSnapper`（`features/knowledge/data/decision_context_snapper.dart`）：Decision 写入路径预读最近 7 天 EventStore (source `fin:*` / `health:*`)，按 importance 抽 top 5 拼 `contextSnapshot`。非阻塞（任何失败 → null，列保持 NULL）。**不**写进 `KnowledgeRepository.upsertDecision`，保持 repo 为纯 Drift wrapper；UI / 未来 AI 写入器主动调 snapper。Decision detail 页新增 "当时的跨域状态" section 渲染

**IA Shell**（§5 Option B dock，与 HealthOS 同模式）
- ✅ 3 tabs：Inbox / Library / Review (`/knowledge`, `/knowledge/library`, `/knowledge/review`)；Library 加 Routines 段（5th segment, 2026-05-29）+ 新建 Routine sheet（statement + 4 档 interval 预设 + scope tag）
- ✅ Unified Capture sheet（2026-05-29，slice B v1）：Inbox FAB 现在打开 `KnowledgeCaptureSheet` — 单 textarea，保存即落 Note（零延迟），保存后同步跑 `CaptureClassifier` heuristic，命中 routine 模式时在同一 sheet 内显示「✓ 应用建议 / 保留为 Note」内嵌升级卡片。✓ → 写 Routine + 软删 temp Note；✗ → 保留 Note。Library 的 typed FABs（Decision / Concept / Experiment / Routine）保留作为「我知道自己要写什么」直接通道
- ✅ `LlmCaptureClassifier`（2026-05-29，slice B v2）：抽象出 `CaptureClassifier` interface + `HeuristicCaptureClassifier` 实现 + `LlmCaptureClassifier`。后者走用户配置的 `DeviceLlmClient.complete`（system prompt 描述 7-类 + JSON schema，输出纯 JSON），8s 超时；任意失败（无 profile / 网络 / 解析 / 置信度 < 0.6）silent fallback 到 heuristic。`captureClassifierProvider` 是 Sheet + `propose_capture` 工具共用的 seam。Sheet 增加 `classifying` 中间态显示「AI 思考中」；apply 路径扩展：routine 直写结构化行，decision/principle/assumption/concept/experiment 用 tag-only 提升（给 Note 加 `kind:<x>_candidate` + `scope:<...>` tag，与 `propose_inbox_classification` 同形状）
- ✅ LLM 润色（2026-05-29，slice B v2.1）：同一次 LLM round-trip 在分类之外还产出 `polished_title` / `polished_body`（含义不变，仅修拼写 / 标点 / 中英文混排 / 口语化整理；不补充用户没写的事实）。空字符串规范化为 null。`CaptureClassification.hasPolish` + `hasSuggestion` 让 sheet 在「只润色不升级」(kind == note 但有 polish) 也进入 suggestion 阶段。UI 增加 `_PolishPanel` 显示「原:.../→ ...」前后对比；apply 时优先写润色版的 Note，再叠加 upgrade 路径。Heuristic 不润色（始终返回 null），保留无 LLM profile 时的零摩擦体验
- ✅ `knowledgeDomainShell()` + `knowledgeShellRoute()`，注入 router 顶层 ShellRoute
- ✅ Settings → Domains 加 KnowledgeOS 开关 + Inbox 深链
- ✅ 全 Forui 实现（无 Material 组件依赖）；New Note 含 Edit/Preview toggle（用 `AiMarkdown` 渲染）
- ✅ Review tab "AI 建议" 卡片（`_ai_suggestions_card.dart`）：渲染 pending envelopes，每条 ✓/✗。✓ 走轻量 apply —— merge `kind:*` / tag / `decision:<id>` 软链 → `upsertNote`；✗ 标 dismissed。MVP inline apply，不抽 `ProposalApplier`（符合 §12 反扩条款；如果后续 P2 `propose_concept_link` apply 路径要落，再统一抽）
- ✅ Library FAB + writers（§1 最高优先级 affordance）：Decision sheet（`_decision_writer.dart`） — question / 动态 options / selected / rationale / Principle+Assumption picker / review date 预设；Principle / Assumption / Concept / Experiment sheets（`_object_writers.dart`） — 每个 ~150 行紧凑表单。Decision 段的 FAB 弹 family chooser（Decision / Principle / Assumption 共享 author flow），其它段直达对应 sheet；Notes 段引导回 Inbox。Assumption confidence 用 5 档预设按钮（Forui slider 控制器路径成本不抵价值）
- ✅ Decision detail page（`knowledge_decision_detail_page.dart` + route `/knowledge/library/decision/:id`）：Library Decisions 卡片 tap → 详情；渲染 status / 全部 options（高亮 selected）/ rationale（AiMarkdown）/ 引用的 Principles & Assumptions / expected & actual outcome / **supersede chain 反向遍历**（§9 "认知演化"）

**Cross-domain hooks**（§6）
- ✅ `knowledgeChatRailContentProvider`：projects 最近 3 条 Decision 进 AI chat rail
- ✅ Share-intent 双轨调度（`features/ingest/data/share_intent_service.dart` 内联 — Knowledge opt-in 时 text/url 写 `KnowledgeNote(tags=['source:share'])` 并跳 `/knowledge`，image/file 仍走 Finance ingest）。临时跨 feature 直引,P3 抽 dispatcher 解耦

### 14.2 待办（按价值 / 紧急度排序）

**P0 — 影响 MVP 可用性**
- [ ] **Inbox quick capture: 语音 / 截屏 OCR / AI chat 片段**：share-intent 已通；剩余三条入口待落（语音转写、截屏 OCR、从 AI chat 一键存为 note）。每条独立小项，按 dogfood 频率决定顺序

**P1 — 影响 §0 定位的关键功能**
- [ ] **AssumptionAgent 事件触发**：§7 spec 说 "月初 + **任何决策被新事件触及时**"。当前只有月初 cadence，事件触发需要 `EventStore` listener
- [ ] **ContradictionAgent cosine + LLM judge 路径**：MVP 是纯启发式 token 匹配，§7 spec 要语义比对。等 Knowledge Memory 全量化后切换
- [x] **CaptureClassifier LLM 替换 heuristic**（2026-05-29 完成）：`LlmCaptureClassifier` 走 user-configured `DeviceLlmClient.complete`，全 7 类 JSON 抽取；heuristic 作为 silent fallback 保留无 profile / 失败场景。`CaptureClassifier.classify` 抽象成 interface 作为 swap 边界（LLM / Heuristic 实现等价）
- [ ] **InboxTriageAgent LLM round-trip 替换 heuristic**：§7 spec "单次 Note ≤ 1 LLM round-trip(3 个 propose 工具批量调)"。MVP 是规则启发式（词典 + token overlap）。可参考 `LlmCaptureClassifier` 的 prompt-engineered JSON 模式 / 失败兜底 / 置信度门槛实现；3 件套 tool 形态稍有不同（每条 Note 输出多 envelope）但骨架共用
- [ ] **从 Note 提升到 typed row（decision / assumption / principle / concept / experiment）**：当前 Capture sheet 对这 5 类用 tag-only 提升（`kind:<x>_candidate` + 可选 `scope:<...>` tag），未直接写结构化行。Library typed FABs + Review tab 的 AI 建议卡可以一键应用，但 sheet 内一步到位的 "Promote with extracted fields" 路径尚未串联

**P2 — Dogfood 改进**
- [x] **非 Decision 类型 detail pages**（2026-05-29）：`knowledge_object_detail_page.dart` —— Concept / Experiment / Principle / Assumption 共用一个 read-only 详情页（route `/knowledge/library/object/:kind/:id`），Library 的 Concept / Experiment 卡片现在可点开（chevron 一致）。按 id 经 repo `findX` 解析，referenced-but-archived 行也能打开
- [x] **Decision lifecycle 编辑**（2026-05-29）：`_decision_lifecycle_sheet.dart` —— detail 页头 ✎ 打开生命周期编辑：7 态 status 切换 / actual_outcome 填写 / `supersededByDecisionId` 选择（标 superseded 时必填，否则清空,使"认知演化"链能成立）。复用 `mutationStamperProvider` + `upsertDecision`。顺带修 detail 页引用解析：principle/assumption 改用 `findX`,引用了 retired/falsified 的也会显示。测试 `knowledge_lifecycle_repository_test`(4)
- [ ] **Review tab "recent agent runs"**：§5 spec 列出但未渲染；需要 Agent 历史读 API
- [x] **`lifeos.knowledge.review` 通知 channel**（2026-05-29）：`NotificationChannelSpec.knowledgeReview` enum 落地；`NotificationService.showNow` 接受 `channel` 参数；RoutineDueAgent 首批使用。ReviewAgent / AssumptionAgent 接入同通道仅一行改动，按 dogfood 反馈再开
- [ ] **`ai_context_summary` override**：§6 列了，但现有 slot (`AiContextSummary`) 是 Finance-shaped；要么扩 slot 形态，要么换成独立的 prompt 拼接 seam
- [ ] **`propose_concept_link` 真正落地路径**：write tool 已经返回 ProposalEnvelope，但 `ProposalApplier` 还没认这个 kind。需要在 `featureProposalApplier` 里加 `knowledge_concept_link` 分支
- [ ] **Knowledge opt-out 清理**：关闭 opt-in 时 indexer 停止订阅，但已写入的 episodic memories 不清。需要明确策略（保留 vs prune），shell §5 应该有相关约定

**P3 — 工程债**
- [ ] **测试**：`test/features/knowledge/` 目录尚未建立。至少需要 repository 单测 + AI tool 单测 + agent 单测（参考 `health/test/`）
- [ ] **l10n**：所有 UI 文案当前是字面量（中/英混排）；触发 dogfood feedback 收敛后入 `.arb`
- [ ] **Sync wire prefix 修复**：`SyncEngine._toRowChange` 硬编码 `prefixFinanceTable(table)`；KnowledgeOS 表上车后 outbound 仍走 `fin:` 前缀。HealthOS 也踩这个雷（health_metrics 目前本地 only）。需要按表名查 domain → 选 prefix 的 dispatch
- [ ] **Share-intent dispatcher 解耦**：当前 `share_intent_service.dart` 内联 Knowledge 写入路径，违反 feature 边界（Finance ingest feature 直接 import Knowledge repo）。抽一个 `ShareIntentDispatcher` 接口，让 Knowledge / Finance 各注册自己的 handler；第三个分发目标出现时强制收敛
- [ ] **`kPrimaryTabPaths` / dock 可视性**：dock 现在 3 域全开会很挤；need responsive collapse 策略（HealthOS D-2.3b 的 ≥ 600 px 桌面 dock 已经实现，移动端 chevron 也是）
- [ ] **图标**：当前 `Icons.psychology` (Material) 还在 domain shell；HealthOS 同样用 Material icon glyph，convention 一致但 long-term 应该用 `FLucideIcons.brain` 等
- [ ] **AppFlowy/Quill 编辑器调研**：§8 反目标明确拒绝 block editor，但 dogfood 可能发现 "Markdown 也太裸了"。如果出现这种声音，先按 `AiMarkdown` 渲染面加 toolbar（list / quote / code），**不**引入 block tree

### 14.3 显式不做（防 "AI Notion" 漂移）

下列条目 dogfood 中可能"想加但不应该加"，写在这里是为了后人对照 §8 反目标时省一次决策：

- ❌ flutter_quill / appflowy_editor / super_editor（block editor → §8 第一条）
- ❌ Notion / Obsidian / Logseq 导入（§1 不包含 + §8 第 9 条）
- ❌ 知识图谱可视化（force-directed graph → §1 不包含 + §8 第 8 条；§8 第 9 条说 > 100k 节点再说）
- ❌ 自动双链 / backlinks 生成（§8 第 4 条；坚持 `[[concept]]` 软链 + AI 建联 user-confirm）
- ❌ RSS / Read Later 抓取 pipeline（§1 KnowledgeOS 是消化层不是获取层）
- ❌ AI 自动生成 Note / Decision 内容（§4 / §8 第 7 条；AI 只整理、关联、质疑）
- ❌ Inbox 保存时同步调 LLM(同步分类 / 摘要 / 改写) — §5 异步 triage 是显式决策(2026-05-28);零延迟保存是 inbox 的不可妥协约束。"想做 ChatGPT 即时整理"=回头看 §5 这段

### 14.4 sunset 信号（命中即按 §12 回滚）

- 用户停止 dogfood ≥ 30 天且无重启意图
- ContradictionAgent / ReviewAgent 累计 false positive 噪音 > 真信号 3 倍且无法靠阈值收敛
- KnowledgeOS-only 代码持续增长但跨域 Recall 命中率 < 5%（说明本质是 silo，违背 §1）
- 任何一条 §8 反目标被破（即使是 "顺手加一下"），但 dogfood 又确认有价值——这是要立 ADR 而不是默默扩

---

## 15. Knowledge Agent — 统一会话式入口（设计，2026-05-29）

> 目标（用户原话）：把 KnowledgeOS 用户交互入口做成一个**完善的 AI agent**，支持**增加 / 查询 / 去重 / 内容建议**。本节是设计 SSOT，落地状态待 §15.6 勾选。

### 15.0 定位：一个 agent loop，四个动词，零新运行时

今天入口是**碎片化**的——增（Capture Sheet）、查（全局 AI chat）、建议（5 个后台 agent 各喂 Review tab），而**去重根本不存在**。本方案不另起 chat 引擎，而是把 Inbox 录入面**升格为一个 knowledge-scoped 会话助理**，直接复用既有 `DeviceAgentLoop` + ai_chat 渲染组件，只做两件事：(1) 补齐缺失的**工具**（去重 + 统一建议），(2) 用一段 knowledge preamble + 快捷 chips 把入口收敛成一个门面。

所有写仍走 `ProposalEnvelope`（§4 行为契约），所有调用进 `AiSpan` trace（ai-architecture.md）。

### 15.1 形态决策：会话式助理 —— 与零延迟快存的边界（不可妥协）

⚠ **本节是 §14.3 红线（"❌ Inbox 保存时同步调 LLM"）的边界澄清，落地时必须守住：**

存在**两条独立路径**，永不混淆：

1. **快存（FAB → Capture Sheet）** —— 维持现状。保存即落 Note、**零延迟、零网络**；分类走 §5 异步 triage / 同步 heuristic。本路径**不**变。
2. **会话助理（本节新增）** —— 用户**主动发一条消息**才触发的 surface。此时 LLM round-trip 是用户显式发起的、被预期的，不违反"无摩擦捕获"——因为它不在快存的关键路径上。

判定准则：**LLM 是否在"用户敲完就想立刻消失"的保存路径上？** 快存 = 是 → 禁止同步 LLM；会话 = 否（用户在等回复）→ 允许。

入口 UI（Inbox tab 顶部录入面，复用 ai_chat surface）：

```
┌─────────────────────────────────────────┐
│  💭 记点什么 / 问点什么…           [🎤]  │  单一输入（文字 / 语音）
├─────────────────────────────────────────┤
│  [查重]  [本周建议]  [搜我的知识]         │  空态 chips = 三个意图预设
└─────────────────────────────────────────┘
   发送 → DeviceAgentLoop(knowledge scope)
   流式文本 + 内联 ProposalEnvelope 卡片（升级 / 合并 / 链接 / Routine，复用现有交互语法）
```

- **有 LLM runtime** → 多轮 agentic，可追问（"两条都留" / "归到 Concept X"）。
- **无 runtime（Web / 无 key / 无 profile）** → 录入面回落今天的 `HeuristicCaptureClassifier` + 升级卡（非会话），同一个框两种深度。
- 实现：用 `AiIntentInvocation{ source: knowledgeInbox, intent, object }` 打开 ai_chat surface，传 `knowledgeScope` preset（只挂 `kKnowledgeDeviceTools` + `kKnowledgeSystemPromptBlock` + capture preamble）。**不新建 chat 引擎**。

### 15.2 四动词 → 工具映射

| 动词 | 工具 | 状态 |
|---|---|---|
| **增加** | `propose_capture`（已存在，7 类分类 + 润色）+ 录入后**自动查重** | 复用 + 增强 |
| **查询** | `recall_decision` / `search_notes` / `summarize_topic_evolution` / `list_*` + 新增 `search_knowledge`（跨 7 类统一语义检索） | 复用 + 1 新工具 |
| **去重** | 新增 `find_similar_knowledge`（read）+ `propose_merge`（write） | **全新（主菜）** |
| **建议** | 新增 `review_knowledge_health`（把 5 个 agent 信号聚成一个 pull 工具） | **新整合** |

后台 5 个 agent **不动**，继续 push ambient 卡片；新工具是"主动问"的 pull 版本，与 push 互补。

### 15.3 新工具规格（全部遵守 §4 ProposalEnvelope / read-default 契约）

**① `find_similar_knowledge`（read · info）**
```
in:  { text? | entity_ref?, types?: [note|concept|decision|...], threshold?=0.82, top_k?=5 }
out: [{ id, kind, title, similarity, overlapping_fields:[title|body|tags], why_zh }]
```
实现：EmbeddingGemma 768-d cosine + token-overlap 复核（避免纯向量误判，沿用 `search_notes` 的 hybrid 思路）。
⚠ **`MemoryRuntime.recall(source:)` 是精确匹配**（`memory_store.dart` → `m.source = ?`），**不支持 `know:*` 通配**；Knowledge indexer 写的是具体 source（`know:notes` / `know:concepts` / `know:decisions` …）。两种落法二选一：
- **MVP（默认，零 core 改动，合 §12 反扩）**：在工具内**遍历具体 source 列表**，各调一次 `recall` 后合并 + 去重排序。具体常量已存在并分散（`kKnowledgeNoteMemorySource='know:notes'`、`kKnowledgeConceptMemorySource='know:concepts'`、`kKnowledgeDecisionMemorySource='know:decisions'` …，散落于 `knowledge_object_memory_indexers.dart` / `knowledge_decision_memory_indexer.dart`）；P0 顺手收敛出一个聚合 `kKnowledgeMemorySources` 列表，按 `types` 入参取子集。
- **可选增强（跨域受益）**：给 `recall` 加 `sourcePrefix` / `sources[]` 过滤（`memory_store` 改 `m.source LIKE ?` 或 `IN (...)`），一次查完。改动小但触 core，按 dogfood 是否需要再做。

会话录入后由 agent 自动调；chip「查重」触发全库聚类扫。

**② `propose_merge`（write · ProposalEnvelope）** —— 展示合并 diff，用户确认后才写
```
in:  { primary_id, duplicate_ids:[...], merged:{ title?, body_md?, tags?, links? } }
→ ProposalEnvelope
确认后 KnowledgeRepository.mergeEntities():
  - 保留 primary，union tags / aliases / related_ids
  - duplicate 软删（deleted_at）+ 写 merged_into_id 指针
  - 回指引用：concept.related_concept_ids、[[concept]] 反链
```
- **MVP 只合并 Note↔Note、Concept↔Concept**（入边少）；Decision / Assumption 引用重定向标 P1。
- ⚠ **Confirmation policy**：`Confirmation` enum 当前只有 `none / oneTap / typed`（`tool_descriptor.dart`），**没有 `confirmDiff`**——架构文档的交互语法里的 confirmDiff 是 UI 渲染模式，不是该 enum 值。MVP 用 **`Confirmation.oneTap`**，把合并 diff（保留/删除/union 字段）**渲染在 ProposalEnvelope 卡片内**（diff 是渲染关注点，与 confirmation policy 解耦）。merge 软删可逆（`deleted_at` + `merged_into_id` 可还原），oneTap 风险可接受。若 dogfood 发现误触多，P1 再正式新增 `confirmDiff` enum 值（enum + wire + applier UI 三处）。
- Sync 友好：合并 = 两条 row update（primary 改 + duplicate tombstone），天然走 row-state LWW（sync-v2）。

**③ `search_knowledge`（read · info）** —— 补齐跨类型检索（今天 `search_notes` 只查 note、`recall_decision` 只查 decision）。

**④ `review_knowledge_health`（read · info）** —— 一次性聚合：过期 assumption / 到期 review·routine / 未分诊 inbox / 孤儿 note（无 tag·link）/ 矛盾 / **重复簇**，返回优先级列表。这是 chip「本周建议」与"给我建议"的后端；只读不写，建议项再由 agent 转成 propose 工具。

四个工具登记进 `kKnowledgeToolDescriptors`，`./tool/check-tool-descriptors.sh` 守恒；`propose_merge` 标 `Access.propose / RiskLevel.propose / Confirmation.oneTap`（diff 在卡片内渲染，见 ② 注），其余 read 标 `Access.read / RiskLevel.info`。`kKnowledgeSystemPromptBlock` 补：录入先 `find_similar_knowledge` 查重再决定 capture / merge；"给我建议"走 `review_knowledge_health`。

### 15.4 Schema / Repo 改动

- **Schema v21→v22 迁移**：可合并表（`knowledge_notes`、`knowledge_concepts`）加 `merged_into_id TEXT?`（软删 `deleted_at` 已有）。1 条迁移。
- **`KnowledgeRepository`** 加 `mergeEntities(...)` + `findSimilar(...)`（薄包一层 `MemoryRuntime`）。
- 本地优先：录入后查重在**保存之后**异步跑（不阻塞 §15.1 路径 1 的零延迟约束）。

### 15.5 Agent 改动（不新增 agent，保持简洁）

- 把 `InboxTriageAgent` 扩成也跑**近重检测** → 给 Review tab 出「疑似重复」卡（复用 `knowledge_inbox_triage` 侧表，不碰 save 路径）。会话 surface 的查重是 pull 版，后台 agent 是 push 版。

### 15.6 分期（可独立合并、随时可停）

- **P0 — 去重闭环**：`find_similar_knowledge` + `propose_merge` + schema v22 + 录入后自动查重卡。（填补唯一能力空白，价值最高）
  - [x] schema v22（`merged_into_id` on notes + concepts，迁移 + 1 条 ALTER ×2）+ `KnowledgeRepository.mergeNotes` / `mergeConcepts`（事务内并集 + tombstone + concept 入边重指）+ 聚合 `kKnowledgeMemorySources`（2026-05-29）
  - [x] `find_similar_knowledge`（read，遍历具体 source + cosine + Jaccard token 复核）+ `propose_merge`（write，`knowledge_merge` envelope + diff，Confirmation.oneTap）+ descriptors + system prompt（2026-05-29）。测试:`knowledge_merge_repository_test`(8) + `knowledge_dedupe_tools_test`(8);更新 `contracts_roundtrip`(55) + `device_degradation` canonical 列表(顺带补全此前漏登的 routine/capture)
  - [x] `propose_merge` 接入 chat-apply（2026-05-29）：新增 shell 级 `CompositeProposalApplier`（`core/ai/composition/composite_proposal_applier.dart`，按 kind 路由 apply、按 `appliedTable` 前缀路由 undo）+ `KnowledgeProposalApplier`（`features/knowledge/composition/knowledge_proposal_applier.dart`，handle `knowledge_merge` → `mergeNotes`/`mergeConcepts`、`knowledge_routine` → `upsertRoutine`）+ kind 元数据（`knowledge_proposal_kinds.dart`，propose card 渲染 merge diff / routine 行）+ `knowledgeCompositionOverrides()`。**Riverpod 3 禁止重复 override**:Finance bundle 不再 override `proposalApplierProvider` / `proposalKindRegistryProvider`(仅暴露 `financeProposalApplierProvider` + `kFinanceProposalKinds` 供 composite 读),由 knowledge bundle 作为唯一 owner 组合 finance + knowledge。知识写不暴露 60s 一键 undo(apply 不回 `appliedAt`);merge 经 `mergedIntoId` 数据层可逆。测试:`knowledge_proposal_applier_test`(6)。
    - 顺带:这也修了 **全部 knowledge propose 工具共用的缺口**(此前 propose_* 从 chat 确认都撞 finance applier 的 "unknown kind")。
  - [x] `knowledge_concept_link` chat-apply（2026-05-29，顺手补 §14.2 待办）：`KnowledgeRepository.linkConcepts`（双向 related 边并集 + 事务）+ applier `_applyConceptLink` 分支 + kind 元数据。`knowledge_concept_link` 加入 `kKnowledgeProposalAppliedKinds`。capture / inbox 仍走 Review tab triage 侧表(非 chat-apply,符合 §5)。
- **P1 — 统一入口**（2026-05-29 落地）：Inbox 顶部新增 `_AiAssistantBar`（`knowledge_inbox_page.dart`）——一个「记点什么 / 问点什么…」录入 pill + 三枚快捷 chip（查重 / 本周建议 / 搜知识），全部经 `askAi` 会话模式打开 ai_chat surface（知识路由 → aiContext.domain = knowledge → 自动挂 `kKnowledgeDeviceTools` + `kKnowledgeSystemPromptBlock`）。
  - [x] 复用 ai_chat 引擎(`askAi` → `showAiSheet` conversation 模式)，**不新增 chat 引擎/运行时**；无 LLM runtime 时 surface 自身给登录/配置引导(沿用 ai_sheet 既有降级)。
  - [x] 三个 chip 用**会话 prefill**(强种子 prompt)而非 invocation intent —— 刻意避开 regression-corpus / renderer fixture 链(每个 invocation intent 需 corpus 条目 + renderer + preferredReadModels);send 后 agent 照常跑完整工具链。
- **P2 — 建议聚合**（2026-05-29 落地）：
  - [x] `search_knowledge`（read，跨 7 类语义检索，遍历 `kKnowledgeMemorySources` + 混合分排序）+ `review_knowledge_health`（read，聚合到期复盘 / 本周到期定期事项 / 长期未校验假设 / 孤儿笔记,按 count 排序)。descriptors + system prompt + 注册。测试:`knowledge_query_tools_test`(8)。
  - [ ] `InboxTriageAgent` 近重检测(push 版,§15.5)——pull 版已由 `find_similar_knowledge` + `review_knowledge_health` 覆盖;后台 agent 增强按 dogfood 需要再做。

每期遵守：本地优先永不阻塞 save、写必经 ProposalEnvelope、Web 优雅降级、trace 全覆盖。

### 15.7 反目标对照（确认不破 §8 / §14.3）

- ✅ **不**违反 §14.3 "保存时同步 LLM"：会话是 path-2 显式发起，快存 path-1 不变（§15.1）。
- ✅ **不**做 AI 自动生成内容（§14.3）：merge 只是 union 既有字段 + 用户卡片内确认 diff，不无中生有。
- ✅ **不**做自动双链 / 知识图谱可视化（§8）：查重/建联仍 user-confirm 单条。
- ✅ **不**新增运行时 / chat 引擎：复用 `DeviceAgentLoop` + ai_chat（§15.0）。
- ⚠ sunset 信号沿用 §14.4；若 `propose_merge` 误合并噪音 > 真信号 3 倍且阈值收敛不住，按 §12 回滚去重工具。
