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

**Drift schema**：六张表都 `with SyncableTable`，row_kind `know:{notes,concepts,principles,assumptions,decisions,experiments}`。Memory 仍走 Memory Layer 表，零新增。

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

**写 tool 全部走 ProposalEnvelope**（northstar / ai-architecture.md 行为契约）；read tool 默认可调。

**不做**（MVP）：
- AI 自动生成 Note / Decision（用户自己写 / dictate；AI 只**整理** / **关联** / **质疑**）
- AI 直接改用户笔记内容（只能 propose）

---

## 5. IA placement（Option B domain dock 下，3 tabs）

匹配 shell §3 的 Option B 双层 shell + `DomainShellSpec`（与 HealthOS Today/Trend/Plan 同模式）：

- **Inbox** — Quick capture（语音 / 粘贴 / 分享 intent）→ 自动归类 placeholder（Note / Decision draft / Concept candidate），LLM 建议但用户确认
- **Library** — Notes / Decisions / Concepts / Experiments 四 segmented control；list + detail；最高优先级是 Decision 视图（含 status badge：active / verified / falsified / overdue-review）
- **Review** — Weekly Review 卡片：to-review decisions / unverified assumptions / contradictions detected / recent agent runs

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

## 7. 三个核心 agent（complement 已有 Morning Briefing）

| Agent | Schedule | 读 | 写 |
|---|---|---|---|
| **ReviewAgent** | 每周日 09:00 local | `list_due_reviews` | Episodic memory（"X 决策已到 review 期"）+ 通知（复用 health 的 `lifeos.knowledge.review` channel） |
| **AssumptionAgent** | 月初 + 任何决策被新事件触及时 | `list_open_assumptions` + 跨域 events | Episodic memory + Review tab 卡片（不直接通知避免噪音） |
| **ContradictionAgent** | 每次新 Decision / Note 落库 | 该对象 vs 最近 90 天同 scope memories + **当前 active Principles** + 引用的 Assumptions（cosine + LLM judge） | 若检出冲突（事实/价值观偏离），写 `kind='semantic'` memory + Review tab 提示。**不**自动覆盖原对象 |

复用 shell §7.3 的 `Agent` / `AgentRunner` 框架。**反目标**：不做 "Agent 之间相互调用"（northstar §1.1 边界 / shell §7.3 反目标）。

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
- ❌ 本文档目标长度：**< 400 行**（override 后含 §14 落地快照）。改本文档前自问：是不是 dogfood 真发现需要改，而不是"完善设计"

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
- ✅ `KnowledgeRepository`（`features/knowledge/data/knowledge_repository.dart`）：6 类对象 CRUD + status 过滤 + due-review query

**AI tools**（`features/knowledge_ai_tools.dart` → `kKnowledgeDeviceTools`）
- ✅ `recall_decision`、`list_open_assumptions`、`list_due_reviews`、`search_notes`、`summarize_topic_evolution`
- ✅ `propose_concept_link`（写 tool → ProposalEnvelope，§4 行为契约）
- ✅ 通过 `deviceToolsProvider` 在 bootstrap 拼入，gated on `domainOptInsProvider.contains(DomainScope.knowledge)`

**Agents**（`features/knowledge/agents/`，复用 shell §7.3）
- ✅ `ReviewAgent`（每周日 09:00 local）
- ✅ `AssumptionAgent`（30d cadence，扫 > 90d 未校验 active 假设）
- ✅ `ContradictionAgent`（每 6h，principle mismatch + assumption invalidation 启发式）

**Memory Layer 接入**（§3 "写一份，索引两次"）
- ✅ `KnowledgeDecisionMemoryIndexer`：Decision → `kind='episodic'` Memory，跟 trade journal indexer 同模式；接入 `memoryLayerBootstrapProvider`
- ✅ Agent 输出 → `kind='episodic'` / `'semantic'` Memory（Review / Assumption / Contradiction）

**IA Shell**（§5 Option B dock，与 HealthOS 同模式）
- ✅ 3 tabs：Inbox / Library / Review (`/knowledge`, `/knowledge/library`, `/knowledge/review`)
- ✅ `knowledgeDomainShell()` + `knowledgeShellRoute()`，注入 router 顶层 ShellRoute
- ✅ Settings → Domains 加 KnowledgeOS 开关 + Inbox 深链
- ✅ 全 Forui 实现（无 Material 组件依赖）；New Note 含 Edit/Preview toggle（用 `AiMarkdown` 渲染）

**Cross-domain hooks**（§6）
- ✅ `knowledgeChatRailContentProvider`：projects 最近 3 条 Decision 进 AI chat rail

### 14.2 待办（按价值 / 紧急度排序）

**P0 — 影响 MVP 可用性**
- [ ] **Inbox quick capture pipeline**：§5 列出 share-intent / 语音 / 粘贴 / AI chat 片段，目前只有手写 New Note。share-intent 可直接复用 `features/ingest/data/share_intent_service.dart`
- [ ] **Decision 创建表单**：当前只有 Note 有写入 UI；Decision 是最高优先级 affordance（§1），必须能在 Library Decisions tab 里 `+ New decision`。Principles / Assumptions / Experiments / Concepts 也需要
- [ ] **Library detail pages**：列表项现在不可点击；至少 Decision 需要 detail view（含 supersede chain / referenced assumptions）

**P1 — 影响 §0 定位的关键功能**
- [ ] **`search_notes` 接入 hybridScore**：§4 spec 要 "全文 + 语义混合"，MVP 是 substring 扫。Notes Memory indexer + 接 Memory Layer `hybridScore` 之后启用
- [ ] **Notes / Principles / Assumptions / Experiments / Concepts Memory indexer**：当前只有 Decision 被 mirror 进 Memory；其它类型仍只在 Drift 表中，跨域 Recall 召不回
- [ ] **`Decision.context_snapshot_json` 自动抓拍**：列存在但未自动写入。需要在 `upsertDecision` 路径下读最近 Finance / Health events 拼 snapshot（不阻塞写）
- [ ] **AssumptionAgent 事件触发**：§7 spec 说 "月初 + **任何决策被新事件触及时**"。当前只有月初 cadence，事件触发需要 `EventStore` listener
- [ ] **ContradictionAgent cosine + LLM judge 路径**：MVP 是纯启发式 token 匹配，§7 spec 要语义比对。等 Knowledge Memory 全量化后切换

**P2 — Dogfood 改进**
- [ ] **Review tab "recent agent runs"**：§5 spec 列出但未渲染；需要 Agent 历史读 API
- [ ] **`lifeos.knowledge.review` 通知 channel**：§7 ReviewAgent 表里有提到，目前只写 Memory 没发通知（HealthOS 有 morning briefing 通知的实现可参考）
- [ ] **`ai_context_summary` override**：§6 列了，但现有 slot (`AiContextSummary`) 是 Finance-shaped；要么扩 slot 形态，要么换成独立的 prompt 拼接 seam
- [ ] **`propose_concept_link` 真正落地路径**：write tool 已经返回 ProposalEnvelope，但 `ProposalApplier` 还没认这个 kind。需要在 `featureProposalApplier` 里加 `knowledge_concept_link` 分支
- [ ] **Knowledge opt-out 清理**：关闭 opt-in 时 indexer 停止订阅，但已写入的 episodic memories 不清。需要明确策略（保留 vs prune），shell §5 应该有相关约定

**P3 — 工程债**
- [ ] **测试**：`test/features/knowledge/` 目录尚未建立。至少需要 repository 单测 + AI tool 单测 + agent 单测（参考 `health/test/`）
- [ ] **l10n**：所有 UI 文案当前是字面量（中/英混排）；触发 dogfood feedback 收敛后入 `.arb`
- [ ] **Sync wire prefix 修复**：`SyncEngine._toRowChange` 硬编码 `prefixFinanceTable(table)`；KnowledgeOS 表上车后 outbound 仍走 `fin:` 前缀。HealthOS 也踩这个雷（health_metrics 目前本地 only）。需要按表名查 domain → 选 prefix 的 dispatch
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

### 14.4 sunset 信号（命中即按 §12 回滚）

- 用户停止 dogfood ≥ 30 天且无重启意图
- ContradictionAgent / ReviewAgent 累计 false positive 噪音 > 真信号 3 倍且无法靠阈值收敛
- KnowledgeOS-only 代码持续增长但跨域 Recall 命中率 < 5%（说明本质是 silo，违背 §1）
- 任何一条 §8 反目标被破（即使是 "顺手加一下"），但 dogfood 又确认有价值——这是要立 ADR 而不是默默扩
