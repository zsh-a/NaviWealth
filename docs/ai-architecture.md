# NaviWealth AI 架构

> 状态: Phase 1–4 已落地（contracts + router + trace + skills + query plan + semantic memory），**Read Models 三层主通道已贯通**（Snapshot 全部 / Analytical 5/6 / Scoped Detail 三表），Phase 5（端侧 LLM）未实现。
> **Wave 进度**: Wave 1–17 完成 — 详见 §7 实现状态表。剩余主线: `subscription_changes` (Analytical P1)、`asset_allocation_snapshot` (Snapshot P1)、Runtime 抽象、Phase 5。
> 适用范围: `lib/core/ai/` (Flutter) 与 `apps/backend/src/ai/` (Rust Worker)。

---

## 1. 设计哲学

```text
Device AI = Copilot / Context Layer
Cloud AI  = Brain   / Orchestrator
Router    = 在二者之间按能力 / 风险 / 隐私 / 在线性 / 延迟选择
```

不是「端 vs 云二选一」，而是 **分层协作**：

- **端**: 高频、低延迟、强隐私的小推理（分类 / 搜索 / 摘要 / context 压缩 / 局部决策）。
- **云**: 多步推理、跨期分析、proposal 生成、复杂工具编排，**主数据源是 D1 上的预计算 Read Models**。
- **路由**: 一个集中、纯函数式的 Router 决定每个意图走哪条路；未来端侧能力变强后只换 runtime 不动业务。

数据流上分四条通道，**主通道是云端 Read Models**，端-云交互只在三个特定 gate 触发：

```text
主通道  = Cloud AI Read Models       (90%+ 流量)
辅助通道 = ContextPack                (端侧派生信号 / 偏好 / 路由 / freshness hint)
兜底通道 = ScopedDisclosure           (freshness gate / privacy gate / draft gate)
确认通道 = ProposalEnvelope           (任何高风险写入；现有 FIR-66 即此通道)
```

口号: **「端侧工具不是主数据通道，而是隐私与新鲜度的补充通道」**。

## 2. 六条架构原则

1. **D1 是云端 AI 的真值源**: 同步已经把数据搬到 D1，云端 planner 应直接读 D1 上的预计算 read models，而不是绕回端侧拿数据。
2. **副作用分级 > 是否写入**: `ProposalEnvelope` sealed 类按副作用分四类（local-immediate / local-proposal / cloud-proposal / external），路由由副作用决定，而非「读还是写」。
3. **风险纳入路由**: Router 决策矩阵 = `capability × privacy × latency × offline × cost × risk`。同样一条 `write` 意图，commit 与 propose 路由不同。
4. **代码强制 > Prompt 强制**: ToolDescriptor 元数据 + `risk_policy` 在 dispatcher 层拦截违规调用；不依赖 system prompt 的「口头约束」。脱敏（bucket / hash）发生在 Worker 内部，**不**在端-云之间。
5. **透明度可见**: 每次 AI 应答都生成 `AiTrace`（本地存储，不同步），用户可见徽章："本地数据 + 云端推理 · 未上传原始交易明细"。
6. **Runtime 可插拔**: Router 依据「能力 + 风险 + 隐私」选择 runtime，而非把任务写死给 device 或 cloud。Stage 2 端侧 analyst / Stage 3 端侧 planner 出现时只换 runtime 注册不动 router 调用方。见第 4.4 节。

## 3. 四条通道

```text
┌──────────────────────────────────────────────────────────────────┐
│              UI / Feature Surfaces                                │
└────────────────────┬─────────────────────────────────────────────┘
                     │ AiRequest { intent, context }
                     ▼
┌──────────────────────────────────────────────────────────────────┐
│ AI Router  (lib/core/ai/router/)                                  │
│   纯函数 decideRouting() → 选 AiRuntime → seedTrace()             │
└──┬───────────────────────────────────────────────────────────────┘
   │ 通过 RuntimeRegistry 选择
   ▼
┌──────────────────────────────┐    ┌────────────────────────────┐
│ Device Runtime               │    │ Cloud Runtime              │
│ (DeviceAiRuntime)            │    │ (CloudAnthropicRuntime)    │
│  • Skills (rules)            │    │  • Anthropic Planner       │
│  • QueryPlan executor        │    │  • Tool Orchestrator       │
│  • SemanticMemory            │    │                            │
│  • LocalWrite/Undo           │    └────────┬───────────────────┘
└────────┬─────────────────────┘             │
         │                                   │
         │ ContextPack (辅助通道)            │
         │ ◄─────────────────────────────────┤
         │                                   ▼
         │  ┌────────────────────────────────────────────────┐
         │  │  Worker Tools (read-only D1 query)              │
         │  │   ────────────────                              │
         │  │  ★ Cloud AI Read Models  (主通道)               │
         │  │  • holdings_snapshot                            │
         │  │  • net_worth_snapshot                           │
         │  │  • monthly_spend_by_category                    │
         │  │  • cashflow_buckets / xirr_snapshot / ...       │
         │  │  ↑ refreshed_at + source_hlc_watermark          │
         │  │  ↑ schema_version + calculation_version         │
         │  └────────┬───────────────────────────────────────┘
         │           │ source HLC watermark
         │           ▼ (用于 freshness gate)
         │  ┌────────────────────────────────┐
         │  │  D1: journal_entries / postings │ ← OpLog (HLC) ← Drift (端)
         │  └────────────────────────────────┘
         │
         ▼ (例外路径)
┌──────────────────────────────────────────────────────────────────┐
│ Cloud Freshness/Privacy Gate (兜底通道)                            │
│   Cloud → request_freshness_refresh / request_disclosure          │
│   Device → ScopedDisclosure (anonymise + return minimal patch)    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Confirmation Gate (确认通道)                                       │
│   Cloud/Device → ProposalEnvelope → User confirm → Local Apply    │
│                  → OpLog → 主通道路径再生效                        │
└──────────────────────────────────────────────────────────────────┘
```

每条通道触发条件：

| 通道 | 触发 | 频率 |
|------|------|------|
| **主通道** | 任何云端推理 / 工具调用 | 默认 |
| **辅助通道** | 任何 chat 请求（端侧装 ContextPack 一并上传） | 默认 |
| **兜底通道** | freshness gate (HLC watermark 落后) / privacy gate (账户标记不上云) / draft gate (未同步附件) | 罕见 |
| **确认通道** | 任何 high-risk proposal（read 不走） | 按需 |

## 4. 核心契约（双侧镜像）

| 契约 | Dart 路径 | Rust 路径 | 用途 |
|------|-----------|-----------|------|
| `ContextPack` | `lib/core/ai/contracts/context_pack.dart` | `apps/backend/src/ai/context/context_pack.rs` | 辅助通道；端侧派生信号 + 偏好 + 路由 + freshness hint |
| `BaseContext` / `TaskContext` | 同上 | 同上 | 拆分稳定层 + 任务层 |
| `PrivacyBudget` (small/standard/large) | `privacy_budget.dart` | `context_pack.rs` | 4KB / 16KB / 64KB 字节硬上限 |
| `DisclosureRequest/Response` | `scoped_disclosure.dart` | `disclosure.rs` | 兜底通道；freshness/privacy/draft gate 触发的最小补丁协议 |
| `ToolDescriptor` | `tool_descriptor.dart` | `policy/tool_policy.rs` | access × risk × confirmation × tier × allowed_runtimes |
| `ProposalEnvelope` (sealed) | `proposal_envelope.dart` | — (端侧消费) | 确认通道；副作用分级写入 |
| `AiTrace` | `ai_trace.dart` | — (端侧本地) | 路由决策 + 工具调用 + 时长审计 |
| `IntentHint` | `intent.dart` | `context_pack.rs` | 路由输入 |
| **Read Model schema** | — | `read_models/<name>.rs` (★ 待建) | 主通道；预计算视图 + HLC watermark + version |

### 4.1 ContextPack 双向契约

ContextPack 不再是「端→云的请求体」，而是 runtime-neutral 的「输入契约」 — 任何 AiRuntime 都消费它，区别只在 producer：

| Producer | 数据来源 |
|----------|---------|
| `DeviceAiRuntime` | Drift + 本地 SemanticMemory |
| `CloudAnthropicRuntime` | D1 Read Models + （未来）云端 SemanticMemory |
| `HybridRuntime` | 端侧 ContextCompressor → 云端再补 read model |

```text
ContextPack
├── version            (major.minor; major 不匹配直接 4xx)
├── BaseContext        (稳定，可缓存) — D1 之外的「偏好」面
│   ├── preferredCurrency / riskPreference / fireGoal
│   └── (★ 收缩) 不再带 cashflow / accounts 摘要 —
│       那些来自 Read Models
├── TaskContext        (每次请求重建)
│   ├── RouteContext (path + area)
│   ├── IntentHint (capability × risk × sideEffect × label)
│   ├── RecentSignal[] (端侧 detector 产物：异常/订阅/退款)
│   ├── SemanticHit[]  (Phase 4: RAG top-k)
│   ├── ScopedAggregate[] (★ 仅当端侧已有现成聚合且 D1 没有时使用)
│   └── ★ FreshnessHint { lastLocalEditAt, lastLocalHlc }
└── PrivacyBudget      (small/standard/large)
```

**约束**: `ContextPack.assertBudget()` 拒绝超出 tier 字节上限的 pack。预期收缩后 standard tier 远低于 16KB 上限。

### 4.2 ScopedDisclosure（兜底协议）

> **ScopedDisclosure is not a primary data path. It is an exceptional mediation protocol.**

仅在三个 gate 触发时使用，普通 chat 流量永远不走它：

| Gate | 触发条件 | 触发频率 |
|------|---------|---------|
| **Freshness gate** | 端侧 `lastLocalHlc > read_model.source_hlc_watermark` | 用户刚录入但 push 还没完成的窗口（秒级） |
| **Privacy gate** | 用户标记某账户/类目「不上云」(★ 未来 feature) | 仅当该 feature 启用 |
| **Draft gate** | 未保存/未同步的本地草稿、附件、OCR 结果 | 罕见 |

协议流程：

```text
Worker 工具返回 tool_result 时附带 freshness 元数据
  → SSE 帧:
    {
      "data": { /* 实际结果 */ },
      "freshness": {
        "read_model_hlc": "01939...",
        "schema_version": 3,
        "calculation_version": 2
      }
    }
  → 端侧检查 device.lastLocalHlc > freshness.read_model_hlc
    或 schema_version 不匹配
  → 命中则触发 cloud emit request_disclosure
  → PrivacyGate 决策（首次/大范围弹 consent；session 已授权放行）
  → 端侧从 Drift 读最小补丁 → 按 anonymization 脱敏 → 截断到 max_rows
  → DisclosureResponse 回发；rows 不进端侧持久层
  → AiTrace 记录 (purpose / row_count / consent)
```

**铁律**:
- 脱敏在端侧执行，云端不可信。
- `LedgerField` 是白名单 enum；未知 field 直接丢弃。
- 任何 disclosure（即便 denied）都写入 AiTrace；`usedRawLedger=true` 即触发 UI 徽章变化。
- 兜底通道**不替代**主通道；先尝试 read model，失败再 disclosure。

### 4.3 Cloud AI Read Models（主通道，★ 待建）

NaviWealth 当前缺少这一层。现状：

- `get_holdings` / `compute_net_worth` / `get_industry_breakdown` 每次从 `journal_entries` 现算 — 浪费 D1 CPU，无 freshness 元数据，无版本化
- `get_journal_entries` 接受较宽 filter（unit / account_id / 日期 / limit≤200），实质上是受限度但**仍偏向 raw ledger scan** 的接口

目标不是「snapshot only」也不是「直接查 journal_entries」，而是 **三层访问模型**。

#### 4.3.1 三层访问模型

```text
┌──────────────────────────────────────────┐
│ Layer 1 — Snapshot                       │ ← AI 默认入口
│   小、快、稳定、跨期增量更新                │   90% chat 流量
│   holdings / net_worth / monthly_spend...│
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│ Layer 2 — Analytical                     │ ← AI 最爱消费
│   预分析的结构化中间结果                    │   token 密度高
│   recurring / anomaly / xirr / cluster   │   语义清晰
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│ Layer 3 — Scoped Detail                  │ ← drill-down 才启用
│   必填 filter + 硬限额 + 预聚合 summary    │   答 "为什么/哪些"
│   read_transaction_slice / window_*      │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│ Raw Write-side Truth (D1)                │
│ journal_entries / postings               │   ★ AI 永远不能直接访问
└──────────────────────────────────────────┘
```

**强制访问规则**:

| 场景 | 允许哪一层 | 工具示例 |
|------|----------|---------|
| AI 默认（routine chat） | Snapshot + Analytical | `get_holdings` / `get_anomaly_flags` |
| Drill-down（"为什么餐饮暴涨"） | + Scoped Detail | `read_transaction_slice(category=Dining, range=...)` |
| 自由 SQL / `SELECT * FROM journal_entries` | **永远禁止** | — |

为什么不能只有 Snapshot：AI 看不到 detail 时只能胡猜「为什么」。
为什么不能直接 raw ledger：token 爆炸 / prompt injection（恶意 memo 可能改 LLM 行为）/ 隐私边界失控 / planner 自由 scan 成本失控。

#### 4.3.2 Layer 1 — Snapshot

特点: 小、快、稳定、跨期增量更新。

| 表 | 业务定义 | 优先级 |
|----|---------|-------|
| `holdings_snapshot` | per-asset 净持仓 + 市值 + 成本基础 | P0 |
| `net_worth_snapshot` | per-day 净资产单值 | P0 |
| `monthly_spend_by_category` | 月 × 类目 的总额 + 笔数 | P0 |
| `cashflow_buckets_6m` | 近 6 月 inflow/outflow 桶 | P1 |
| `asset_allocation_snapshot` | 当前类别 / 地理 / 市值分布 | P1 |

适合的查询: "本月支出多少" / "净资产趋势" / "股票占比" / "现金流"。

#### 4.3.3 Layer 2 — Analytical

特点: 预分析的结构化中间结果。**AI 最适合消费的层** —— 比 snapshot 更有解释力，比 raw ledger 更安全。

| 模型 | 结构示例 | 优先级 |
|-----|---------|-------|
| `recurring_patterns` | `{ merchant, frequency, last_amount, trend }` | P1 |
| `anomaly_flags` | `{ category, delta_pct, reason_hint }` | P1 |
| `refund_links` | `{ original_txn_id, refund_txn_id, amount_minor, currency }` | P1 |
| `transfer_links` | `{ from_txn_id, to_txn_id, amount_minor, currency }` | P1 |
| `investment_performance` | `{ asset_id, asset_currency, base_currency, as_of, quantity, cost_basis_in_base, market_value_in_base, unrealized_pnl_in_base, weight, holding_days? }` | P1 |
| `subscription_changes` | `{ merchant, prev_amount, new_amount, since }` | P1 |
| `spending_clusters` | `{ cluster, transactions, total }` (e.g. "Japan Trip") | P2 |
| `goal_progress_projection` | FIRE 进度 + 残余年数预测 | P2 |
| `tax_lot_analysis` | per-lot 实/未实现盈亏 | P2 |
| `financial_behavior_profile` | 储蓄率 / 风险偏好 / 节奏 | P2 |

注：`recurring_patterns` / `anomaly_flags` 在端侧也有同名 detector（rules 实现）。**端侧是唯一的计算者**；云端 read model 是端侧上报后的快照投影而非重算结果，避免 Dart/Rust 两份启发式漂移。同步路径：端侧 detector 跑 → ContextPack 上报 → backend 写入 read model 表（带 `source_device_id`）。

#### 4.3.4 Layer 3 — Scoped Detail

> 这是 raw ledger scan 的唯一替代。`get_journal_entries` 应被废弃。

特点: 仅在 drill-down 触发时启用；必填 filter、硬限额、与预聚合 summary 同发、字段 sanitised。

工具示例:

```rust
read_transaction_slice(
    category: String,                // 必填
    range: DateRange,                // 必填，最大 31 天窗口
    limit: u8,                       // 1..=50
    merchant: Option<String>,
    account_id: Option<AccountId>,
    purpose: DisclosurePurpose,      // drill_down_anomaly / cluster_explain / refund_check / ...
)
```

返回:

```json
{
  "summary": { "count": 34, "total_minor": 120000, "currency": "USD" },
  "transactions": [
    { "merchant_hashed": "h_xxx", "amount_minor": 1250, "date": "2026-04-02" }
  ],
  "freshness": { "read_model_hlc": "01939...", "schema_version": 1 }
}
```

铁律:

- **必填 filter** —— 没有 category/range 就拒绝调用
- **硬限额** —— 一次返回 ≤ 50 行；分页必须新 tool_call
- **预聚合 summary 优先** —— 即便明细给了，先给 summary 让 LLM 优先消费聚合
- **sanitised 字段** —— `merchant_hashed` / `account_kind` 而非名字
- **purpose-bound** —— 每次调用必须声明 `purpose`，写入 AiTrace
- **policy 强制** —— `risk_policy` 在 enforced 模式下检查 purpose 与意图匹配

工具栈替换关系:

| 旧 | 新 | 说明 |
|----|----|------|
| `get_journal_entries(unit, account_id, from, to, limit≤200)` | `read_transaction_slice` 系列 | 旧工具的"按 unit 过滤"等用法分别落到 `read_asset_window` / `read_account_window` / `read_category_window` |

#### 4.3.5 Schema 公约（三层共享）

每个 read model 表必须有：

```sql
source_hlc_watermark TEXT NOT NULL,    -- freshness gate 真值（HLC，非 wall-clock）
refreshed_at TEXT NOT NULL,            -- ISO 时间戳，仅做 debug
schema_version INTEGER NOT NULL,        -- 列结构版本
calculation_version INTEGER NOT NULL,   -- 算法版本，改算法就 +1
```

`source_hlc_watermark` 用 HLC（NaviWealth 同步真值时序）—— wall-clock 在多设备场景容易被时钟漂移误导。

#### 4.3.6 三档刷新策略

不是所有 read model 都需要写后立即刷新：

| 档 | 触发 | 适用 |
|----|------|------|
| **同步刷新**（write 路径直接更新行） | journal_entries / postings 写入 | Snapshot 层 hot rows（当前月 / 当前日 / 持仓） |
| **异步队列**（Worker queue 触发） | 批写后异步重算 | Snapshot 冷区 + Analytical 大部分（recurring / anomaly / subscription_changes） |
| **夜间 cron** | 定时任务 | Analytical 重算成本高的（cluster / tax_lot / behavior_profile） |

**关键**: write 路径不能被 AI projection 拖慢。允许短暂 stale，由 freshness gate 兜底。

### 4.4 Runtime 抽象（可插拔执行层，★ 待重构）

Router 决策不应该写死成「这条意图走 device」，而是「该意图需要这些能力 → 注册表里哪些 runtime 满足」。

```dart
// lib/core/ai/runtime/ai_runtime.dart  (待新增)
abstract class AiRuntime {
  String get id;                       // 'device-rules' / 'cloud-anthropic' / 'device-llm-mlc'
  RuntimeCapabilities get capabilities;
  Future<AiResult> run(AiRequest request);
}

class RuntimeCapabilities {
  final Set<Capability> capabilities;     // {classify, search, summarize, plan, ...}
  final Set<RiskLevel> maxRisk;
  final bool requiresOnline;
  final BudgetTier maxContextTier;
  final int? planHorizonSteps;            // null = 不支持 multi-step planning
  final bool supportsToolUse;
}
```

```dart
class AiRouter {
  RoutingDecision decide(RoutingInputs inputs) {
    final required = _intentRequirements(inputs.intent);
    final candidates = _registry.runtimesServing(required);
    return _policy.pick(candidates, inputs);  // 按 latency/privacy/cost 排序
  }
}
```

#### 演进路线（端侧能力随时间增强）

| Stage | 能力范围 | 状态 |
|-------|---------|------|
| **Stage 1 — Copilot** | classify / search / summarize / compress context | ✅ 已实现（rules + ContextCompressor） |
| **Stage 2 — Analyst** | local cashflow analysis / FIRE quick estimate / anomaly explanation / budget suggestion | 待实现，依赖 device LLM |
| **Stage 3 — Planner** | 端侧生成 ProposalEnvelope / 多步本地推理 / 财务情景模拟 | 远期 |
| **Stage 4 — Agent** | 端侧 tool orchestration / 离线 workflow | 远期，可选云端 |

每个 stage 通过同一套 `Router + Runtime + ToolRegistry + ProposalEnvelope` 承载 — Router 调用方完全不感知。

#### 当前 Backend 枚举的迁移路径

`AiTrace.backend` 字段（`device | cloud | hybrid`）保留为审计 label，**不再是路由决策的输出**。`RoutingDecision` 改成携带 `runtime: AiRuntime` 引用；`Backend` 枚举只在 trace 序列化时由 runtime id 反向映射。

#### Tool Registry 端云同构

`ToolDescriptor` 加两个字段：

```rust
pub struct ToolDescriptor {
    pub name: &'static str,
    pub access: Access,
    pub risk: RiskLevel,
    pub requires_confirmation: Confirmation,
    pub allowed_context_tier: BudgetTier,
    // ★ 新增
    pub allowed_runtimes: AllowedRuntimes,  // device_only | cloud_only | both
    pub side_effect: SideEffectScope,        // 与端侧 IntentHint 用同一 enum
}
```

未来 Stage 2 加 `query_local_ledger` 时 `allowed_runtimes = device_only`；`execute_broker_trade` 是 `cloud_only + typed confirmation`。

### 4.5 ProposalEnvelope（确认通道，按副作用分级）

> Confirmation Gate is implemented by the existing FIR-66 ProposalEnvelope flow. 不需要重做。

| 子类 | 应用层 | 确认 | 适用场景 |
|------|--------|------|----------|
| `LocalImmediateWrite` | 端侧立即应用 + 30s undo | 无确认 | 备注、tag、手动分类、dismiss |
| `LocalProposal` | 端侧 staged，用户 review | one-tap | 批量重分类、草稿预算 |
| `CloudProposal` | 云端生成，复用现有 `proposal_applier` 流 | one-tap | 跨账户重平衡、FIRE 调整 |
| `ExternalSideEffect` | 触达外部（broker/bank） | typed | broker 下单、对公转账 |

`ExternalSideEffect` 永远 **不能**由 LLM 自动触发 — 必须用户主动点击。

未来 Stage 3 端侧也能产 proposal，所以 envelope 加：

```dart
sealed class ProposalEnvelope {
  final String proposalId;
  final String kindLabel;
  final ProposalSource source;  // ★ device | cloud | hybrid
}
```

Confirmation gate 对 source 不敏感 — 任何高风险 proposal 都走同一确认 UI。**Privacy Policy 永远优先于 source。**

## 5. 模块映射

### 5.1 Mobile (Flutter)

```
lib/core/ai/
├── contracts/
│   ├── intent.dart              Capability / RiskLevel / SideEffectScope / IntentHint
│   ├── privacy_budget.dart      BudgetTier / PrivacyBudget / AnonymizationLevel
│   ├── base_context.dart        BaseContext / RiskPreference / CashflowSummary / FireGoalSummary
│   ├── task_context.dart        TaskContext / RecentSignal / SemanticHit / ScopedAggregate
│   ├── context_pack.dart        ContextPack + assertBudget + assertVersion
│   ├── scoped_disclosure.dart   DisclosureRequest/Response / LedgerField / UserConsent
│   ├── tool_descriptor.dart     ToolDescriptor (mirror)
│   ├── proposal_envelope.dart   sealed ProposalEnvelope + 4 variants + UndoToken
│   ├── ai_trace.dart            AiTrace / Backend / DisclosureSummary / TraceToolCall
│   └── contracts.dart           barrel
├── router/                      ★ Phase 5 重构: 注入 RuntimeRegistry，原 Backend 枚举降级为 audit label
│   ├── routing_inputs.dart      RoutingInputs / PrivacySensitivity / LatencyHint
│   ├── routing_decision.dart    RoutingDecision / RoutingReason / supported flag
│   ├── routing_policy.dart      纯函数 decideRouting()
│   ├── ai_router.dart           class AiRouter + seedTrace + Riverpod provider
│   └── router.dart              barrel
├── runtime/                     ★ 待新增: AiRuntime 抽象 + RuntimeRegistry
├── trace/
│   ├── ai_trace_store.dart      AiTraceStore 抽象 + InMemoryAiTraceStore
│   ├── ai_trace_builder.dart    可变累加器
│   ├── providers.dart           aiTraceStoreProvider / recentAiTracesProvider / aiTraceByIdProvider
│   └── trace.dart               barrel
├── write/
│   ├── local_immediate_executor.dart  LocalImmediateWriteExecutor + UndoEntry + 30s 默认窗口
│   └── write.dart               barrel
└── local/
    ├── skills/
    │   ├── transaction_input.dart       中性输入类型
    │   ├── merchant_key.dart            normalize（latin + CJK）
    │   ├── txn_classifier.dart          alias 表 + 子串回退
    │   ├── recurring_detector.dart      monthly/weekly cadence + 5% amount tolerance
    │   ├── transfer_matcher.dart        跨账户配对（±2 天，50 minor 容差）
    │   ├── refund_matcher.dart          merchant 同名 + 30 天窗口
    │   ├── context_compressor.dart      构造 BaseContext + TaskContext + 预算自检
    │   ├── finance_query_plan.dart      sealed: SpendingByCategory / TransactionsFilter / NetWorthTrend / SubscriptionList / RefundMatching
    │   ├── nl_to_query_plan.dart        启发式 NL→Plan 解析器（中英文）
    │   ├── query_plan_executor.dart     抽象 + InMemoryQueryPlanExecutor
    │   └── skills.dart                  barrel
    └── embedding/
        ├── embedder.dart           Embedder 抽象 + StubEmbedder
        ├── vector_store.dart       VectorStore + InMemoryVectorStore
        ├── semantic_memory.dart    SemanticMemory + excerptAround
        └── embedding.dart          barrel
```

### 5.2 Backend (Rust on Cloudflare Workers)

```
apps/backend/src/ai/
├── context/                  Wire-crossing types (与端侧契约镜像)
│   ├── mod.rs
│   ├── context_pack.rs       ContextPack + ContextPackError + assert_version + assert_budget
│   └── disclosure.rs         DisclosureRequest/Response / LedgerField / UserConsent
├── policy/                   代码层策略
│   ├── mod.rs                #[allow(dead_code)] 直至 Phase 3 启用
│   ├── tool_policy.rs        13 个工具的 ToolDescriptor 静态表 + lookup
│   └── risk_policy.rs        纯函数 check_tool_call() + PolicyDecision
├── read_models/              ★ 待新增: 第 4.3 节核心层
│   ├── mod.rs
│   ├── holdings_snapshot.rs           P0
│   ├── net_worth_snapshot.rs          P0
│   ├── monthly_spend_by_category.rs   P0
│   ├── cashflow_buckets.rs            P1
│   ├── asset_allocation_snapshot.rs   P1
│   ├── projection.rs                  trait SyncProjection / AsyncProjection / NightlyProjection
│   └── freshness.rs                   freshness gate 协议（HLC watermark + version 比对）
├── anthropic.rs              Anthropic API client
├── guardrails.rs             rate limit / max rounds / max proposals
├── proposals.rs              propose_* 工具实现（确认通道，不动）
├── sse.rs                    encode_event / encode_comment
└── tools.rs                  ★ Phase 5 facade 化: 工具内部改读 read_models::*::get()
```

`apps/backend/src/routes/ai.rs`: `ChatRequest` 已含 `context_pack` 字段；`run_tool_loop` 已透传 `context_tier` 到 `ToolCtx`。

## 6. 数据流示例

### 场景 A — 用户输入新交易 "STARBUCKS 04291"

```
QuickAdd → Router(classify, info, no sideEffect)
  → decideRouting() → DeviceRuntime
  → Device.skills.txn_classifier
    → merchant_key = "starbucks" → alias hit → categoryHint='coffee', confidence=0.9
  → 写 Drift（本地真源）→ Sync OpLog
  云端零调用
```

### 场景 B — "上月咖啡花了多少"

```
Chat → Router(search, info, no sideEffect)
  → decideRouting() → DeviceRuntime（数据端侧已有，无需联网）
  → nl_to_query_plan.parseNlQuery()
    → SpendingByCategoryPlan(range=2026-04, categoryHints=['coffee'])
  → DriftQueryPlanExecutor.run()  (★ 待实现)
    → 返回 QueryResult { rows, summary }
  云端零调用，零外泄
```

### 场景 C — "帮我看下今年 FIRE 进度并建议调整"（含主通道与 freshness gate）

```
Chat → providers.dart 中 _prepareChatTrace(ref, requestId)
  → ContextCompressor.compress() 编 ContextPack（端侧派生信号 + 偏好 + freshness hint）
  → AiRouter.decide() → CloudAnthropicRuntime
  → AiRouter.seedTrace() 生成 AiTrace seed (requestId == assistantMessageId)
  → AiChatApiClient.chat({contextPack, messages})
  → POST /ai/chat
     Backend:
       - ChatRequest 反序列化
       - pack.assert_version(CURRENT_CONTEXT_PACK_VERSION) → 4xx 若不兼容
       - pack.assert_budget()                              → 4xx 若超 tier
       - ToolCtx.context_tier = pack.budget.tier
       - run_tool_loop:
           per tool_call get_holdings →
             read_models::holdings_snapshot::get(user_id)  ★ 主通道
             → tool_result 附带 freshness.read_model_hlc
           客户端检查: device.lastLocalHlc > read_model_hlc?
             命中 → request_freshness_refresh 触发 ScopedDisclosure（兜底通道）
       - per tool_call → risk_policy::check_tool_call() → 当前仅日志
  → SSE 回流，端侧渲染
  → AiTraceBuilder per tool_use/tool_result 累加 duration
  → finally: AiTraceStore.append(trace.finalize())
  → AiTransparencyBadge(messageId)：
     "本地数据 + 云端推理 · 未上传原始交易明细 · 2 个工具 · 1.4s"
```

## 7. 实现状态

| Phase | 范围 | 状态 |
|-------|------|------|
| **Phase 1** | contracts + router + trace + 基础 compressor | ✅ |
| **Phase 2-A** | ContextPack 上线（端侧编码 + 后端 ingest + 透明度徽章） | ✅ |
| **Phase 2-B** | rules skills（4 个）+ LocalImmediateWrite/undo | ✅ |
| **Phase 2-C** | ToolDescriptor 元数据 + risk_policy（advisory） | ✅ |
| **Phase 3** | NL→QueryPlan + 5 类 plan + InMemoryExecutor | ✅ |
| **Phase 4** | Embedder 抽象 + InMemoryVectorStore + SemanticMemory（StubEmbedder） | ✅ |
| **★ Read Models — Snapshot 层** | `holdings_snapshot` / `net_worth_snapshot` / `monthly_spend_by_category` / `cashflow_buckets` / `net_worth_daily` | ✅ 主通道全部贯通（cloud-projected via `Projection` trait + lazy refresh） |
| **★ Read Models — Analytical 层 P1** | `recurring_patterns` / `anomaly_flags` / `refund_links` / `transfer_links` / `investment_performance` (5/6) | ✅ device-sourced — 端侧 detector → `ContextPack.analytical_uploads` → 后端镜像；剩 `subscription_changes` 待跨会话状态机 |
| **★ Read Models — Analytical 层 P2** | `xirr_snapshot` | ✅ cloud-projected (Newton-Raphson 确定性算法) |
| **★ Read Models — Scoped Detail 层** | `read_account_window` / `read_asset_window` / `read_category_window` | ✅ 含 purpose 必填 + 硬限额 + sanitised 字段 + HMAC-SHA256(user_id, merchant) 哈希；`get_journal_entries` 仍在表中（schema 隐藏，dispatch 保留兼容），待去除 |
| **★ Schema 公约 + Freshness gate** | `source_hlc_watermark` / `refreshed_at` / `schema_version` / `calculation_version`；SSE tool_result.freshness + 端侧比对 + Phase 2 `force_refresh_read_models` 提示 | ✅ Phase 1 (logging) + Phase 2 (hint) 落地，下一次 chat 自动带 `freshnessHint` |
| **★ Runtime 抽象层** | `AiRuntime` interface + `RuntimeRegistry` | ❌ 当前 `Backend` 枚举写死 |
| **Phase 5** | 端侧真实 LLM runtime + 模型下载/校验 | ❌ 未实现 |

**ToolDescriptor 总数**: 25（Read 18 + Propose 5 + 兼容保留 2）— 见 `apps/backend/src/ai/policy/tool_policy.rs`。`risk_policy.rs::every_dispatch_target_has_a_descriptor` 与 `tools.rs::schemas_advertise_all_dispatch_targets` 双向同步。

**测试覆盖**: backend 121 tests (`cargo test --lib`) + mobile（含 8 个 analytical_uploads 转换契约用例 + 23 个 chat_repository 用例 + freshness gate 覆盖）。`flutter analyze --fatal-infos` 与 `cargo clippy --target wasm32-unknown-unknown --all-targets -- -D warnings` 均干净。Runtime 抽象、Phase 5 尚未触及。

### Wave 落地清单（Read Models 主通道）

| Wave | 主题 | 关键产物 |
|------|------|---------|
| 1 | `Freshness` / `Projection` 抽象 + schema 公约 | `read_models/{freshness,projection}.rs`，五字段公约 |
| 2–3 | `monthly_spend_by_category` 落地 + write-side trigger | migration 0006，`get_monthly_spend_by_category` |
| 4 | `holdings_snapshot` cloud-projected | migration 0007，`get_holdings` 从 read model 读 |
| 5–6 | `net_worth_snapshot` + `get_net_worth_summary` | migration 0008 |
| 7 | tools.rs facade 改造（industry/geo/market_cap breakdown 读 holdings_snapshot） | — |
| 8 | Freshness gate Phase 1 (SSE `tool_result.freshness` + 端侧 logging) | `chat_sync_gate.dart` 接 `staleReadModels` 计数 |
| 9 | `cashflow_buckets` + `get_cashflow_buckets` | migration 0009 |
| 10 | Analytical 首个 device-sourced：`recurring_patterns` | migration 0010；ContextPack `analytical_uploads` 协议落地 |
| 11 | `anomaly_flags` + 端侧 `expenseAnomalyInsightProvider` 上报 | migration 0011 |
| 12 | Scoped Detail 三表 + 共享 `scoped_detail/common.rs`（HMAC-SHA256 / parse_iso / validate_range / excerpt） | `read_{account,asset,category}_window` |
| 13 | `xirr_snapshot` cloud-projected（Analytical P2） | migration 0012；`get_xirr_summary` |
| 14 | `net_worth_daily` + Freshness gate Phase 2（`pendingFreshnessHintProvider` → 下次 chat 携带 `forceRefreshReadModels`） | migration 0013 |
| 15 | Mobile producer wire：`detectRecurring` 跑在 expense 流上 → `recurring_pattern` upload | `_buildAnalyticalUploads` 落地 |
| 16 | `refund_links` + `transfer_links`（device-sourced） | migration 0014；端侧 `matchRefunds` / `matchTransfers` 接入 producer |
| 17 | `investment_performance`（device-sourced，per-asset 持仓状态） | migration 0015；`holdingsSnapshotProvider` → `investment_performance` upload |

## 8. TODO

按优先级排列。**P0 主通道已贯通**；P1 剩 Analytical 1 个模型 + Runtime 抽象 + 运维持久化。

### P0 — 主通道（✅ 全部完成 Wave 1–17）

- [x] ~~**Read Models — Snapshot 层 P0 三表**~~ — `holdings_snapshot` / `net_worth_snapshot` / `monthly_spend_by_category` 全部 cloud-projected + lazy refresh
- [x] ~~**Read Model schema 公约**~~ — 五字段公约 + `Freshness` / `Projection` 抽象 (`apps/backend/src/ai/read_models/freshness.rs`, `projection.rs`)
- [x] ~~**`tools.rs` facade 改造**~~ — `get_holdings` / `compute_net_worth` / `get_industry_breakdown` / `get_geo_breakdown` / `get_market_cap_breakdown` / `get_monthly_spend_by_category` / `get_net_worth_summary` / `get_cashflow_buckets` 全部从 read model 读，带 `freshness` 元数据
- [x] ~~**Freshness gate 协议**~~ — SSE `tool_result.freshness` (Phase 1 logging + Phase 2 `pendingFreshnessHintProvider` → 下次 chat 携带 `forceRefreshReadModels` 提示) — 见 `apps/mobile/lib/features/ai_chat/data/providers.dart`、`apps/mobile/lib/features/ai_chat/state/chat_sync_gate.dart`
- [x] ~~**废弃 `get_journal_entries` → Scoped Detail 工具族**~~ — `read_account_window` / `read_asset_window` / `read_category_window` 落地：必填 `purpose` + 硬限额 ≤ 50 + HMAC-SHA256(user_id, merchant) 哈希 + sanitised 字段 + 共享 `scoped_detail/common.rs` 帮手；`get_journal_entries` schema 已从 LLM 视野隐藏（dispatch 保留以防回归）

### P1 — 现有路径稳定 + 启用生产

- [ ] **Read Models — Snapshot 层 P1**: 剩 `asset_allocation_snapshot`（`cashflow_buckets` 已落地 Wave 9，`net_worth_daily` 额外补充）
- [ ] **Read Models — Analytical 层 P1**: 剩 `subscription_changes`
  - 端侧需要跨会话状态（"上个月这条 recurring 比这个月便宜了 10%"）— 落地前需把 `recurring_patterns` detector 结果通过 OpLog 持久化到 Drift，方能跨 chat 比对
  - 已落地（device-sourced）：`recurring_patterns` (Wave 10) / `anomaly_flags` (Wave 11) / `refund_links` (Wave 16) / `transfer_links` (Wave 16) / `investment_performance` (Wave 17)
  - 已落地（cloud-projected）：`xirr_snapshot` (Wave 13)
- [ ] **`AiRuntime` 抽象 + RuntimeRegistry** — 把现有路径包装为 `RulesDeviceRuntime` + `CloudAnthropicRuntime`，router 改成 registry 查询。`Backend` 枚举降级为 trace label。
- [ ] **AiTraceStore 持久化** — Drift 表 + 30 天滚动清理。接口已稳定。  *入口*: `lib/core/ai/trace/ai_trace_store.dart`
- [ ] **LocalImmediateWriteExecutor 持久化** — undo 栈 Drift 表按 token 索引。  *入口*: `lib/core/ai/write/local_immediate_executor.dart`
- [ ] **risk_policy advisory → enforced** — 生产数据验证后，dispatcher 在 denied 分支返回合成的 `tool_result { error: "policy_denied" }`。  *入口*: `apps/backend/src/ai/tools.rs::dispatch`
- [ ] **`tools.rs` 文件拆分** — `tools/{read,propose,external}/`，元数据已在 `policy/tool_policy.rs`，机械工作不影响行为。
- [ ] **`ToolDescriptor` 加 `allowed_runtimes` + `side_effect` + `read_model_layer`** — 端云同构契约；`read_model_layer` 让 policy 强制 routine chat 不调 Layer 3。

### P2 — 增强

- [ ] **AI 透明度审计页** — Settings → AI 透明度 → 翻历史。`recentAiTracesProvider` 已就绪。
- [ ] **ContextPack 进 system prompt** — 后端把派生信号（signals / preferences / route）编进 Anthropic system prompt（不替代 SYSTEM_PROMPT，而是 append）
- [ ] **Drift-backed QueryPlanExecutor** — 生产侧 features 适配器。  *入口*: `lib/core/ai/local/skills/query_plan_executor.dart`
- [ ] **`NetWorthTrendPlan` 适配器** — 端侧桥接 read_models 或 dashboard providers
- [ ] **AiTraceBuilder 错误/取消细分 reason** — finalize 区分 stream error vs user cancel vs done。
- [ ] **`ProposalEnvelope.source` 字段** — device/cloud/hybrid，配合 Stage 3 准备
- [ ] **ContextPack 收缩** — `BaseContext` 删除 `cashflow` / `accounts` 字段（数据来自 read models 而非 ContextPack），`TaskContext` 加 `freshnessHint { lastLocalHlc }`

### P3 — Phase 5 / 长期 / 未来 feature

- [ ] **Read Models — Analytical 层 P2 四模型** — `spending_clusters` / `goal_progress_projection` / `tax_lot_analysis` / `financial_behavior_profile`，nightly cron
- [ ] **Read Models — Scoped Detail 层完善** — purpose-bound 工具族补齐（`read_trip_cluster` / `read_subscription_history` 等），与 Analytical 层 drill-down 链路打通
- [ ] **Phase 5 — 端侧 LLM runtime**:
  - [ ] 平台通道 / `onnxruntime` 包装
  - [ ] 模型下载 + 校验和 + opt-in 设置
  - [ ] tokeniser + decode loop
  - [ ] 接管 `txn_classifier` 兜底分支（rules 未命中时）
  - [ ] 月报摘要 device LLM 路径
  - [ ] Stage 2 `LocalAnalystRuntime` 注册
- [ ] **Phase 5 — 真实 Embedder** — 替换 `StubEmbedder` 为 MiniLM (~30MB ONNX)。`Embedder` 接口已稳定，仅换实现类。
- [ ] **VectorStore: sqlite-vec 后端** — `InMemoryVectorStore` 在 ≥5k 文档时变慢。
- [ ] **「不上云账户」feature + PrivacyGate UI** — 配合此 feature 上线时再做 disclosure consent UI；否则 ScopedDisclosure 仅做 freshness gate 即可。
- [ ] **Disclosure session 缓存** — 用户授权 "本会话允许 drill-down 餐饮" 应缓存避免每次弹窗。
- [ ] **Schema-as-source codegen** — JSON Schema 生成 Dart freezed + Rust serde（`packages/ai_contracts/`）。等 Phase 5 设计锁定后启动。

### 非本架构引入但相关

- 9 个 `test/features/ai_chat/tool_invocation_renderers_test.dart` 测试在 HEAD 即失败（与本架构无关，已在 stash 验证）。
- `apps/backend/src/routes/ai.rs:178` 的 `cargo fmt` 差异同样在 HEAD 即存在。

## 9. Contract Drift Prevention

NaviWealth 当前的 wire 契约（`lib/core/ai/contracts/` 与 `apps/backend/src/ai/context/`）是**双侧手写 + roundtrip test 锁死**的，约 9 个 Dart 文件 + 3 个 Rust 文件、~1500 LOC，规模可控。

**当前阶段（Phase 1–4 已稳定，未到 Phase 5）的纪律**：

1. **双侧契约改动必须同 PR** — Dart 改了字段，Rust mirror 必须同 PR 跟上；review 强制检查双侧 wire key 一致。
2. **Roundtrip test 强制覆盖每个新增字段** — `test/core/ai/contracts/contracts_roundtrip_test.dart` 是 wire format 的 golden，新增字段必须在该测试中露面。
3. **snake_case 是 wire 唯一形式** — 端侧 `toJson()` 显式 `snake_case`，Rust 用 `#[serde(rename_all = "snake_case")]`；任何 camelCase 漏出都属于 bug。
4. **`ContextPackVersion.major` 不匹配 → 直接 4xx** — 不做 wire-level fallback；端侧必须升级才能继续工作。
5. **未知 enum 值 → 软回退到默认** — wire 解析层不抛异常，但 routing/policy 拿到默认值时按"陌生意图"处理（路由到 cloud + one_tap）。

**演进触发点**: 当下面任一条件满足时启动 codegen pipeline（schema-as-source）：

- 契约表面超过 ~3000 LOC（双侧总和）
- 出现端侧多 runtime（DeviceLLM + DeviceRules）需要消费同一份 ContextPack
- Phase 5 设计锁定后准备发布 SDK / 第三方对接

届时落 `packages/ai_contracts/`：

```text
packages/ai_contracts/
  schemas/
    context_pack.schema.json        ← 单一真值
    proposal_envelope.schema.json
    tool_descriptor.schema.json
    sse_event.schema.json
    read_model_freshness.schema.json
  build.sh
  README.md
```

工具链候选: `quicktype` (CLI, JSON Schema → Dart freezed + Rust serde) 或自研薄薄的 generator。

**核心原则**: **不共享代码，共享协议** — Dart 类型和 Rust 类型由同一份 schema 生成，业务实现各写各的。

## 10. 关键设计取舍（非显然的决定）

- **为什么主通道是 Read Models 而不是 ContextPack** — 同步已经把数据搬到 D1，让 cloud 绕回端侧拿数据是绕远路。ContextPack 退到「端侧独有的派生信号 + 偏好 + 路由 + freshness hint」更合理。
- **为什么 Read Models 分三层而不是 snapshot only / 也不是开放 raw ledger** — 只有 snapshot 时 AI 答不出「为什么」只能胡猜；开放 raw ledger 会触发 token 爆炸 / prompt injection（恶意 memo 改 LLM 行为）/ 隐私边界失控 / planner 自由 scan 成本失控。三层各取所长：Snapshot 答聚合事实，Analytical 提供可解释的中间结论，Scoped Detail 在 drill-down 时给受控明细。
- **为什么 Analytical 层比 Snapshot 更值钱** — `{merchant: "Netflix", trend: "up"}` 这种结构化中间结果对 LLM 来说 token 密度远高于一堆 raw rows，且语义清晰；snapshot 偏「数」，analytical 偏「事」，AI 更适合后者。
- **为什么 `get_journal_entries` 必须废弃而不是收紧** — 它的 schema 允许 `unit + account + 日期 + limit≤200`，已经偏 raw scan 心智；保留它会让 LLM 默认走它而非 Snapshot。改成 `read_transaction_slice` 系列后必填 `purpose` + 写 AiTrace，policy 可在 enforced 模式下检查 purpose 与意图匹配。
- **为什么端侧 detector 不复制成云端 Analytical 层重算** — recurring / refund / anomaly 是启发式 + 个性化逻辑，Dart 一份 Rust 一份必然漂移。让端做唯一计算者，云端订阅结果（通过 ContextPack 或纯快照同步）。
- **为什么 freshness gate 用 HLC 而不是 wall-clock** — NaviWealth 已有 HLC 基础设施，wall-clock 在多设备场景容易被时钟漂移误导。
- **为什么 read model 不全部写后立即刷新** — D1 / Worker 环境下，每次 journal_entries 写入触发全部 projection 重算会拖慢 sync push。允许短暂 stale + freshness gate 兜底是更工程化的选择。
- **为什么 `AiRuntime` 不一开始就上** — Phase 1–4 用 `Backend` 枚举写死成本最低；现在 stage 1 只有两个 runtime，registry 是过度设计。但元数据先到位（ToolDescriptor 加 `allowed_runtimes`），让 Phase 5 平滑切换。
- **为什么 Schema-as-source 不立刻做** — 契约规模未到，codegen 引入构建依赖 + CI 步骤是负债。当前用「同 PR + roundtrip test + snake_case 公约」足够。
- **ContextPack 为何拆 Base + Task 两层** — Base 稳定可缓存，跨会话复用；Task 每次重建。
- **`SideEffectScope` 默认 `crossCutting`** — 当 feature 没显式声明 sideEffect 时，路由器假设最坏情况而不是放行。
- **`risk_policy` 为何先 advisory** — ToolDescriptor 表是手写元数据，需要生产流量验证。advisory 提供观察期，无回归风险。
- **AiTrace 不进 OpLog** — trace 包含路由决策、tool latency、用户 consent 选择，不应该被同步到云端。
- **端侧 LLM 必须 opt-in** — 200MB 级别下载不应阻塞首屏。
- **NL→QueryPlan 不直接写 SQL** — sealed plan + Drift query builder。新增意图必须改类型，不会「忘了」。
- **Privacy Policy 永久优先于 Source** — 任何 high-risk proposal 不论端侧/云端生成都走同一确认 UI；隐私设置不论 runtime 都执行。

## 11. 引用 / 入口表

| 想做什么 | 从这里看起 |
|---------|----------|
| 调用 AI 路由 | `lib/core/ai/router/router.dart` (`AiRouter.decide`) |
| 编码 ContextPack | `lib/core/ai/local/skills/context_compressor.dart` |
| 添加新 plan 类型 | `lib/core/ai/local/skills/finance_query_plan.dart` (sealed) + parser + executor |
| 添加新 rules skill | `lib/core/ai/local/skills/` 新建文件 + 加入 `skills.dart` barrel |
| 新增工具元数据 | `apps/backend/src/ai/policy/tool_policy.rs::DESCRIPTORS` |
| 改 router 决策 | `lib/core/ai/router/routing_policy.dart` (纯函数) |
| 修改 wire 契约 | `lib/core/ai/contracts/` + 对应 Rust mirror，需要双侧改动 + roundtrip test |
| 看 AI 透明度徽章 | `lib/features/ai_chat/ui/ai_transparency_badge.dart` |
| 跑测试 | `flutter test test/core/ai/` + `cargo test --lib` |
| **新增 Snapshot Read Model**（★ 待建） | `apps/backend/src/ai/read_models/` + `tools.rs` facade 改造 + `read_models/projection.rs` 选 sync/async/nightly 档 |
| **新增 Analytical Read Model**（★ 待建） | 同上，但订阅端侧 ContextPack 上报，写入带 `source_device_id` |
| **新增 Scoped Detail 工具**（★ 待建，替代 `get_journal_entries`） | `tools.rs` 中加 `read_transaction_slice` 等；必填 filter + purpose + 硬限额 |
| **新增 AiRuntime**（★ 待建） | `lib/core/ai/runtime/` 实现 `AiRuntime` + 在 `RuntimeRegistry.register()` |
