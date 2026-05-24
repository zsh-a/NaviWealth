# LifeOS Shell (跨域基础设施 SSOT)

> 本文档是 LifeOS shell 的**唯一规划入口**。覆盖跨域共享的基础设施:
> Identity / Memory / Sync / AI Runtime / Agent / Storage,以及多域 IA 形态。
>
> **不**写任何域内业务路线。Finance 域看 `roadmap-next.md`;Health 域看 `healthos-domain.md`。
>
> 上位文档: `lifeos-architecture-northstar.md` (架构约束) + `lifeos-decision-2026-05-24.md` (Phase D 触发 ADR)。

---

## 0. 定位

LifeOS = 个人数字基础设施。当前活跃域:

- **FinanceOS** (live, v0.5.x)
- **HealthOS** (Phase D-2 等待中)

未启动域 (TimeOS / KnowledgeOS / LivingOS) 走 `roadmap-next.md` §5 触发表,**不在本文档范围**。

---

## 1. Shell 包含什么

```
┌──────────────────────────────────────────────────────┐
│  Domain shell (IA / domain switcher / nav layer)    │  ← §3
├──────────────────────────────────────────────────────┤
│  Cross-domain composition (chat / agents / search)  │  ← §4
├──────────────────────────────────────────────────────┤
│  Identity (core/auth)                                │  ← §5
│  Memory (core/ai/local/embedding + vector store)     │  ← §6
│  AI Runtime + Agent (core/ai/runtime)                │  ← §7
│  Sync v2 (core/sync + apps/backend/src/sync)         │  ← §8
│  Persistence (core/persistence ← data/db)            │  ← §9
└──────────────────────────────────────────────────────┘

域内: features/<domain>/{ui,data,domain,ai_tools}/
```

每个域**只**实现 `features/<domain>/`。Shell 不感知域内业务实体。

---

## 2. Phase D 整体序列 (高层)

详细工作项见下面各章。

```
D-0  决策落地 + 文档基线                          (1 周)   ✅ 进行中
D-1  Shell foundation                            (4–6 周)
  D-1.1  Naming refactor (data/db → core/persistence)
  D-1.2  AI tool relocation (Finance tool → features/ai_tools)
  D-1.3  Intent/Trace domain 字段
  D-1.4  Sync row family namespace (fin:* / health:*)
  D-1.5  Auth domain scopes + 域级 opt-in
  D-1.6  Cross-feature composition uplift (ai_chat)
  D-1.7  Memory Layer 通电 substrate                    ✅ 落地 (vector store + embedder seam)
  D-1.7b Memory Runtime (typed + lifecycle + ContextBuilder)  ✅ 落地 (2026-05-24)
  D-1.7c Rust MiniLM embedder drop-in                   ⏳ 未做 (§6.6 步骤已列)
  D-1.8  Multi-domain IA shell
D-2  HealthOS MVP                                (8–12 周)  详见 healthos-domain.md
D-3+ 触发性 (TimeOS / Knowledge / Living)         不预排
```

**完工标准 (per phase)**: 各章 §"完工标准"。Phase D-1 全部完成才启动 D-2。

---

## 3. Domain shell (IA)

**今天**: Today / Activity / Wealth / Plan + Settings + Search (全 Finance 视角)。

**Phase D 形态选项**:

```
Option A — 顶部 domain switcher
  [Finance ▾]  Today | Activity | Wealth | Plan | Settings | Search
  切换到 [Health ▾] 后 tabs 变成 Health 视角

Option B (推荐) — 左侧 domain dock
  ┌─┬──────────────────────┐
  │💰│ Today  Activity       │
  │❤│ Wealth Plan            │
  │ │ Settings  Search        │
  └─┴──────────────────────┘
  域 icon 在左,各域有自己的 tabs

Option C — 单一 cross-domain Today + 其它 tabs 加 domain filter
  顶部 Today 跨域;Wealth/Plan 等保持 Finance;Health 内容塞进 Today
```

**当前推荐**: Option B。理由:每域 IA 自洽;桌面 master-detail 已落地,左侧 dock 与现有 layout 兼容;移动端 dock 折叠到底部 sheet。

**决策门**: D-1.8 paper prototype 后自己 dogfood 2 周,若 Option B 不顺手降级 Option A。

---

## 4. Cross-domain composition

**今天**: `features/ai_chat/data/providers.dart` 直接 import 7+ sibling features 做 chat context composition(northstar §2.4 已知例外)。

**目标 (D-1.6)**: 上提到 `core/ai/composition/chat_context_composer.dart`。每个域**注册**自己的 provider:

```dart
abstract class DomainContextProvider {
  String get domain;                          // 'finance' | 'health' | ...
  Future<DomainContext> compose(ContextScope scope);
}
```

- `features/finance/composition/finance_context_provider.dart` 注册 finance
- `features/health/composition/health_context_provider.dart` 注册 health
- `ai_chat` 不再 import 任何 feature

**完工标准**: `features/ai_chat/` 下 `grep "features/[^/]*/"` 零命中(`features/shared/` 除外)。

---

## 5. Identity (core/auth)

**今天**: 单 user JWT (HS256),无 domain 概念。

**Phase D-1.5**:

- JWT claim 增 `domains: ['finance']`(默认),允许 `['finance', 'health']`
- `core/auth/domain_scope.dart` 加 `DomainScope` enum
- Settings UI 加 "域级 opt-in" 开关:Health 默认 OFF,D-2 完成后用户手动开启
- Backend `apps/backend/src/auth/` JWT 验证读取 domains claim,sync 路由按 domain filter

**兼容**: JWT 缺失 domains claim 默认 `['finance']`,旧 client 不破。

---

## 6. Memory Runtime

> **Phase D-1.7b 落地** (2026-05-24): 升级为"长期上下文运行时",不再是"语义化全文索引"。Schema v17 拆分,引入 typed records + lifecycle + Context Builder。

### 6.1 五种 Memory 抽象

按用户原始设计(2026-05-24 review)落地 4 个 memory kind + 一个独立 event log:

| Kind | 用途 | 抽取触发 | 例 |
|---|---|---|---|
| **event** | "发生了什么" | 每条 trade journal 入库 | `trade_closed`: NVDA put closed at 70% credit |
| **semantic** | 长期事实 / 偏好 | 用户配置 / AI 提炼(尚无 caller) | "user prefers local-first" |
| **episodic** | 决策 + 推理 + 结果 | 终态 trade(closed/assigned/expired)抽取 | "closed NVDA put early: IV 回落, 风险收益比下降" |
| **procedural** | 规则 | 用户配置 / AI 提炼(尚无 caller) | "当 put 收益 >= 70% 考虑平仓" |
| **events 表** | 时间线主干 | 任何 indexer 写入 | 与 memories 分离;cheap, abundant;不带 confidence/lifecycle |

### 6.2 数据形状

```
events                                 memories                          memory_embeddings
─────────                              ──────────                        ──────────────────
id          PK                         id                  PK            memory_id    PK (FK CASCADE)
type        free string                kind                event|sem|...  fingerprint  Embedder.fingerprint
timestamp   millis                     scope               '*' | 'options_trading' | ...  dimension
source      'options_trade_journal'    owner_user_id                     vector_bytes Float32 LE BLOB
owner_user_id                          source/sourceId/sourceEventId
title/summary                          title/summary       (summary embedded)
payload_json                           payload_json        kind-specific
entities_json                          entities_json       boost match
importance                             importance/confidence
                                       valid_from/valid_until
                                       created_at/updated_at/last_accessed_at
```

- `memory_embeddings` 是 1:1 FK 侧表 —— **embedder swap 不必动 records**,只 drop 旧 fingerprint 的 vectors 即可触发 reindex
- 所有表都在 `local_only_tables.dart`,**不进 sync**(derived data,re-indexable)
- `scope='*'` 是 wildcard:在任何具体 scope 查询里都会命中(适合通用偏好)

### 6.3 Runtime API (`core/ai/local/memory/`)

| 模块 | 责任 |
|---|---|
| `embedder.dart` (`embedding/`) | `Embedder` 抽象 + fingerprint 守门;`StubEmbedder` 默认 |
| `memory_store.dart` | `MemoryStore` 抽象 + `SqliteMemoryStore` 实现(JOIN memories + memory_embeddings) |
| `event_store.dart` | `EventStore` + `SqliteEventStore` |
| `hybrid_scorer.dart` | 纯函数 `hybridScore = 0.35*sem + 0.25*imp + 0.20*ent + 0.10*rec + 0.10*con` + `entityOverlap` (Jaccard) + `recencyScore`(指数衰减) |
| `memory_runtime.dart` | composition root:`remember / recall / forget / supersede / recordEvent / recentEvents / dropStaleVectors` |
| `context_builder.dart` | 按 5 槽组装 `ContextPackMemory{user_preferences, applicable_rules, related_decisions, recent_events, related_events}` |
| `providers.dart` | Riverpod 接线 —— 跨域中立,**不**import `features/` |

### 6.4 Extractor:从 raw → typed memory

第一个 caller `features/options_income/data/trade_journal_memory_indexer.dart`:

```
TradeJournalEntry  →  always emit event (trade_opened/closed/assigned/expired)
                  →  if terminal status: also emit episodic memory
                       payload = {context, decision, reasoning, outcome}
                       importance heuristic: assigned 0.75 > closed 0.6 > expired 0.5
                                            +0.1 if notes attached, +0.05 if |pnl|/credit >= 1
                       confidence: 0.9 with notes, 0.75 otherwise
```

**故意 defer**:semantic / procedural 自动抽取 —— 需要跨多条 entry 的模式检测,等 AI Chat 接 extractor 之后再做。当前 schema 允许这两种 kind 写入,只是没有自动 caller。

### 6.5 Device AI tools

| Tool | 用途 | 输入 | 输出 |
|---|---|---|---|
| `build_context` (推荐) | 按 5 槽分类的 ContextPack | `{query?, entities?, scope?, kinds?, per_slot_limit?}` | `{user_preferences, applicable_rules, related_decisions, recent_events, related_events}` |
| `query_memory` (back-compat) | 扁平 hybrid-ranked hit 列表 | `{query, kind?, source?, top_k?}` | `{hits[{id, kind, source, title, excerpt, score, semantic_sim, entity_overlap, recency, importance, confidence}]}` |

LLM 应**优先**调 `build_context`(回答涉及"以前 / 上次 / 我当时为什么 / 我的偏好"等问题);`query_memory` 留作模糊 fallback。

### 6.6 Rust MiniLM drop-in (D-1.7c, 未做)

唯一剩余的 Rust 工作:

1. 新建 `apps/mobile/native/lifeos_native/` 单 crate,`fastembed-rs` 或 `candle`
2. FFI 表面只 1 个函数:`embed(text: String) -> Vec<f32>`(tokenizer 同 crate)
3. Dart 侧 `RustMinilmEmbedder implements Embedder`, `fingerprint => 'minilm-l6-v2-d384'`
4. `bootstrap.dart` `embedderProvider.overrideWithValue(RustMinilmEmbedder(...))`
5. `runtime.dropStaleVectors()` 清旧 → 下次 indexer cycle 自动用真模型重 embed
6. **memory/event records 不动**(架构债已经在 D-1.7b 提前还掉)

### 6.7 第二域接入路径 (D-2.4 HealthOS)

```
1. 写 features/health/data/sleep_memory_indexer.dart (复制 trade_journal 模板)
2. 在 memory_indexers_bootstrap.dart 加一行: ref.watch(sleepDailyMemoryIndexerProvider);
3. emit events 用 source='health:sleep' / type='sleep_session_ended'
4. emit episodic memories 用 scope='health'
5. Memory Layer 本身完全不动 —— scope='health' 和 scope='options_trading' 在同一张表共存
```

### 6.8 反目标(D-1.7b 故意没做)

- ❌ Memory links 表(图结构) —— Context Builder 已够用,等真的不够再加
- ❌ Auto-summarisation / agent self-reflection —— Extractor 用 deterministic heuristics
- ❌ Embedding everything raw —— Extractor 是写入门
- ❌ 把 memory 模块整个 Rust 化(`lifeos-shell.md` §10 边界仍然成立)

### 6.9 测试覆盖

D-1.7b 总计 **~120 测试**:

- `test/core/ai/contracts/memory_record_test.dart` — 8 (kind wire + JSON roundtrip)
- `test/core/ai/local/memory/hybrid_scorer_test.dart` — 18 (weights / Jaccard / decay)
- `test/core/ai/local/memory/memory_store_test.dart` — 17 (CRUD / query filters / fingerprint / scope wildcard)
- `test/core/ai/local/memory/event_store_test.dart` — 8 (CRUD / time / type / entity / owner)
- `test/core/ai/local/memory/memory_runtime_test.dart` — 11 (recall / supersede / events / drop stale)
- `test/core/ai/local/memory/context_builder_test.dart` — 7 (slot classification / scope / kindHints / limit)
- `test/features/options_income/data/trade_journal_memory_indexer_test.dart` — 8 (event emission / importance / idempotency / owner / back-pointer)
- `test/core/ai/runtime/device/tools/query_memory_tool_test.dart` — 7
- `test/core/ai/runtime/device/tools/build_context_tool_test.dart` — 6

Plus updated descriptor/registry tests (catalog → 37 tools).

---

## 7. AI Runtime + Agent

**今天**: `core/ai/runtime/` device-only multi-profile,34 个 device tool 全在 `core/ai/runtime/device/tools/` (northstar §2.2 已知例外)。

### 7.1 Tool 分层 (D-1.2)

- 所有 finance 业务 tool 迁出: `core/ai/runtime/device/tools/*` → `features/<finance-area>/ai_tools/*`
- `core/ai/runtime/` 只剩 provider-neutral runtime + `ToolDescriptor` 抽象
- `DeviceToolRegistry` 成为 composition root,启动时收集各域 `ai_tools/`
- CI gate: `tool/lint-no-finance-in-core.sh` 阻止 `core/ai/runtime/` 出现 `features/` import

### 7.2 Intent / Trace domain 字段 (D-1.3)

- `AiIntentInvocation.domain: String` (default `'finance'`,migration 写所有现存 trace)
- `ToolDescriptor.domain: String` (catalog 按域分组)
- `AiTrace.intent.capability` 允许非 finance 值

### 7.3 Agent runtime (D-4,D-2 之后)

- 已有:device session + tool dispatcher + Opik 风格 trace
- 加:`core/ai/agents/scheduled_agent.dart` (cron-driven autonomous agent)
- 第一个跨域 agent: **Morning Briefing** (D-2.5,见 `healthos-domain.md`)

**反目标**: 不做"通用 agent 平台"。Agent runtime 服务 1–2 个具名 use case,不开 general API。

---

## 8. Sync v2 row family namespace

**今天**: `sync_rows.row_kind` 是裸表名(`account` / `journal_entry` / ...)。

**Phase D-1.4**: 加域 namespace 前缀:

- `account` → `fin:account`
- `journal_entry` → `fin:journal_entry`
- 未来 Health: `health:sleep_session` / `health:heart_rate_daily`

**Backend**: `apps/backend/src/sync/store.rs` 仍 schema-agnostic,只是按 row_kind 前缀分片(同一 user 内)。

**Migration**: 一次性 SQL `UPDATE sync_rows SET row_kind = 'fin:' || row_kind WHERE row_kind NOT LIKE '%:%'`。Client 端 `SyncEngine` 写入时统一加前缀。

**完工标准**: `SELECT DISTINCT row_kind FROM sync_rows` 全部带前缀;backend dry-run 测试通过。

---

## 9. Persistence

**Phase D-1.1 rename**:

- `data/db/` → `core/persistence/` (跨域 storage adapter)
- `data/domain/` → `features/finance/data/domain/` (Finance 业务实体)
- `data/audit/` 跨域 → `core/audit/`
- `data/market/` Finance 专属 → `features/finance/data/market/`
- `data/securities_catalog/` Finance 专属 → `features/finance/data/securities_catalog/`
- `data/repositories/providers.dart` 内 Finance providers 拆出去

**风险**: 全仓 import path 改动。Mitigation:

- 单次机械化 PR + 全量 test + golden 保护
- `dart fix` + 手工脚本批量改 import
- 不允许"顺手优化"

---

## 10. Rust 边界(重要)

**原则**: northstar §1.3 允许"局部 FFI",**不允许** AppFlowy 式宽口径 pivot。Rust 入选必须**同时满足**:

1. 真正的 perf / 安全 delta(不是"理论上更快")
2. Caller 已存在或当前 phase 出现
3. FFI 表面窄到 `flutter_rust_bridge` 自动生成
4. 不强制引入 web wasm32 流水线

### 10.1 Phase D Rust 模块清单

| 模块 | 进 Rust? | 时机 | Crate |
|---|---|---|---|
| Memory Layer embedder | ✅ 是 | D-1.7 | `fastembed-rs` 或 `candle` |
| Memory Layer tokenizer | ✅ 是 | D-1.7 (同 crate) | `tokenizers` |
| Vector ANN | ❌ 否 (MVP) | > 50k 条目触发 | `usearch-rs` |
| Sync E2EE | 🟡 触发后 | sync v2 稳定 ≥ 1 月触发 | `age` 或 `libsodium-sys-stable` |
| 其它 D-1.x / D-2.x | ❌ 否 | — | (留 Dart) |

### 10.2 Mobile Rust 布局

```
apps/mobile/native/
└── lifeos_native/         # 单一 crate
    ├── Cargo.toml
    └── src/
        ├── lib.rs         # flutter_rust_bridge entry
        ├── embedder.rs
        ├── tokenizer.rs
        └── crypto.rs      # D-3 触发后
```

对照 AppFlowy 的 20+ crate(`flowy-document` / `flowy-database2` / `flowy-search` / `flowy-ai` / ...):我们**只一个 crate, 2–3 模块**。

### 10.3 FFI 工具

- 选 **`flutter_rust_bridge`**(自动 Dart binding)
- **不**做 AppFlowy 的自建 FlowySDK + protobuf event dispatch(那是为宽 FFI / 团队产品设计的)

### 10.4 Web

- Memory Layer 在 web 降级到文本搜索(不编译 wasm32)
- 未来 E2EE 在 web 用现有 Dart `cryptography` 包

### 10.5 反目标 (永远不上 Rust)

- 本地 LLM inference(user 自带 key,不养模型)
- Quant 计算 / Money math(Dart Decimal 够)
- SQLCipher / FTS5(已有 C 实现)
- 市场数据 fetcher(HTTP + JSON)
- 业务 tool 逻辑(永远是 Dart)

---

## 11. CI gates (Phase D-1 落地后强制)

| 脚本 | 检查 |
|---|---|
| `tool/lint-no-finance-in-core.sh` | `core/ai/runtime/` 禁止 `import 'package:.../features/'` |
| `tool/lint-cross-feature-imports.sh` | `features/<A>/` 禁止 import `features/<B>/`(`shared` 例外) |
| `tool/lint-row-family-prefix.sh` | `sync_rows.row_kind` insert 必须带 `<domain>:` 前缀 |
| `tool/lint-domain-neutral-contracts.sh` | `core/ai/contracts/` / `core/sync/` 不出现 finance/health 业务词 |

详细脚本在 D-1 落地时添加到 `tool/`。

---

## 12. 与现有文档关系

| 文档 | 角色 |
|---|---|
| `lifeos-architecture-northstar.md` | 架构约束 SSOT;本文档**遵守**它,不重复 |
| `lifeos-decision-2026-05-24.md` | Phase D 触发 ADR;本文档**承接**它 |
| `healthos-domain.md` | 第一个域 SSOT;不在本文档 |
| `roadmap-next.md` | Finance 域路线 + Phase D 调度状态指针 |
| `ai-architecture.md` | AI 现状 SSOT;Phase D §7 是它的演进规划 |
| `sync-v2.md` | sync 协议 SSOT;Phase D §8 是它的 namespace 扩展 |

---

## 13. 使用方式

- 改本文档前自问:是 shell 跨域基础设施的变更?还是某个域内业务?后者去对应域 SSOT
- 写新域 SSOT 前自问:northstar §4 触发条件成立了吗?ADR 写了吗?
- 本文档目标长度: **< 300 行**(当前在限内)。超出意味着在写域内细节,应该回流到域 SSOT
