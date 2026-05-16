# NaviWealth AI 架构

> 状态: Phase 1–4 已落地（contracts + router + trace + skills + query plan + semantic memory），**Read Models 三层全部贯通**（Snapshot 5 张 / Analytical 7 个 / Scoped Detail 三表），**P1 全部完成**（Runtime 抽象 / Trace 持久化 / Undo 持久化 / Tool descriptor 扩展 / Policy enforce / tools 拆分起步），**P2 全部完成**（AI 透明度审计页 / ContextPack→system prompt / Drift QueryPlanExecutor + NetWorthTrendPlan / AiTrace terminal reason 细分 / ProposalEnvelope.source / ContextPack 收缩）。Phase 5（端侧 LLM）未实现。
> **Wave 进度**: Wave 1–44 完成（Wave 41–44 = 测试准出 P0：Red CI cleanup + Schema-as-contract gates + AI surface 视觉回归 + AI 回归 corpus）— 详见 §8 实现状态表与 Wave 落地清单。**§5 Interaction Grammar + 测试准出 P0 全部完成；CI 现已有可信赖的 baseline（known-failing-tests pinned）+ 双侧 enum/l10n 漂移自动检测 + AI 视觉 token 回归保护 + 回归 corpus 静态契约**。剩余主线: 测试准出 P1（A11y baseline / 性能预算 / Prompt injection corpus / backend HTTP 集成测试）；Phase 5 端侧 LLM；long-window `subscription_changes`；Analytical 层 P2 四模型；可选 swipe-to-apply 真实手势。
> **§5 是 UI/UX 契约**: 任何新 AI 入口 / 渲染 / 确认面必须满足 §5.8 硬约束。
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

### 4.6 Phase 5 — 端侧 LLM Runtime（用户自带 key · 最小后端 · 全原生平台，含桌面）

> 状态: ❌ 未实现 → 本节为已锁定的落地决策（取代 §9 P3 「Phase 5 — 端侧 LLM runtime」的占位描述）。
> 取舍详见 §11；逐 Wave 清单见 §8 / §9。

**目标**: agent 大脑下沉到端侧，**最小化对后端的依赖**。后端在 device runtime 路径上完全不参与 AI（不走 `/ai/chat`、guardrails、read model projection、ContextPack ingest）；后端 AI 代码先**冻结并存**，端侧验证稳定后单独 Wave 删除。后端继续保留 sync / auth / D1（与 AI 无关，不动）。

#### 4.6.1 五条决策

1. **用户自带 key**: 用户在设置里手动填 LLM API key。复用 `core/security/SecureKeyStore`（`flutter_secure_key_store.dart` 已有，Keychain/Keystore 后端）。key **绝不**进 OpLog / 云同步 / 明文备份；与 SQLCipher key 同等对待。
2. **`DeviceLlmRuntime` 直连 provider**: 端侧 Dart Anthropic adapter（port 自 `apps/backend/src/ai/adapters/anthropic/`，Messages API + SSE streaming + `tool_use`）。agent loop / tool dispatch / prompt 组装 / proposal 全在端侧。
3. **工具读 Drift 本地真源**: 不再读 D1 read models。**§4.2 freshness gate 与 ScopedDisclosure 兜底通道在 device runtime 路径上整体消失** —— 端侧本就是 local-first 真值源，不存在 read model stale，也不存在「原始 ledger 出设备」需要脱敏的问题。
4. **Vision 端侧直发**: 图像 base64 → content block，用用户 key 直发 provider。比 §5.10.10 的 Worker 中转**更私密**（原图根本不出设备到我方服务器）。AiTrace 文案改为「端侧直连 provider · 原图未经我方服务器」。
5. **平台边界 = 全部原生平台（iOS / Android / macOS / Windows / Linux），仅排除 Web**（决策已修订，原为「仅 iOS/Android」）: 所有原生平台都有系统级安全存储（iOS/macOS Keychain、Android Keystore、Windows 凭据库、Linux libsecret，均经 `flutter_secure_storage` ^10）且用原生 HTTP（无浏览器 CORS / 无 JS key 暴露）——桌面与移动的安全前提**完全相同**，故端侧 agent 同样支持桌面。**只有 Web 继续走 `CloudAnthropicRuntime`**（IndexedDB-only key + 浏览器直连 CORS）。门控就是 `!kIsWeb`，由 registry 按 `platform × keyPresent × optIn` 选择。

#### 4.6.2 Runtime 选择（`RuntimeRegistry` 改造）

新增 `RuntimeId.deviceLlm`。`pickFor` 不再单纯按 `Backend` 枚举一一映射，改为能力 + 环境联合判定：

```text
if  platform == native(iOS/Android/macOS/Windows/Linux，即 !web)
 && userLlmKeyPresent
 && userOptedInDeviceAi          → RuntimeId.deviceLlm
else if cloud relay 仍存在        → RuntimeId.cloudAnthropic   (web / 无 key / 未 opt-in / 降级)
else                              → AI 禁用，提示「设置中填入 API key」
```

`RulesDeviceRuntime` stub 由 `DeviceLlmRuntime` 取代（rules-only 快答仍作为 device runtime 内部的零模型短路，不再是独立 RuntimeId）。`ChatRepository` 这次真正改走 registry（§8 标注的「Phase 5 接入端侧 runtime 时切换」即此刻）。

#### 4.6.3 工具端侧化清单（D1 read model → Drift）

device runtime 路径上 27 个工具的数据源迁移，**复用既有端侧资产，不重造**：

| 层 | 端侧来源 | 备注 |
|----|---------|------|
| Snapshot（net worth / holdings / monthly spend / cashflow / allocation / net_worth_daily） | `domain/services/` 既有 net worth/currency service + `holdingsSnapshotProvider` + `DriftQueryPlanExecutor` | XIRR 复用现有确定性算法（端侧已有 plan executor 雏形） |
| Analytical（recurring / anomaly / refund / transfer / investment_perf / subscription_changes） | **本来就在端侧**（detector 是 Dart 唯一计算者，§4.3.3 铁律） | 直接调本地 detector，省掉 ContextPack 上报→D1 投影→工具读回的往返 |
| Scoped Detail（account/asset/category window） | 直接查 Drift | 端侧不出设备 → **不再 HMAC 脱敏**；仍保留 `purpose` 必填 + 写 AiTrace 维持透明度 |

`ToolDescriptor.allowed_runtimes` 据此校验：device runtime 只 dispatch 标 `device`/`both` 的工具；`ExternalSideEffect`（broker 下单）仍 `cloud_only + typed confirmation`，端侧产 proposal 但不自动执行（§4.5 不变）。

#### 4.6.4 降级路径

`DeviceLlmRuntime` 在以下情况回落 `CloudAnthropicRuntime`（cloud relay 删除前）：web 平台 / 无 key / 未 opt-in / provider 报错（鉴权失败、网络）。cloud relay 删除后，无 key 即禁用 AI 并引导填 key。降级必须写 AiTrace（`terminalReason` 体现）。

## 5. Interaction Grammar — AI 进入页面，而非用户进入 AI

> 这一章是 UI/UX 层的「契约」，与 §4 wire 契约平级。所有 AI 入口、Bottom Sheet、Capsule、Reply Chip、Proposal 确认面，**必须遵守本章规则**。功能 PR 在 review 时按 §5.8 硬约束逐条对照。

### 5.1 设计哲学

NaviWealth 的 AI 不是「财务 App 里的一个 chat tab」，而是**贯穿整个产品的系统层能力**。指导原则三句话:

1. **Invisible but Omnipresent** — AI 像系统服务，不像功能模块。用户感知是「这个 App 懂我」，而非「这里有个 AI 按钮」。
2. **AI 进入用户的页面，而非用户进入 AI** — Bottom sheet / capsule 在原位展开，禁止把用户从当前业务页面踢到 `/ai` tab。
3. **Calm Intelligence** — 排版 + 克制动效 + 极少 sparkle；禁止 chatbot 气泡、glow、neon 渐变。参考: Apple Intelligence / Linear / Notion AI。**反例**: Glowing "Ask AI" big button、彩虹色 robot icon。

| 反模式（禁止） | 替代（采纳） |
|----------------|--------------|
| 「Ask AI」按钮 | 对象语义动作（"为什么涨价" / "对比上月"） |
| 跳 `/ai` tab | inline bottom sheet（同页展开） |
| 全功能 chat 起步 | 单 intent 触发，需要时再 expand |
| 散落的 `openAiChat(args)` 调用 | 统一 `AiIntentInvocation` 协议（§5.3） |
| chatbot 气泡 + AI avatar | typography-first，无 avatar |
| glowing / neon / 渐变 AI icon | 单色 sparkle、极小尺寸、按需出现 |

### 5.2 三层入口模型

AI 触达用户的三个层级**必须共存**（缺一会回到「插件感」）:

| 层级 | 触发者 | 形态 | 场景 | 当前落地 |
|------|--------|------|------|----------|
| **Ambient AI** | 系统/端侧 detector 主动 | Insight 卡片 / banner / 通知 | anomaly / maturity / subscription_change | 🟢 home `ai_insight_feed.dart`（但无 chat 深链） |
| **Contextual AI** | 用户在某个对象上 | Capsule / 选中菜单 → bottom sheet | 详情页解释、对比、建议 | ❌ 未建 |
| **Global AI** | 用户跨领域复杂任务 | Command palette / chat tab | 多步骤分析、跨账户重平衡 | 🟢 `/ai` tab + command palette |

三层缺一不可。Ambient 不深链 → AI 看似有提示但用户无法追问；Contextual 缺失 → 用户必须切到 chat tab，context break；Global 缺失 → 复杂任务无家可归。

### 5.3 AiIntentInvocation — 唯一入口协议

**所有调起 AI 的地方** (capsule / insight tap / command / voice / 未来 drag-to-AI) **必须经过这个类型**。禁止散落的 `openAiChat(routeContext, sessionId, prompt)` 风格 API。

```dart
class AiIntentInvocation {
  const AiIntentInvocation({
    required this.source,        // 触发位置标签（'expense_detail', 'home_insight_card', ...）
    required this.intent,        // §5.7 注册过的 intent 字符串（'explain_change', ...）
    this.object,                 // 业务对象引用（{type, id}）
    this.context = const {},     // 额外 ContextPack 信号（timeframe / 关联 ID 等）
    this.suggestedPrompt,        // 兜底 prompt 文案（intent 模板生成失败时用）
    this.capabilities = const {  // 此次调用允许的能力，影响 sheet 渲染分支
      AiCapability.chat,
      AiCapability.proposal,
      AiCapability.visualization,
    },
  });

  final String source;
  final String intent;
  final AiObjectRef? object;
  final Map<String, Object?> context;
  final String? suggestedPrompt;
  final Set<AiCapability> capabilities;
}

class AiObjectRef {
  const AiObjectRef({required this.type, required this.id});
  final String type;  // 'expense' | 'account' | 'asset' | 'liability' | 'fire_plan' | 'insight'
  final String id;
}

enum AiCapability { chat, proposal, visualization, voiceFollowup }
```

**示例**:

```dart
// Expense detail 页面右上角的 "为什么涨价" capsule
const AiIntentInvocation(
  source: 'expense_detail',
  intent: 'explain_change',
  object: AiObjectRef(type: 'expense', id: 'exp_abc123'),
  context: {'timeframe': '30d'},
  suggestedPrompt: '为什么这笔支出比上月增加了 18%？',
)

// Home insight 卡片 tap
const AiIntentInvocation(
  source: 'home_insight_card',
  intent: 'explain_insight',
  object: AiObjectRef(type: 'insight', id: 'anom_2026_05_food_spike'),
)

// FIRE 页面 "如何提高" capsule
const AiIntentInvocation(
  source: 'fire_page',
  intent: 'stress_test_plan',
  object: AiObjectRef(type: 'fire_plan', id: 'plan_default'),
  capabilities: {AiCapability.chat, AiCapability.proposal},  // 不需要可视化
)
```

**协议承诺**:
- **唯一性**: 入口收敛到 `AiIntentInvocation` 是硬性纪律。新 AI surface 不允许绕过本协议直接构造 chat / proposal。
- **可扩展**: 未来 voice、drag-to-AI、slash command 都填同一结构。
- **可追踪**: `AiTrace` 多一个 `invocation` 字段，把上面所有键存进 trace（透明度页就能看到「这次 AI 调用是从 expense_detail 触发的，intent=explain_change」）。

### 5.4 默认 surface: Inline Bottom Sheet

**强制规则**: `AiIntentInvocation` 默认渲染为 modal bottom sheet，覆盖在用户当前页面之上。**禁止**跳转到 `/ai` tab 作为响应。

```text
┌─ Current Page ─────────────────┐
│                                │
│  …business content…            │
│                                │
│ ┌─ AI Bottom Sheet ──────────┐ │
│ │ Context Header              │ │ ← intent + object 一行 summary
│ │ "Analyzing Netflix sub"     │ │
│ │                             │ │
│ │ Streaming answer            │ │ ← 复用现有 message_bubble streaming
│ │                             │ │
│ │ [Visualization, if any]     │ │ ← Wave 34 domain renderer
│ │                             │ │
│ │ Reply chips: [对比] [深入]   │ │
│ │                             │ │
│ │ [Proposal Card, if any]     │ │ ← propose_card 嵌入 sheet 里
│ │                             │ │
│ │ ─ expand to chat ─          │ │ ← 二级动作，升级为完整 session
│ └─────────────────────────────┘ │
└────────────────────────────────┘
```

**升级路径**: 用户点 "expand to chat" 才把当前 invocation **转**为 `/ai` tab 的一个新 session，原 sheet 关闭。**默认不切 tab**。

**降级 fallback**:
- 屏幕高度 < 500px (老 Android 横屏) → sheet 自动升级为全屏 modal route
- 用户从 sheet 内点 "在新会话里继续" → push `/ai` 并 seed 一条新 session

**Trace 关系**: bottom sheet 内的对话也是 AiTrace 记录的，与 chat tab 共享 store；用户在透明度页能看到来自所有 surface 的轨迹。

### 5.5 风险分层 × 交互模式

`ToolDescriptor` 已有 `risk` (Info/Suggest/Propose/Commit) + `requires_confirmation` (None/OneTap/Typed)，但 UI 没有从这两个轴直接派生交互。新增 `interaction_mode` 作为 UI 的强约束 (✅ Wave 35 落地：`lib/core/ai/write/interaction_mode.dart`，按 envelope 子类 + kindLabel 派生表实现):

| 场景 | proposal kind 举例 | risk | side_effect | `interaction_mode` |
|------|--------------------|------|-------------|---------------------|
| 解释 / 分类建议 / 标签建议 | 改 category、加 tag | Info | None | `oneTap`（capsule 内直接出按钮，无确认 sheet） |
| 小额记账 / 修改 note / 添加分类 | `propose_expense`（< $100）/ memo edit | Suggest | DeviceLocalWrite | `swipe`（向右滑应用 + persistent undo） |
| 中等金额 / 删除 / 转账 | `propose_trade` / `propose_liability_payment` | Propose | DeviceLocalWrite | `confirmDiff`（必须看到 diff preview 才能确认） |
| 大额 / 不可逆 / 外部 | broker 下单、bulk delete | Commit | ExternalCall | `typed`（输入金额 / 确认词二次） |

**派生规则** (代码层强制):
```dart
InteractionMode deriveMode(ProposalEnvelope p) {
  if (p is ExternalSideEffect) return InteractionMode.typed;
  return switch ((p.risk, p.sideEffect)) {
    (RiskLevel.info, _)                          => InteractionMode.oneTap,
    (RiskLevel.suggest, SideEffect.deviceLocalWrite) => InteractionMode.swipe,
    (RiskLevel.propose, _)                       => InteractionMode.confirmDiff,
    (RiskLevel.commit, _)                        => InteractionMode.typed,
    _                                            => InteractionMode.confirmDiff,  // safe default
  };
}
```

**禁止覆盖**: feature 代码不能"为了流畅"把 `confirmDiff` 降级为 `oneTap`。要降级先改 `risk`。

**Undo 全局可见性** (✅ Wave 35 落地，`PersistentUndoBanner` 挂在 `AppShell.footer`):
- `oneTap` / `swipe` 应用后，全局顶部出现 persistent undo snackbar（不是 60s 后消失的传统 toast），停留直到用户主动 dismiss 或新 proposal 应用
- snackbar 文案: "已修改 Netflix 分类为「订阅」· 撤销"
- 数据来源: `DriftUndoStack` (Wave 24)

### 5.6 Calm Intelligence 视觉规范

| 元素 | Do | Don't |
|------|-----|-------|
| AI 标识 | 单色细线 sparkle (Material `Icons.auto_awesome_outlined`)、字号同正文 | 彩虹渐变 / glowing / 大 icon |
| Capsule | 灰底 + 文字 + 极小 sparkle prefix；hover/long-press 才出现 | 常驻巨型按钮 |
| Bottom sheet | 系统 BottomSheet shape，标题区无装饰 | sheet 顶部彩色 banner |
| 流式光标 | 单 `█` 字符脉冲（已实现 _StreamingCaret） | 三个跳跃点 dot loader |
| Reply chip | outline button、同字号、间距紧凑 | 大尺寸卡片 / 阴影 |
| AI 来源 badge | typography 小字、灰色、单行 | tooltip 弹窗 / 大徽章 |

**色彩**: AI 元素**默认使用 surface tone**（不是 accent），让"AI 触点"在视觉上沉入页面而不是跳出来。只有处于 active streaming 状态时短暂强调一次。

### 5.7 Intent 治理 — `intent_policy.dart`

Intent 字符串 (`'explain_change'`, `'summarize_account'`, ...) 必须有 owner，否则两年后会有 50 个意图、半数已死。仿照 `policy/tool_policy.rs` 模式:

```dart
// lib/core/ai/intent/intent_policy.dart
class IntentDescriptor {
  const IntentDescriptor({
    required this.name,
    required this.labelZh,
    required this.allowedObjectTypes,
    required this.preferredCapabilities,
    required this.promptTemplate,
    this.preferredReadModels = const <String>[],
  });

  final String name;                       // 'explain_change'
  final String labelZh;                    // 'capsule 上显示的中文短语：「为什么涨价」'
  final Set<String> allowedObjectTypes;    // {'expense', 'recurring_pattern'}
  final Set<AiCapability> preferredCapabilities;
  /// `{}.object_label` / `{}.timeframe` 占位符
  final String promptTemplate;
  /// 此 intent 通常调用的 read model 名（freshness gate 用）
  final List<String> preferredReadModels;
}

const intentDescriptors = <IntentDescriptor>[
  IntentDescriptor(
    name: 'explain_change',
    labelZh: '为什么',
    allowedObjectTypes: {'expense', 'recurring_pattern', 'asset', 'liability'},
    preferredCapabilities: {AiCapability.chat, AiCapability.visualization},
    promptTemplate: '请解释 {{object_label}} 在最近 {{timeframe}} 的变化原因。',
    preferredReadModels: ['monthly_spend_by_category', 'subscription_changes'],
  ),
  IntentDescriptor(
    name: 'summarize_account',
    labelZh: '账户概览',
    allowedObjectTypes: {'account'},
    preferredCapabilities: {AiCapability.chat, AiCapability.visualization},
    promptTemplate: '请用要点总结账户 {{object_label}} 的近 30 天表现。',
    preferredReadModels: ['holdings_snapshot', 'cashflow_buckets'],
  ),
  // ...
];
```

**纪律**:
- 新加 capsule 前必须先注册 intent，code review 强制检查
- `intent ∉ registered` 在 dev 模式 `assert(false)`，prod 模式回落到 `suggestedPrompt`
- `intent × object_type` 不匹配 → capsule 不渲染（不会出现「在 expense 上看到 stress_test_plan」）

### 5.8 实施硬约束（PR review 检查项）

新 AI 相关 PR review 时必须逐条勾选。漏一条不通过。

- [ ] **唯一入口**: 没有新的 `openAiChat(...)` / `Navigator.push(ChatPage(...))` 风格 API；所有调起都经过 `AiIntentInvocation`
- [ ] **默认 surface**: 入口默认渲染 bottom sheet；route push 仅作为 "expand to chat" 的二级动作或屏幕过窄的 fallback
- [ ] **Object-semantic label**: capsule / 入口文案 不允许出现 "Ask AI" / "AI 分析"；必须是对象语义动作
- [ ] **Intent 注册**: 新 intent 在 `intent_policy.dart` 注册，含 `labelZh` / `allowedObjectTypes` / `promptTemplate`
- [ ] **风险分层**: proposal 的 `interaction_mode` 通过 `deriveMode(p)` 派生，不允许 feature 代码硬编码；不允许降级
- [ ] **Calm 视觉**: 无渐变 / glow / 巨型 AI icon；sparkle 字号 ≤ 正文；色彩默认 surface tone
- [ ] **Trace**: 新 surface 调用 AI 必填 `AiTrace.invocation` 字段（source / intent / object）
- [ ] **Three-tier 平衡**: 单独加 ambient / contextual / global 任一层之前确认另两层是否对该数据有覆盖

### 5.9 当前差距 → 三层入口 mapping

| 当前问题（来自 UX 审计） | 归属层 | 修复方向 |
|--------------------------|--------|----------|
| Home insight 卡片不能深链 chat | Ambient → Contextual 缺桥梁 | insight tap 构造 `AiIntentInvocation(intent: 'explain_insight')` 打开 bottom sheet |
| Feature 页无 AI 入口 | Contextual 缺失 | 详情页右上角 capsule（触发式优先：长按 / 选中文本菜单；少数高频对象常驻） |
| Tool result 多为 raw JSON | Visualization capability 未实现 | Wave 34 domain renderer 4 个高价值优先 |
| ~~Proposal 单一确认流~~ | ✅ Wave 38 — propose_card 已按 mode 三分支（oneTap / confirmDiff / typed），swipe 当前等价 confirmDiff（等真实手势 wave）| — |
| Undo 仅 chat 内 60s | global feedback 缺失 | persistent undo snackbar 接 `DriftUndoStack` |
| 冷启动固定 prompt | onboarding 缺失 | sample intents 从 `intent_policy` 当前 active 集合派生 |

### 5.10 四层入口重构（S0–S6 蓝图）

> 状态: **S0–S4 + S6 已落地**（命令栏成为 AI 主入口 / Layer 3 三动作 + 两类新洞察 / Layer 2 capsule 铺开 / 隐私 UI），**S5（Layer 4 录入管道）S5a + S5a.1 + S5b + S5c 已落地**（端侧解析/去重/草稿/确认链 + Layer 3 洞察卡 + 全量 l10n + 隐私门 + 后端多模态 Vision + 完整 AiTrace + 文件/相机/拖拽/分享捕获；唯 iOS Share Extension Xcode target + S5d 待做，详细方案 §5.10.10）。§5.1–5.9 的 wire / 视觉 / 风险契约不变，本节只重构**入口拓扑与全局形态**——把 AI 表面从「一个目的地 tab + sheet + page」改写为「**无目的地的环境能力**」。判断标准: 把 AI 全部拿掉，产品依然完整、好看、好用。详见 §5.10.8 状态表与 §5.10.9 偏离记录。

#### 5.10.1 四层模型

四个表面互不抢戏，按用户主动度从高到低、作用范围从全局到上下文排列。**没有 `/ai` tab，没有右下角悬浮气泡，没有 ✨ 按钮散在每个面板旁。**

| Layer | 名称 | 触发者 | 形态 | §5.2 三层模型对应 |
|-------|------|--------|------|----------------------|
| 1 | 统一命令栏 | 用户主动 / 全局 | Cmd-K overlay / 顶栏 search / 主屏下拉 spotlight | Global AI（重塑：不再是 `/ai` tab，而是 overlay） |
| 2 | 内联上下文 Capsule | 用户主动 / 局部 | 图表 ⋯ 菜单 / 表格选区工具条 / 卡片长按 sheet | Contextual AI |
| 3 | 环境式洞察 | 系统主动 | 主屏卡片，三动作（展开 / 问一下 / 忽略） | Ambient AI（增强） |
| 4 | 录入链路隐形 AI | 系统主动 / 无入口 | 截图 / 邮件 / 文件粘贴自动解析 + 去重对账 | **新增**（§5.2 未覆盖） |

**保留不变**: §5.4 inline bottom sheet 仍是 Layer 2 的默认渲染形态；§5.5 `interaction_mode` 派生表与 PersistentUndoBanner 仍生效；§5.7 `intent_policy` 治理仍生效；§5.8 PR 硬约束在本节 §5.10.7 之上累加，不替换。

#### 5.10.2 主要拓扑变更

1. **`/ai` tab 下线**: 5-tab → 4-tab（Home / Activity / Accounts / Settings）。`features/ai_chat/ui/ai_chat_page.dart` 不再是 tab 着陆页，迁至 `/settings/ai-history`（沿用 `AiTransparencyPage` 位置语义），仅作只读历史回放；新会话默认走命令栏的结构化结果区。
2. **命令栏升级为唯一显式 AI 入口**: `core/command_palette/` 现行 "Ask AI" 是 prefill 后跳 `AiChatSheet`；新行为是**就地出结构化答案**（表格 / 数字 / 小图 + 一段简短解释），overlay 不留对话历史。回放进 `/settings/ai-history`。
3. **Ambient 卡片改造**: `features/home/ui/ai_insight_feed.dart` 卡片由"点开跳转"单一 affordance → 三动作（展开 / 问一下 / 忽略）+ 偏好学习（新 Drift 表 `dismissed_insight_keys`）。
4. **新增 `features/ingest/` 模块**: Layer 4 此前完全空白；新增统一解析管道 + 去重对账层 + 待确认队列。

#### 5.10.3 §5.2 三层模型 → §5.10 四层模型归并

| §5.2 旧条目 | §5.10 新归类 | 备注 |
|-------------|---------------|------|
| Ambient AI (insight feed) | Layer 3 | 卡片三动作 + 偏好学习；规则引擎独立化 |
| Contextual AI (capsule) | Layer 2 | 默认 surface 仍是 inline bottom sheet（§5.4 不变） |
| Global AI (chat tab + command palette) | Layer 1（命令栏） + `/settings/ai-history`（聊天回放） | 拆分：探索性入口收敛到命令栏 overlay；session 历史降级为审计页 |
| — | Layer 4（录入隐形 AI） | 新增；不是 surface，而是「无入口」——任何粘贴/拖拽/转发都被理解 |

#### 5.10.4 视觉契约（在 §5.6 上加严）

§5.6 已禁止 chatbot 气泡 / 渐变 / glow。在本节再加严:

- **`Icons.auto_awesome`（实心 ✨）全量替换**为 `Icons.auto_awesome_outlined` 或 `core/ai/visual/ai_pill.dart` 现有的 `Generated` 角标。盘点替换点: `app/app_shell.dart`、`core/command_palette/default_commands.dart` + `command_palette_dialog.dart`、`features/ai_chat/ui/{message_bubble, tool_invocation_inline, ai_chat_page, ai_bottom_sheet, ai_chat_sheet}.dart`、`features/activity/ui/activity_entry_detail_page.dart`。
- **等宽数字**: `design_system/tokens/` 新增 monospace numeral token，应用到 `features/home/ui/{trend_card, allocation_card}.dart`；金额一律右对齐、千分位、固定小数位。
- **AI 状态指示文字**: 命令栏右下角一行小字，三态 `本地处理` / `云端处理（已脱敏）` / `云端处理`，从 `privacyModeProvider`（§5.10.5 新增）实时取。
- **暗色模式默认**: 财务用户夜间查账多，深色背景让数字更醒目。

#### 5.10.5 隐私 UI（落实 §4 的 PrivacyBudget / ScopedDisclosure / AiTrace 用户感知）

`PrivacyBudget` / `ScopedDisclosure` / `AiTrace` 契约已实现但用户感知不到。新增:

- 新 `features/settings/ui/ai_privacy_page.dart`: 三选一 radio（金额可上行 / 金额掩码量级 / 金额完全本地）+ 账户名/机构名脱敏开关；状态写入新 `privacyModeProvider`，下沉到 `core/ai/contracts/privacy_budget.dart` 的运行时入口（运行时根据该 provider 选择 PrivacyBudget tier）。
- 审计页强化: `features/settings/ui/ai_transparency_page.dart` 每行写入操作加 "撤销" 按钮，直连 `core/ai/write/drift_undo_stack.dart`。
- 首次 onboarding: `app/bootstrap.dart` 加一次性 sheet 引导隐私模式选择，写 `shared_preferences` 标记。

#### 5.10.6 不可逆操作护栏（在 §5.5 风险表上加一条）

命令栏接到不可逆意图（转账、下单、删除账户）→ **拒绝执行**，只回操作指引。实施:

- `core/ai/intent/intent_policy.dart` 新增 `requiresExplicitConfirmation` 字段（IntentDescriptor 元数据）。
- 命令栏检测到 `requiresExplicitConfirmation == true` 的意图 → 强制弹二次确认 sheet，复用 `core/ai/write/local_immediate_executor.dart` + `drift_undo_stack.dart` 撤销链。
- AI 在任何 surface（Layer 1–4）都**不可作为不可逆操作的最终执行者**——只能产出 `ProposalEnvelope`，由用户确认面完成提交。

#### 5.10.7 反模式清单（PR review 一票否决，与 §5.8 并列累加）

- 右下角悬浮聊天气泡
- 底部多一个 "AI" tab（包括 5-tab 复活）
- ✨ / 魔法棒 / glow 撒在每个面板旁
- 一打开 app 先看到 chat 界面而不是数据
- AI 直接给出「该买/该卖 XX」的投资建议
- LLM 直接计算金额并显示（必须经 §4 ToolDescriptor 工具路径，落到 read model）
- 把转账/下单做成 AI 一句话就能触发的命令
- 紫色渐变 / 彩虹色 / 机器人头像

#### 5.10.8 执行序列（S0–S6）

后续 PR 纲领。**S0 = 本节**；S1–S6 各自一条 issue。依赖链: S1 阻塞所有 UI 工作；S5 与 S2–S4 可并行；S6 在 S2 之后任意插入。

| 序号 | 状态 | 名称 | 关键文件 / 路径 | 依赖 | 备注 |
|------|------|------|------------------|------|------|
| S0 | ✅ | 本节文档（蓝图对齐） | `docs/ai-architecture.md §5.10` | — | 后续 PR review 依据 |
| S1a | ✅ | 拓扑重构（去 tab + 路由迁移 + ARB） | `app/route_paths.dart`、`app/router_builder.dart`、`app/app_shell.dart`、`l10n/app_*.arb` | S0 | 5-tab→4-tab；FIRE/Rebalance/Analytics 迁到 `/accounts/{fire,rebalance,analytics}`；chat 迁 `/settings/ai-history`；`isAccent`/accent-disc 全删；`kPrimaryTabCount` 5→4；vim `g i` 删除 |
| S1b | ✅* | 视觉去 sparkle + monospace token | `core/command_palette/`、`features/ai_chat/ui/`、`design_system/tokens/typography_tokens.dart`（新 `numericMono`）、`test/golden/`、`docs/visual-baseline/` | S1a | 4 处实心 ✨→outlined；空状态紫渐变圆→中性圆。*Golden 重拍待 Linux CI（macOS 本地按 `flutter_test_config.dart` skip 像素 diff，非阻塞） |
| S2 | ✅ | 命令栏成为 AI 主入口 | `core/command_palette/command_palette_dialog.dart`、新 `core/command_palette/ask_ai_result_pane.dart`、`core/ai/intent/intent_policy.dart`（加 `requiresExplicitConfirmation`）、复用 `nl_to_query_plan.dart` + `query_plan_executor.dart` + `drift_query_plan_executor.dart` | S1 | 结构化答案就地渲染；不可逆 NL 关键词护栏；"去 AI 历史继续"回退；旧 in-list "Ask AI" 行删除 |
| S2.5 | ✅⚠ | 移动端命令栏入口（回归修补） | `core/shortcuts/global_shortcuts_scope.dart`（Actions 层在触屏平台也挂载）、`app/app_shell.dart`（`_CommandBarPill`）、`l10n`（`commandPaletteMobileEntryHint`） | S2 | S1a 删了 `/ai` tab 但没补移动端入口 → 触屏一度无任何方式打开命令栏。补：`_MobileShell` 顶部 spotlight 式 pill → `Actions.maybeInvoke(OpenCommandPaletteIntent)`。⚠ 主屏下拉手势仍 deferred——见 §5.10.9 |
| S3 | ✅⚠ | Layer 3 卡片三动作 + 两类新洞察 | `features/home/ui/ai_insight_feed.dart`、新 `features/home/data/duplicate_charge_insight_provider.dart`、新 `monthly_summary_insight_provider.dart`、新 `dismissed_insights_store`、新 `core/ai/local/skills/duplicate_charge_detector.dart` + `expense_to_transaction_input.dart` | S2 | 三动作（展开/问一下/忽略）；新 `InsightKind.duplicateCharge`/`monthlySummary`。⚠ dismissed store 用 `shared_preferences` 而非 Drift 表——见 §5.10.9 |
| S4 | ✅⚠ | Layer 2 Capsule 铺开 | 新 `core/ai/intent/ai_context_chip_scope.dart`、`intent_policy` 注册 `explain_chart`+`transactions.explainSelection`、`features/home/ui/{trend_card,allocation_card}.dart` capsule、`regression_corpus.dart` | S2 | `AiObjectCapsule` 自动 merge scope chips。⚠ expense_list 选区工具条 deferred 到 S4.5——见 §5.10.9 |
| S5a | ✅⚠ | Layer 4 草稿队列 + 端侧解析（零云端） | `features/ingest/`（domain/data/ui · pipeline/dedup/draft store/confirm）、Drift v7→v8（`ingest_drafts` + `ingest_attachments`）、`activity_page.dart` 入口 + `/activity/ingest` 路由 | OpLog 表迁移（独立线） | 落地：CSV/paste 端侧解析 → 复用 `txn_classifier` 归一 → 对 Drift 真源去重 → `ingest_drafts`（本地不入 OpLog）→ 确认走现有 `ProposalApplier`（expense 计划）→ Drift/OpLog/AiTouch。30 个单测 + analyze clean。偏离见 §5.10.9 |
| S5a.1 | ✅ | Layer 4 环境式洞察 + l10n | `features/home/{domain/insight_models,data/dashboard_insights_provider,ui/{ai_insight_feed,insight_feed_strings}}.dart` + `InsightKind.ingestQueue`、新 `features/ingest/data/ingest_queue_insight_provider.dart`、`l10n/app_*.arb`（+25 key 双语）、`cn_literal_allowlist.txt` 收口 | S5a | 落地：队列以 Layer 3 洞察卡静默冒泡（行点 deep-link `/activity/ingest`，dismissable scopeHash `pending:fresh`）；`ingest_review_page` 全量 ARB 化并移出 allowlist；顺带清掉 main 上既有 cn-gate 红（`ask_ai_result_pane` 按 intentional-keyword 归类 + 4 条 stale 项剪除）→ cn/enum/l10n-parity/known-failing 四 gate 全 exit 0 |
| S5b-gate | ✅ | Layer 4 隐私门（端侧） | 新 `features/ingest/data/ingest_privacy_gate.dart`（纯决策）、`providers.dart` `IngestController` 接 `aiPrivacySettingsProvider` | S5a | 落地：image/pdf/email 需云端 → `amountsLocal` 直接拒绝（隐私文案）、`amountsAllowed/Bucketed` 放行但回「S5b-vision 待接入」；csv/paste 永不过门。穷举单测（kind×mode）|
| S5b-vision | ✅ | Layer 4 后端 Vision + 完整 AiTrace | 新 `apps/backend/src/routes/ingest.rs`(`POST /ingest/parse`)、新 `apps/backend/src/ai/ingest/{mod,parse}.rs`（`emit_parsed_transactions` 强制 tool_use，**非 chat ToolRegistry**）、`AnthropicAdapter::complete()` 非流式单发（Bearer+x-api-key）、mobile `cloud_ingest_client.dart` + `IngestController._ingestCloud` + 完整 `AiTrace` append；多模态模型经 `ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_BASE_URL`/`ANTHROPIC_DEFAULT_OPUS_MODEL`（token 走 wrangler secret，不入库） | S5b-gate | 落地：图像即用即弃零留存；cargo fmt/clippy(wasm32 -D warn)/test 157 pass；mobile analyze+37 ingest 测试+known-failing gate 全绿。顺带修复 main 既有 `sha2 0.11`/`hmac 0.12` 构建破（#133），见 §5.10.9 |
| S5c-pick | ✅ | Layer 4 文件捕获（跨平台） | 新 `features/ingest/data/{capture_encoder,ingest_capture_source}.dart`、`ingest_review_page` 顶栏/空态「导入文件」+ 共享 `_runIngest`、ARB `ingestImportFileAction`（双语） | S5b | 落地：复用**既有** `file_picker`（零新依赖）—— 选图/PDF/CSV → 纯 `ingestSourceFromCapture`（扩展名定 kind/mime；二进制 base64、文本 utf8）→ 经隐私门走 device/cloud；analyze + 41 ingest 测试 + 四 gate 全绿 |
| S5c-native | ✅⚠ | Layer 4 原生捕获入口 | `image_picker`（相机）/`desktop_drop`（拖拽）/`receive_sharing_intent`（分享）+ `cross_file`；新 `share_intent_service.dart`（自守卫，挂 `AppRootShell`）、`xFileToIngestSource`/`CameraIngestCapture`、`ingest_review_page` 三入口（拍照/导入/粘贴 + `DropTarget` + 空态 Wrap）、Android `SEND`/`SEND_MULTIPLE` intent-filter、iOS Info.plist 相机/相册用途串、ARB `ingestCameraAction` | S5c-pick | Dart/Android 全落地：pub get 解析、analyze clean、41 ingest 测试、known-failing/cn/enum/l10n gate 全绿。**⚠ 残留**：iOS Share Extension 需 Xcode 单独 native target（app group + entitlements + 签名），见 §5.10.9 |
| S5d | ⬜ | Layer 4 邮件 webhook | Cloudflare Email Routing、`/ingest/email`、服务端 `ingest_inbox` 队列 + 设备拉取 | S5b-vision | 见 §5.10.10 |
| S6 | ✅ | 隐私 UI + Onboarding | 新 `features/settings/ui/ai_privacy_page.dart`、新 `core/ai/contracts/privacy_mode_provider.dart`、新 `features/settings/ui/ai_privacy_onboarding.dart`、`features/settings/ui/ai_transparency_page.dart` 加 undo section | S2 之后任意插入 | 三选一 mode→`maxBudgetTier`/`AnonymizationLevel` 映射；首启 onboarding sheet 挂 HomePage；审计页列待撤销项 |

状态图例: ✅ 已落地 · ✅* 已落地但有外部待办 · ✅⚠ 已落地但偏离 spec（见 §5.10.9）· ⬜ 未开始

每条 issue 在 review 时必须勾选: **§5.8 既有硬约束** + **§5.10.7 反模式清单**。S1a/S1b 合并后需在 Linux（CI / Docker）跑一次 `flutter test test/golden --update-goldens` 重拍基线并与 `docs/visual-baseline/` 同步。

测试现状（截至 S6 + S2.5 + YTD bugfix）: `flutter analyze --fatal-infos` clean；`flutter test` 1235 passing / 17 skipped（golden，按平台 skip）/ 0 failing。

#### 5.10.9 偏离记录（spec ↔ 实现）

落地过程中相对 §5.10.8 关键文件清单的有意偏离，后续 PR 需知晓:

- **S3 — dismissed store 用 `shared_preferences` 而非 Drift 表 `dismissed_insight_keys`**。理由: Drift schema bump 牵涉 `app_database.dart` 升版 + `build_runner` 重生 `.g.dart` + onUpgrade 迁移，对 S3 体量过重。`DismissedInsightsStore` 的公共 API 完全隐藏存储后端（`watch()` / `dismiss()` / `currentSnapshot()`），未来 Drift 化是单点替换、不动调用方。代价: dismissal 状态目前不跨设备同步（视为本地偏好，可接受）。
- **S4 — expense_list 选区工具条 deferred 到 S4.5**。`transactions.explainSelection` 意图与 regression corpus 已注册，`AiContextChipScope` 基础设施已就绪；缺的是 `ExpenseGroupedList` 的多选状态 + 浮起工具条 + tap 切换 vs navigate 的歧义处理——这是独立的一条 UX 工作线，单独 PR review 更稳。
- **S1b — golden 基线未在本机重拍**。`flutter_test_config.dart` 把 byte-compare 限定在 Linux；macOS 本地 skip 像素 diff（页面仍 pump，render 异常仍会 fail）。S1a/S1b 的视觉改动需 Linux CI 跑 `--update-goldens` 后基线才真正更新。
- **S2.5 — 移动端命令栏入口（S1a 回归修补）**。S1a 删 `/ai` tab 时漏补移动端入口，触屏平台一度完全无法打开命令栏（`Cmd-K` 在 iOS/Android 原生不可用，`GlobalShortcutsScope` 整体透传）。修补: `Actions` 层改为全平台挂载（只把键盘 `Shortcuts` map + vim 处理 gate 在 `areKeyboardShortcutsAvailable`），`_MobileShell` 顶部加 spotlight 式 pill 调 `Actions.maybeInvoke(OpenCommandPaletteIntent())`。**仍 deferred**: §5.10.2 mock 里的「主屏下拉唤出」手势——下拉手势需 overscroll 检测且与各页 ScrollView 协调，单独一条 UX 工作线；持久 pill 已满足"有入口"且更可发现、风险更低。
- **S5a — Layer 3 环境式洞察卡 deferred 到 S5a.1 → ✅ 已解决**。S5a 先落 **Activity 顶栏 `move_to_inbox` 入口 + `/activity/ingest` 审阅页**（`InsightKind` 在 `insight_models` / `dashboard_insights_provider`(`insightScopeHash`) / `insight_feed_strings` / `ai_insight_feed`(`_expandedDetailFor`) 四处穷举 switch，加 kind 牵动四文件 + 双语 ARB + Wave 43 golden，故按 S4→S4.5 同形拆出独立 UX 线）。**S5a.1 已补齐**：新 `ingestQueueInsightProvider` + `InsightKind.ingestQueue` 接入四处 switch，队列以洞察卡静默冒泡、行点 deep-link `/activity/ingest`。Activity 顶栏入口保留为冗余直达。
- **S5a — zh 字面量 allowlist → S5a.1 ✅ 收口**。S5a 期 `features/ingest/**` 入 FIR-99 allowlist 解 unblock。**S5a.1 已收口**：`ingest_review_page.dart` 全量 ARB 化（+25 key 双语，过 Wave 42 parity gate）并移出 allowlist；仅保留两类**本质非显示文案**——(1) `csv_ingest_parser._headerAliases`（中文银行账单表头匹配数据，同 command-palette 关键词豁免）；(2) `ingest_{pipeline,confirm_service}`/`providers` 的数据层异常/拒绝串（无 BuildContext，与顶部 ai_chat 持久层块同源，随该 follow-up 一并重构为结构化句柄）。同时顺带修复 main 上**既有** cn-gate 红（与 S5 无关）：`ask_ai_result_pane.dart` 的不可逆意图关键词按 intentional-matching 归类豁免 + 剪除 4 条 stale 项 → `dart tool/check_cn_literals.dart` 全绿。
- **S5a — 全量 AiTrace append deferred 到 S5b**。S5a 设备侧解析不做一次完整 `AiTrace` 落库（`AiTrace` seed 需 `IntentHint`/`Backend`/`BudgetTier` 等多契约字段，为纯设备摄取合成成本高且脆）。审计闭环已由两点覆盖: `ingest_drafts.trace_id` 列预留 + 确认后 `ProposalApplier` 写 `ai_touched_entities`（AiTouchMark）。当 S5b-vision 引入云端 Vision（真正的模型往返）时再补完整 trace。
- **S5b 拆 S5b-gate（✅）/ S5b-vision（⬜）**。隐私门是纯端侧确定性逻辑、可穷举单测，已落地（`ingest_privacy_gate.dart` + `IngestController` 接 `aiPrivacySettingsProvider`：`amountsLocal` 拒云端摄取，其余放行）。后端 Vision 段开理由：(1) 现有 LLM 适配器**只有流式** `stream()` 接口，Vision 抽取要的是单发 tool-use，需新增非流式路径；(2) 默认模型经 ModelScope Anthropic-compat（`deepseek-ai/DeepSeek-V4-Flash`），Vision 能力与 image content-block 支持未经真 API 验证；(3) ingest 解析工具**不是 chat ToolRegistry 成员**（不能进 LLM tool-loop，否则污染 chat 工具面），是 `/ingest` 路由专用 schema——需独立设计 + 真机/真 API 验证。盲写不可信代码违背「忠实报告」，故段开为 S5b-vision 单独 PR，契约/策略/路由在该 PR 内一次到位。
- **S5b-vision 已落地（解段开）**。后端单发路径以 `AnthropicAdapter::complete()`（`stream:false`，Bearer+x-api-key 双发，复用 `messages_url()`）实现；`/ingest/parse` 路由 auth+rate-limit、零持久化、`emit_parsed_transactions` 强制 tool_use 抽取（坏行跳过非整批失败）；解析工具刻意**不进 chat ToolRegistry**（仅 ingest 路由专用 schema，§5.10.9 第 3 点已遵守）。多模态模型由 `ANTHROPIC_AUTH_TOKEN`（**wrangler secret，绝不入库/不入 git**）+ `ANTHROPIC_BASE_URL` + `ANTHROPIC_DEFAULT_OPUS_MODEL`（非密，`[vars]`）配置，回退 `LLM_API_KEY`/`LLM_BASE_URL`/`LLM_MODEL`。mobile `_ingestCloud` 复用 `planFromParsed`（与 CSV 路径同一 ④⑤⑥：归一/去重/草稿），并 append 一条 `Backend.cloud` 的 `AiTrace`。验证：backend `cargo fmt`/`clippy --target wasm32 -D warnings`/`cargo test --lib` **157 pass**；mobile `analyze --fatal-infos` clean + ingest 37 测试 + known-failing/enum/l10n/cn gate 全 exit 0。
- **顺带修复 main 既有构建破（非 S5 引入）**。`cargo check --target wasm32` 在 pristine HEAD 即失败（已 `git stash` 实证）：commit `86fbd42` 把 `sha2` 0.10.9→0.11.0（digest 0.11），但 `hmac 0.12` 仍要 digest 0.10 → `Hmac<Sha256>: Mac` 不成立，`auth/jwt.rs` + `scoped_detail/{common,category_window}.rs` 全编不过。最小正确修复：`Cargo.toml` `sha2 = "0.10"` + `cargo update -p sha2 --precise 0.10.9`（hmac 0.12 尚无 digest-0.11 兼容版，回退是唯一对齐方式）。这不在 S5 范畴但不修则后端无法验证，按「让所交付可验证」一并处理并记此。
- **S5c 拆 S5c-pick（✅）/ S5c-native（⬜）**。S5c-pick 复用**既有** `file_picker`（零新依赖）落地跨平台文件捕获：纯 `ingestSourceFromCapture`（扩展名 → kind/mime；image/pdf base64、csv/txt utf8）+ 选择器薄封装 + 复用 §5.10.10 隐私门与 device/cloud 双路；可单测（编码纯函数）+ analyze/gate 全绿。S5c-native（`image_picker` 相机 / `desktop_drop` 拖拽 / iOS Share Extension target / Android `SEND` intent-filter receiver / 媒体权限）段开：均需平台 IDE + 签名 + 真机/桌面运行时验证（Share Extension 还是独立 native target + app group + entitlements），盲写不可验证违背「忠实报告」。`file_picker` 已覆盖「把收据/账单/CSV 喂进管道」的全平台诉求，S5c-native 是发现性增强而非阻塞项。
- **S5c-native 已落地（Dart/Android 全部，iOS Share Extension 为唯一残留）**。三库接入：`image_picker`（相机 → `CameraIngestCapture`）、`desktop_drop`（`DropTarget` 包审阅页 body，触屏无害空转）、`receive_sharing_intent`（`ShareIntentService` 挂 `AppRootShell.initState`/`dispose`）。所有捕获经同一纯 `xFileToIngestSource`/`ingestSourceFromCapture` → 隐私门 → device/cloud。**自守卫**：`ShareIntentService` 所有插件调用 try/catch + 流 `onError`，host 测试/web/桌面无 channel 时静默空转——故 `AppRootShell` 无条件 start 仍 build-safe（known-failing gate 实证：app_shell widget 测试无新红）。Android 分享**完全可用**（manifest `SEND`/`SEND_MULTIPLE` filter + 插件，无需 native target）。**唯一残留**：iOS 接收系统分享需 Xcode 建独立 Share Extension target（+ App Group + entitlements + 代码签名）——这是 `receive_sharing_intent` 自身在 iOS 的固有要求，非本仓可盲建/盲验；插件 pod 不建该 target 也不影响 app 编译（`flutter build ios` CI 仍过），仅 iOS 系统分享入口在建 target 前不生效。相机 Info.plist 用途串、相册权限均已就位。

> 计划外 bugfix（非 §5.10 范畴，记此备查）: home hero「年初至今」整数溢出（XIRR Newton 无 rate 上界，对「年初 0 + 年中小买入 + 大 bookend」shape 收敛到 1e12+ 无意义 rate，`*100` 后撑屏 1448px）。已在 `xirr_engine.dart` 加 `_convergedOrFallback` sanity gate（`|rate| > bisectionHigh` → `XirrFallbackAbsolute(reason:'runaway')`）+ Newton 步进 clamp，并在 `home_page.dart` 加 `_isSaneRatio`（`|ratio|≥100` 退回 currency delta）双层防御。回归用例见 `test/features/investment/domain/returns/xirr_engine_test.dart`。

#### 5.10.10 Layer 4 录入解析管道（S5 详细方案）

**定位**: 无入口的隐形 AI。用户的任何「粘贴 / 拖拽 / 转发 / 截图」都被理解，解析成草稿，去重对账后**静默排进待确认队列**——从不自动落账（§5.10.6），从不进 OpLog 直到用户确认（§4.2 draft gate）。判断标准: 把 AI 全部拿掉，产品仍是一个可手动记账的 App。

**管道七段**:

```
①Capture ──▶ ②Route ──▶ ③Parse ──▶ ④Normalize ──▶ ⑤Dedup ──▶ ⑥Draft Queue ──▶ ⑦Confirm
 无入口      端云分流    结构化      复用端侧skill   端侧对账    本地非同步表    ProposalEnvelope
```

| 段 | 做什么 | 关键约束 |
|----|--------|----------|
| ① **Capture** | iOS Share Extension / Android Intent filter / `desktop_drop` 拖拽 / 剪贴板粘贴检测 / 邮件转发 webhook。**不放任何 ✨ 按钮**（§5.10.7） | 入口收敛为单一 `IngestSource{kind, payload, originLabel}` |
| ② **Route** | 按 `kind` 分流：CSV / 银行短信 → 端侧确定性解析器（零联网）；图片 / PDF → cloud Vision。遵循「device-first，云端仅在必要时」 | privacyMode `完全本地` → 云端解析禁用，降级为占位项逐条 opt-in |
| ③ **Parse** | 云端走 `parse_receipt_image` / `parse_statement_pdf` 两个 ToolDescriptor 工具，返回结构化 `{merchant, amount_minor, currency, date, category_hint, confidence, source_span}`——**不是自由文本**（§5.10.7「LLM 直接计算金额」禁止） | 图像在 Worker 内即用即弃，云端零留存；AiTrace 记「原始图像已上云解析（未留存）」 |
| ④ **Normalize** | 复用现成 `merchant_key.dart` / `txn_classifier.dart`；金额转 `Money`（Decimal，minor units） | 不新造启发式——端侧是唯一计算者（§11） |
| ⑤ **Dedup/对账** | 针对 **Drift 真源**（非 read model，避免刚录入未投影）跑模糊匹配 `(merchant_key, amount, date±N)`；复用 `transfer_matcher` / `refund_matcher`；输出 `new / likelyDup / dup` | 去重天然是端侧操作，与 §4.2 freshness 哲学一致 |
| ⑥ **Draft Queue** | 落新 Drift 表 `ingest_drafts`（schema bump，**本地、不进 OpLog / 不同步**）；附件加密本地存 `ingest_attachments`，确认或 N 天后清除 | 守住「Raw Write-side Truth · AI 永远不能直接访问」 |
| ⑦ **Confirm** | 以 Layer 3 环境式洞察静默冒泡（「N 条待确认」）。高置信+无重 → `LocalProposal` one-tap；重复项预标 skip；低置信需先编辑；批量「全部确认」。确认后走**现有 `proposal_applier` → Drift → OpLog**，打 `AiTouchMark`（复用 Wave 39/40） | 永不自动 commit（§5.10.6）；interaction_mode 经 `deriveInteractionMode` 派生，禁降级（§5.5） |

**数据模型（新增，均本地、不同步）**:

```
ingest_drafts      (owner_user_id, draft_id PK, source_kind, parsed_json,
                     confidence, dedup_verdict, dedup_target_entry_id?,
                     trace_id, status[pending|confirmed|dismissed], created_at)
ingest_attachments (draft_id PK, blob, mime, expires_at)   -- SQLCipher 加密
```

后端：`routes/ingest.rs`（图片 / PDF → Anthropic Vision 结构化工具 → `IngestDraft[]` + freshness + trace，**无持久化**）。邮件路径用 Cloudflare Email Routing → `/ingest/email` → 解析后写**独立 `ingest_inbox` 服务端队列**，设备下个同步 tick 拉取落本地 `ingest_drafts`——**绝不注入 OpLog**。

**ToolDescriptor 注册**: `parse_receipt_image` / `parse_statement_pdf` — `access=none`（摄取非查询，不碰 ledger）、`risk=Suggest`、`side_effect=None`（产草稿非写账）、`confirmation=OneTap`、`allowed_runtimes=cloud`（Vision 端侧待 Phase 5）、`read_model_layer` 豁免三层规则（摄取类）。

**执行序列（拆 S5a–S5d，见 §5.10.8 表）**:

| 序号 | 范围 | 依赖 |
|------|------|------|
| S5a | Drift schema + 草稿队列 + 确认 UI；仅 CSV/手动 paste 端侧解析，零云端 | OpLog 表迁移线 |
| S5b-gate | 端侧隐私门（privacyMode 接线） | S5a |
| S5b-vision | 后端 Vision 工具 + 完整 AiTrace | S5b-gate |
| S5c-pick | 跨平台文件捕获（既有 file_picker） | S5b |
| S5c-native | 相机/拖拽/Share Extension/Intent receiver | S5c-pick |
| S5d | 邮件 webhook + `ingest_inbox` 拉取 | S5b-vision |

每条 PR review 在 §5.8 + §5.10.7 之上**再加一条**：摄取草稿在确认前不得出现在 `journal_entries` / OpLog / read model 任一处。

## 6. 模块映射

### 6.1 Mobile (Flutter)

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

### 6.2 Backend (Rust on Cloudflare Workers)

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

## 7. 数据流示例

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

## 8. 实现状态

| Phase | 范围 | 状态 |
|-------|------|------|
| **Phase 1** | contracts + router + trace + 基础 compressor | ✅ |
| **Phase 2-A** | ContextPack 上线（端侧编码 + 后端 ingest + 透明度徽章） | ✅ |
| **Phase 2-B** | rules skills（4 个）+ LocalImmediateWrite/undo | ✅ |
| **Phase 2-C** | ToolDescriptor 元数据 + risk_policy（advisory） | ✅ |
| **Phase 3** | NL→QueryPlan + 5 类 plan + InMemoryExecutor | ✅ |
| **Phase 4** | Embedder 抽象 + InMemoryVectorStore + SemanticMemory（StubEmbedder） | ✅ |
| **★ Read Models — Snapshot 层** | `holdings_snapshot` / `net_worth_snapshot` / `monthly_spend_by_category` / `cashflow_buckets` / `net_worth_daily` / `asset_allocation_snapshot` | ✅ 全部贯通（cloud-projected via `Projection` trait + lazy refresh）|
| **★ Read Models — Analytical 层 P1** | `recurring_patterns` / `anomaly_flags` / `refund_links` / `transfer_links` / `investment_performance` / `subscription_changes` | ✅ 六个 device-sourced 模型全部贯通；`subscription_changes` 当前仅检测**本次 chat 窗口内**的变化（长历史需 OpLog 持久化 `recurring_patterns`） |
| **★ Read Models — Analytical 层 P2** | `xirr_snapshot` | ✅ cloud-projected (Newton-Raphson 确定性算法) |
| **★ Read Models — Scoped Detail 层** | `read_account_window` / `read_asset_window` / `read_category_window` | ✅ 含 purpose 必填 + 硬限额 + sanitised 字段 + HMAC-SHA256(user_id, merchant) 哈希；`get_journal_entries` 仍在表中（schema 隐藏，dispatch 保留兼容），待去除 |
| **★ Schema 公约 + Freshness gate** | `source_hlc_watermark` / `refreshed_at` / `schema_version` / `calculation_version`；SSE tool_result.freshness + 端侧比对 + Phase 2 `force_refresh_read_models` 提示 | ✅ Phase 1 (logging) + Phase 2 (hint) 落地，下一次 chat 自动带 `freshnessHint` |
| **★ ToolDescriptor 扩展** | `allowed_runtimes` (cloud/device bitset) + `side_effect` (None/DeviceLocalWrite/ExternalCall) + `read_model_layer` (Snapshot/Analytical/ScopedDetail) | ✅ 27 个描述符全部填充；mobile 镜像（`tool_descriptor.dart`）字段对齐 |
| **★ risk_policy enforced** | dispatch denied 分支返回合成 `tool_result {error: "policy_denied", policy, tool, message}` | ✅ Wave 21 落地；LLM 看到标准 error 形态可继续工作 |
| **★ AiRuntime + RuntimeRegistry** | `AiRuntime` trait / `RuntimeId` / `CloudAnthropicRuntime` (wraps existing `AiChatApiClient`) / `RulesDeviceRuntime` stub / registry provider | ✅ 抽象层就位；ChatRepository 暂未改走 registry（Phase 5 接入端侧 runtime 时再切） |
| **★ AiTraceStore 持久化** | Drift 表 `ai_traces` (request_id PK + owner partition) + `DriftAiTraceStore`；provider 自动从 in-memory 切换到 Drift | ✅ Wave 23 落地；30 天清理由 caller 调度 |
| **★ Undo stack 持久化** | Drift 表 `ai_undo_stack` (token PK + expires_at) + `DriftUndoStack` (put/take 原子 / pruneExpiredBefore) | ✅ Wave 24 落地；closure-based `LocalImmediateWriteExecutor` 保留作为内存路径，需持久化的 caller 直接用 `DriftUndoStack` |
| **★ `tools.rs` 拆分** | `apps/backend/src/ai/tools/` 目录化 + `xirr` 核心算法提到 `tools/xirr.rs` | ✅ Wave 25 起步；剩余 read/propose 二级拆分待后续增量 |
| **Phase 5** | 端侧 LLM runtime（§4.6：用户自带 key · 直连 provider · 工具读 Drift · 全原生平台含桌面 · cloud 先并存后删） | 🚧 W-D1–4/4.2/4.2b/6 + 桌面支持已落；W-D5/4.3/4.4/4.5/4.2c/7 待续 |

**ToolDescriptor 总数**: 27（Read 20 + Propose 5 + 兼容保留 2）— 见 `apps/backend/src/ai/policy/tool_policy.rs`。每条描述符含七个轴：`name` / `access` / `risk` / `requires_confirmation` / `allowed_context_tier` / `allowed_runtimes` / `side_effect` / `read_model_layer`。`risk_policy.rs::every_dispatch_target_has_a_descriptor` 与 `tools.rs::schemas_advertise_all_dispatch_targets` 双向同步。

**测试覆盖**: backend **140 tests** (`cargo test --lib`，P1 增量 +10：asset_allocation aggregate × 4 / tool_policy invariant × 4 / policy_denied shape × 2；P2 增量 +9：system_prompt_extension formatter × 9) + mobile **158 core/ai tests**（含 P1 的 analytical_uploads × 8 / ai_runtime × 5 / drift_ai_trace_store × 5 / drift_undo_stack × 6 / chat_repository × 23 + freshness gate；P2 的 AiTrace terminal_reason round-trip × 2）。`flutter analyze --fatal-infos lib` 与 `cargo clippy --target wasm32-unknown-unknown --all-targets -- -D warnings` 均干净。剩余 9 个 widget 渲染器失败为 Wave 18 之前的预存遗留（`tool_invocation_renderers_test.dart::_expandCard` 找不到目标 widget），与本次 P1/P2 无关。

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
| 18 | `asset_allocation_snapshot`（Snapshot P1）— per (asset_type, currency) cost basis 聚合 | migration 0016；`get_asset_allocation` 工具 |
| 19 | `subscription_changes`（Analytical P1 完结）— 端侧 `detectSubscriptionChanges` 半窗对比 | migration 0017；`get_subscription_changes` 工具 + skill 模块 |
| 20 | `ToolDescriptor` 扩展三维度 | `allowed_runtimes` / `side_effect` / `read_model_layer` 字段 + mobile 镜像 + invariant tests |
| 21 | `risk_policy` advisory → enforced | `policy_denied_result(name, reason)` 合成 tool_result；`PolicyReason::code/message` 稳定形态 |
| 22 | `AiRuntime` + `RuntimeRegistry` | `lib/core/ai/runtime/ai_runtime.dart`，`CloudAnthropicRuntime` + `RulesDeviceRuntime` + 5 个 registry 测试 |
| 23 | `AiTraceStore` Drift 持久化 | Drift 表 `ai_traces` + `DriftAiTraceStore` + provider 自动切换 + 5 个 round-trip 测试 |
| 24 | `LocalImmediateWriteExecutor` Drift 持久化 | Drift 表 `ai_undo_stack` + `DriftUndoStack` (原子 take) + 6 个测试 |
| 25 | `tools.rs` 拆分起步 | `apps/backend/src/ai/tools/` 目录化；XIRR 核心抽离到 `tools/xirr.rs` |
| 26 | AI 透明度审计页 | `settings/ui/ai_transparency_page.dart` 列表 + 详情；Settings 入口；`/settings/ai-transparency` + `/:requestId` 子路由 |
| 27 | ContextPack → system prompt | `ai/context/system_prompt_extension.rs`：route/base/signals/freshness hint/uploads-by-kind 概要追加在 SYSTEM_PROMPT 之后（不替代）；9 个 formatter 测试 |
| 28 | Drift-backed QueryPlanExecutor | `core/ai/local/skills/drift_query_plan_executor.dart` — `journalExpensesStreamProvider.future` → TransactionInput → 委托给 `InMemoryQueryPlanExecutor` |
| 29 | NetWorthTrendPlan 适配器 | DriftQueryPlanExecutor 直接读 `dashboardTrendProvider` → TrendPoint → QueryRow；本范围内过滤 |
| 30 | AiTraceBuilder terminal reason | `TerminalReason` 枚举（done/streamError/userCancel/policyDenied/closedEarly）+ chat_repository 各分支精细打标 + 透明度页 chip/详情显示 + 兼容旧 trace JSON |
| 31 | ProposalEnvelope.source | `ProposalSource` 枚举 (device/cloud/hybrid) 加到基类，子类透传；`LocalImmediateWriteExecutor.register` 默认 `device`；默认值 `cloud` 兼容旧 caller |
| 32 | ContextPack 收缩 | `FreshnessHint` 新增 `last_local_hlc`（mobile + Rust 双侧 + serde default）；`BaseContext.accounts/cashflow` 标记 deprecated（保留 wire 兼容，未来 v2 移除）；mobile 始终携带 lastLocalHlc 让 freshness 协议自包含 |
| 33 | **§5 AI Entry Framework** | `lib/core/ai/intent/`（`AiIntentInvocation` + 5 intent 注册表 + `renderPromptFor`）；`AiBottomSheetShell` + `showAiBottomSheet`（viewport < 500px fallback Dialog）；`AiObjectCapsule` 可复用 capsule；2 个 proof point（expense detail + home insight）；`AiTrace.invocation` 字段贯穿 trace_builder / chat_repository / 透明度页 |
| 34 | **§5 Contextual Output** | 4 个 domain renderer (`get_asset_allocation` 环形图 + 权重列表 / `get_recurring_patterns` 订阅卡 / `get_subscription_changes` 涨跌 diff bar / `get_refund_links` pair 卡) 接入 `renderToolOutput` dispatch；`reply_chips.dart` 规则化生成 v1（intent-specific 上限 2 + tool-driven + generic fallback），`MessageBubble.onReplyChip` 透传；bottom sheet 内 tap chip 同 invocation trace 续传 |
| 35 | **§5 Trust & Action** | `InteractionMode` 枚举 (oneTap/swipe/confirmDiff/typed) + `deriveInteractionMode(ProposalEnvelope)` (kindLabel-table 派生，禁止 feature 硬编码)；`DriftUndoStack.watchAll()` + `undoEntriesStreamProvider` + `PersistentUndoBanner` 全局挂载在 AppShell footer（calm intelligence：surface tone + 14px sparkle + 撤销 button）；`AiSourceMark` 12px sparkle widget 作 AI 修改字段前缀 |
| 36 | **AI 视觉语言** | 新 `lib/core/ai/visual/` 5 个原语：`AiSparkle` / `AiPill` (neutral/selected/error) / `AiTone` (onSurface/muted/active/error/outline/surfaceTint — 禁止 tertiary/secondary) / `AiType` (body 13 / meta 11 / label 12 / title 16，比 Material 紧 1px) / `AiMotion` (short 120ms / medium 200ms / Linear-style cubic 0.32 0.72 0 1)；6 处 AI surface（capsule / source mark / undo banner / reply chips / timeline / transparency chips / sheet header）全部迁移到原语，无散落 `Icons.auto_awesome_outlined` 或 `colorScheme.tertiary` |
| 37 | **Tool inline + 流式 UX** | 新 `ToolInvocationInline`：domain renderer 命中时直接 inline 渲染（`✦ tool_name` 单行 attribution + 渲染体，无 card 边框），long-press 弹 bottom sheet 显示原 debug 卡作 fallback；未命中域 renderer 继续走原卡（JSON viewer 是唯一有用的呈现）；`_AssistantBody` 接收 `pendingToolName`，流式无文本时显示 `✦ 正在 get_holdings ...` 替代 generic 「思考中」；`_BodySkeleton` 三条 muted bar 1100ms 呼吸代替 spinner 作 bottom sheet 初始态 |
| 38 | **propose_card interaction_mode 分支** | `interactionModeForKindLabel(String)` 公共化（从 `_cloudModeForKind` 提升）；propose_card 按 `_kindLabel(plan.kind)` 派生 mode 三分支：`oneTap` → 新 `_OneTapView`（紧凑单行 `✦ kind` + summary + `Confirm` pill + `Edit/Cancel` 文字按钮，适用 expense 这类低风险）；`typed` → 新 `_TypedConfirmView`（复用 `_ExpandedView` body + 增加「输入「确认」」TextField，未匹配前 Confirm callback 拒绝），目前没有 kindLabel 命中但框架就位；`confirmDiff/swipe` → 维持 `_ExpandedView`（swipe 等真实手势 wave）；`unknown` 安全 fallback confirmDiff |
| 39 | **AiSourceMark end-to-end** | schema v5→v6 加 side-table `ai_touched_entities`（PK `(owner_user_id, entity_type, entity_id)`，存 `touched_at + kind_label + trace_id`，不污染 journal_entries / accounts / liabilities / assets 主表）；新 `DriftAiTouchedStore` (put/lookup/watch/forget + StreamController 触发流) + `aiTouchedStoreProvider` + `aiTouchedAtProvider.family((entityType, entityId))` autoDispose 流；`ProposalApplier.apply()` 成功后 `_recordTouch(plan, state, at)` 写入 (best-effort，失败不影响 apply)；ExpenseFormPage edit 模式下新 `_AiTouchMark` ConsumerWidget 在 capsule 旁渲染 `AiSourceMark`（30 天 stale 阈值，过期不显示，tooltip 含 kindLabel） |
| 40 | **AiTouchMark 全覆盖** | `_AiTouchMark` 私有 helper 提升为公共 `AiTouchMark({entityType, entityId, staleAfter, size})`（在 `core/ai/write/ai_source_mark.dart`），三个新 detail page 接入：`AccountFormPage`（edit 模式，`accounts` 实体）、`CashFormPage`（edit 模式，`assets` 实体，覆盖最常见的 manual valuation 场景）、`ActivityEntryDetailPage`（hero card 上方，`journal_entries` 实体——同时覆盖 trade / liability_payment / expense 三种 ProposalKind 写出的 journal entry）；ExpenseFormPage 改用共享 widget，移除 ~25 行私有副本；所有接入点统一 30 天 stale 阈值，widget 自身 self-gating（无 touch / 过期 → 渲染 `SizedBox.shrink()`） |
| 40.1 | **剩余 asset 子表单接入** | `DepositFormPage` / `WealthProductFormPage` / `EquityAssetDetailPage` 三个 asset 子表单也接入 `AiTouchMark(entityType: 'assets', entityId: …)`，与 Wave 40 的 cash form 等价；至此每种 `AssetType`（cash / deposit / wealthProduct / stock / etf / crypto / mutualFund）的 detail page 均能在 `propose_asset_valuation` 命中后渲染 sparkle 前缀 |
| **测试准出 P0 — Wave 41–44** | | |
| 41 | **Red CI cleanup** | 修 9 个 `tool_invocation_renderers_test._expandCard` 失败（Forui 把 `InkWell` 包成了 `FTappable` 无法直接 findByType — 给 prod 加 `Key('tool-invocation-card-header')`，测试改 findByKey）；修 settings_page_test 货币选择器（从 `find.text('CNY')` 改 `findTextContaining` 适配 "CNY · 人民币" 长 label）；新 `tool/check-known-failing-tests.sh` + `known-failing-tests.txt` 把残存 ~50 个 design-system / golden / widget 测试失败钉成基线，新红色测试触发 CI 阻断；mobile.yml 接入 |
| 42 | **Schema-as-contract** | 新 `tool/check-enum-mirror.sh`（awk 解析 Dart 与 Rust 同名 enum，比对 variant set；12 enum 全绿）+ `apps/mobile/tool/check-l10n-parity.sh`（Python 解析 ARB，比对 top-level key 集；1078 keys 全 mirror）；mobile.yml 接入两个 gate |
| 43 | **AI surface 视觉回归** | 新 `test/golden/ai_surfaces_golden_test.dart` 5 个组件级 golden（AiPill 3 态 / AiObjectCapsule / AssetAllocationView / SubscriptionChangesView / AiTraceTimeline），独立于 `_golden_setup.dart`（page 级 harness 因 `marketColorMode` 移除已破，列在 known-failing-tests.txt）；Wave 36 视觉 token 漂移会触发 golden 失败 |
| 44 | **AI 回归 corpus + 静态契约** | 新 `lib/core/ai/regression/regression_corpus.dart` 含 7 个 fixed prompt × intent × 期望工具集；新 `test/core/ai/regression/regression_corpus_test.dart` 7 条静态契约（id 唯一 / intent 已注册 / 每条期望工具有 renderer 或 jsonOnly 标记 / 期望工具与 intent.preferredReadModels 一致 / 每个 intent 至少 1 条 prompt）；catch 了 2 处 intent_policy 与实际期望工具不一致的真实 drift（`explain_change` 缺 `recurring_patterns`、`explain_insight` 缺 `refund_links` — 同步补齐）；live LLM 跑 corpus 的 nightly 留作 P1 增量 |

## 9. TODO

按优先级排列。**P0 + P1 全部完成（Wave 1–25）**；P2 是体验增强，P3 进入 Phase 5。

### P0 — 主通道（✅ 全部完成 Wave 1–17）

- [x] ~~**Read Models — Snapshot 层 P0 三表**~~ — `holdings_snapshot` / `net_worth_snapshot` / `monthly_spend_by_category` 全部 cloud-projected + lazy refresh
- [x] ~~**Read Model schema 公约**~~ — 五字段公约 + `Freshness` / `Projection` 抽象 (`apps/backend/src/ai/read_models/freshness.rs`, `projection.rs`)
- [x] ~~**`tools.rs` facade 改造**~~ — `get_holdings` / `compute_net_worth` / `get_industry_breakdown` / `get_geo_breakdown` / `get_market_cap_breakdown` / `get_monthly_spend_by_category` / `get_net_worth_summary` / `get_cashflow_buckets` 全部从 read model 读，带 `freshness` 元数据
- [x] ~~**Freshness gate 协议**~~ — SSE `tool_result.freshness` (Phase 1 logging + Phase 2 `pendingFreshnessHintProvider` → 下次 chat 携带 `forceRefreshReadModels` 提示) — 见 `apps/mobile/lib/features/ai_chat/data/providers.dart`、`apps/mobile/lib/features/ai_chat/state/chat_sync_gate.dart`
- [x] ~~**废弃 `get_journal_entries` → Scoped Detail 工具族**~~ — `read_account_window` / `read_asset_window` / `read_category_window` 落地：必填 `purpose` + 硬限额 ≤ 50 + HMAC-SHA256(user_id, merchant) 哈希 + sanitised 字段 + 共享 `scoped_detail/common.rs` 帮手；`get_journal_entries` schema 已从 LLM 视野隐藏（dispatch 保留以防回归）

### P1 — 现有路径稳定 + 启用生产（✅ 全部完成 Wave 18–25）

- [x] ~~**Read Models — Snapshot 层 P1**~~ — `asset_allocation_snapshot` 落地（Wave 18），`cashflow_buckets` / `net_worth_daily` 在 P0 完成
- [x] ~~**Read Models — Analytical 层 P1**~~ — 六模型全部落地：`recurring_patterns` (W10) / `anomaly_flags` (W11) / `refund_links` + `transfer_links` (W16) / `investment_performance` (W17) / `subscription_changes` (W19)
  - 注：`subscription_changes` 当前只检测**本次 chat 上报的 expense 窗口内**的变化（earlier-half vs later-half median diff）。跨会话长历史比对需把 `recurring_patterns` 通过 OpLog 持久化到 Drift —— P3 工程项
- [x] ~~**`AiRuntime` 抽象 + RuntimeRegistry**~~ — `lib/core/ai/runtime/ai_runtime.dart`：`CloudAnthropicRuntime` 包装现有 `AiChatApiClient`，`RulesDeviceRuntime` 为 Phase 5 占位。`ChatRepository` 暂未改走 registry（Phase 5 接入端侧 runtime 时切换以避免现在 churn）
- [x] ~~**AiTraceStore 持久化**~~ — `DriftAiTraceStore` + `ai_traces` 表 (request_id PK + owner partition + started_at index)。Provider 自动从 in-memory 切换到 Drift。30 天清理由 caller 触发 `pruneOlderThan(...)`
- [x] ~~**LocalImmediateWriteExecutor 持久化**~~ — `DriftUndoStack` + `ai_undo_stack` 表 (token PK + expires_at)。原子 `take(token)` 通过事务保证两次 undo 不并发执行
- [x] ~~**risk_policy advisory → enforced**~~ — `tools::dispatch` denied 分支直接 return `policy_denied_result(name, reason)` 合成 `{error: {code: "policy_denied", policy, tool, message}, policy_denied: true}`，LLM 看到的就是标准 tool error
- [x] ~~**`tools.rs` 文件拆分**~~ — `apps/backend/src/ai/tools/` 目录化 + `xirr` 核心算法迁到 `tools/xirr.rs`（Wave 25）。剩余 read/propose 二级拆分作为后续增量
- [x] ~~**`ToolDescriptor` 加 `allowed_runtimes` + `side_effect` + `read_model_layer`**~~ — Wave 20：27 描述符全部填充，mobile `tool_descriptor.dart` 镜像对齐，含 invariant tests（proposals 必有 DeviceLocalWrite side effect / reads 必无 side effect / ScopedDetail 必至少 Standard tier / 每条都允许 cloud）

### P2 — 增强（✅ 全部完成 Wave 26–32）

- [x] ~~**AI 透明度审计页**~~ — Wave 26：`features/settings/ui/ai_transparency_page.dart` 含列表 + 详情；Settings 入口；GoRouter 路由 `/settings/ai-transparency` 与 `:requestId` 子路由；显示路由原因 / 终止原因 / 工具调用 / disclosures / stale 列表
- [x] ~~**ContextPack 进 system prompt**~~ — Wave 27：`ai/context/system_prompt_extension.rs` formatter 把 route / base / signals / freshness hint / device upload 概要 append 在 SYSTEM_PROMPT 之后；9 个 unit tests
- [x] ~~**Drift-backed QueryPlanExecutor**~~ — Wave 28：`DriftQueryPlanExecutor` 读 `journalExpensesStreamProvider.future` → `TransactionInput[]` → 委托 `InMemoryQueryPlanExecutor`；Riverpod provider `driftQueryPlanExecutorProvider`
- [x] ~~**`NetWorthTrendPlan` 适配器**~~ — Wave 29：`DriftQueryPlanExecutor.run` 对 `NetWorthTrendPlan` 改读 `dashboardTrendProvider`，过滤范围后映射 `TrendPoint → QueryRow`
- [x] ~~**AiTraceBuilder 错误/取消细分 reason**~~ — Wave 30：`TerminalReason` 枚举（`done` / `streamError` / `userCancel` / `policyDenied` / `closedEarly`）；`finalize(terminalReason:)` 参数；chat_repository 各分支精细打标；wire 兼容老 trace（missing → done）
- [x] ~~**`ProposalEnvelope.source` 字段**~~ — Wave 31：`ProposalSource` 枚举（`device` / `cloud` / `hybrid`）+ `ProposalSourceWire`；基类构造透传；`LocalImmediateWriteExecutor.register` 默认 `device`；默认值 `cloud` 兼容旧 caller
- [x] ~~**ContextPack 收缩**~~ — Wave 32：`FreshnessHint.lastLocalHlc` (mobile + Rust 双侧加 `#[serde(default)]`)；mobile 始终携带 lastLocalHlc 让 freshness 协议自包含；`BaseContext.accounts/cashflow` 标记 deprecated（wire 兼容保留，等 ContextPack v2 移除）

### P2.5 — Interaction Grammar（契约见 §5）

按 §5 落地 AI native UI/UX。三个 wave，先建框架再补能力，最后调可信度。**proof point 数量遵从 §5.8 硬约束**——每个 wave 只接 2 个 feature page 验证架构，剩余在 33.x / 34.x / 35.x 渐进铺开。

- [x] ~~**Wave 35 — Trust & Action**~~ — `InteractionMode` + `deriveInteractionMode`（`ExternalSideEffect`/`LocalProposal`/`LocalImmediateWrite` 走类型决定，`CloudProposal` 按 kindLabel 表派生，未知 kind → confirmDiff 安全默认）；`DriftUndoStack.watchAll()` 加 `StreamController<void>` 触发；`undoEntriesStreamProvider` + `PersistentUndoBanner` 全局挂载在 AppShell footer；`AiSourceMark` 12px sparkle widget 已就绪
- [x] ~~**Wave 34 — Contextual Output**~~ — 4 个 domain renderer 接入 `tool_invocation_renderers.dart` dispatch；`reply_chips.dart` 规则生成（intent-specific 上限 2 + tool-driven + generic）；`MessageBubble.onReplyChip` 透传至 `AiBottomSheetShell._sendChip` 续发；chip 复用原 invocation trace 让透明度页 group 跟随对话深度
- [x] ~~**Wave 33 — AI Entry Framework**~~ — 落地于 `lib/core/ai/intent/` + `lib/features/ai_chat/ui/ai_bottom_sheet.dart`
  - `AiIntentInvocation` / `AiObjectRef` / `AiCapability` 类型（`ai_intent_invocation.dart`）；`intent_policy.dart` 注册 5 个 intent (`explain_change` / `summarize_account` / `stress_test_plan` / `compare_period` / `explain_insight`) 含 prompt template + 占位符填充
  - `AiBottomSheetShell` + `showAiBottomSheet(context, invocation:, objectLabel:)`：modal sheet 覆盖当前页面；viewport < 500px 时自动升级为 fullscreen Dialog（§5.4 fallback）；session 落到 ChatHistoryStore；`展开对话` 按钮 `context.go('/ai?selected=<sid>')`
  - `AiObjectCapsule`：可复用对象级 capsule（surface tone + Icons.auto_awesome_outlined 14px + bodySmall 标签）
  - 2 个 proof point: expense detail capsule（`explain_change`，note 作 objectLabel）+ home insight 卡片 capsule（`explain_insight`，stable id 派生自 kind+key fields）
  - `AiTrace.invocation` 字段 (Map\<String,Object?\>)：附加 source/intent/object_type/object_id/context_keys；透明度详情页新增「触发来源」section；roundtrip + null-omitted 测试
  - `ChatRepository.sendMessage(invocationTrace:)` 透传给 `AiTraceBuilder.attachInvocation`
  - 测试：7 个 intent_policy 单测（lookup / render / trace shape）+ 2 个 AiTrace.invocation roundtrip

### P3 — Phase 5 / 长期 / 未来 feature

- [ ] **Read Models — Analytical 层 P2 四模型** — `spending_clusters` / `goal_progress_projection` / `tax_lot_analysis` / `financial_behavior_profile`，nightly cron
- [ ] **Read Models — Scoped Detail 层完善** — purpose-bound 工具族补齐（`read_trip_cluster` / `read_subscription_history` 等），与 Analytical 层 drill-down 链路打通
- [ ] **Phase 5 — 端侧 LLM runtime（决策见 §4.6：用户自带 key · 最小后端 · 原生 only · cloud 先并存后删）**:
  - [x] ~~**W-D1** SecureKeyStore for LLM key + 设置页输入/校验/清除 UI（原生 only gate）~~ — `core/ai/llm_credentials/`（model + store + providers）+ `settings/ui/ai_llm_credentials_page.dart` + `/settings/ai-llm` 路由；`deviceLlmAvailableProvider` 为 W-D3 registry 入口（fail-closed）；15 tests
  - [x] ~~**W-D2** Dart Anthropic adapter（Messages + SSE streaming + `tool_use`），port 自 `apps/backend/src/ai/adapters/anthropic/`~~ — `core/ai/runtime/device/anthropic/`（wire + 流式 SSE decoder + dio client + 一发 `complete` for W-D5）+ provider-neutral `LlmStreamEvent`（backend `AgentEvent` 镜像）；16 tests（含 4 个 event_map.rs 平价用例 + chunk-boundary）
  - [x] ~~**W-D3** 端侧 `AgentLoop`（port `agent_loop.rs`：tool round budget + propose 拦截）+ `DeviceLlmRuntime` 注册 + `RuntimeRegistry.pickFor` 改造 + `ChatRepository` 改走 registry~~ — `device_agent_loop.dart`（port `run_inner`+`collect_model_round`，输出现有 `AiChatEvent`）+ `device_session.dart` + `device_system_prompt.dart`（SYSTEM_PROMPT 逐字 port + 常量）+ `device_tool_dispatcher.dart`（W-D4 占位）；`RuntimeId.deviceLlm` + `DeviceLlmRuntime`；`RuntimeRoutingAiChatApiClient` 让 `ChatRepository` 零改动经 registry 选择（`deviceLlmRuntimeProvider` 按 `deviceLlmAvailableProvider` 构建，null→cloud，行为与现状一致）；9 tests（含 agent_loop.rs 多轮/propose cap/provider error/timeout/budget 平价用例）。注：`pickFor` 保持 `Backend` 映射作 trace label，runtime 选择按可用性在 provider 层（§4.6.2）；mid-turn provider-error→cloud 失效转移留 W-D6
  - [~] **W-D4** 端侧 tool registry（框架 + proof tool 完成；其余工具族增量）— `runtime/device/tools/`：`DeviceTool`/`DeviceToolContext`、`DeviceToolRegistry`（schemas feed + 排序）、`DriftDeviceToolDispatcher`（per-tool 15s timeout + backend `policy_denied`/`tool_timeout`/`tool_error` 信封逐字 port + §4.5 external_call 拒绝）；proof tool `list_payment_accounts`（schema/desc 逐字 port，读 `accountsStreamProvider` + 纯 `shape()` 复刻 backend payload filter）；接入 `deviceLlmRuntimeProvider`；11 tests。**allow-list 决策见 §11**。剩余工具族（Snapshot/XIRR 复用 `domain/services/` · Analytical 直连 detector · Scoped Detail 查 Drift 去 HMAC · propose_*）= W-D4.2~W-D4.5 增量
    - **W-D4.2 进行中**：`get_holdings` 落地（schema/desc 逐字 port）。提取 `devicePortfolioSnapshotProvider`（`_buildPortfolioSnapshot` 从 ai_chat 移到 `investment/data/providers.dart`，云/端两路共用一个 builder，DRY）；端侧 `get_holdings` 复刻 backend `client_portfolio_snapshot` 分支（端侧持仓引擎即真值，无 read model 故无 freshness gate）；纯 `shape()` 单测；23 个 chat_repository 回归测试零退化。其余 Snapshot/XIRR 继续增量
    - **W-D4.2b 进行中**：`get_asset_allocation` 落地——schema/desc 逐字 port，纯 `shape()` 逐字 port backend `asset_allocation_snapshot::aggregate`（(asset_type,currency) 双键聚合 cost basis，weight 同币种内归一，currency asc + weight desc 排序），复用已提取的 `devicePortfolioSnapshotProvider`（零新 provider，与 `get_holdings` 同源同模式），无 read model 故无 freshness gate。registry 现 3 工具。剩余 `get_net_worth_summary`/`compute_net_worth`/`compute_xirr`/`get_xirr_summary`/breakdown(industry/geo/market_cap，需 asset 分类元数据)/cashflow → W-D4.2c
    - **W-D4.2c（2/4 进行中，最重一块）**：`get_net_worth_summary` 落地——schema/desc 逐字 port `get_net_worth_summary.rs`；纯 `shape()` 逐字 port `net_worth_snapshot::aggregate`（entry→`YYYY-MM` · 非资产 leg(`unit∉asset_ids`) signed minor 求和 · per-currency ym 升序累加 cumulative · 排序 (ym,currency)）+ `impls::get_net_worth_summary` 窗口算法（`months_back` clamp 1..60 默认 12 · `to_ym`=当前月 · `from`=months_back−1 月前 · `year_month` lexicographic 闭区间 · currency trim+upper exact）+ 输出 `{from,to,currency,series[{year_month,currency,cumulative_minor,net_flow_minor}(String)],note}` 逐字。数据源 `journalEntriesWithPostingsStreamProvider`（pre-joined → backend entry_id→ym map 折叠为单遍）+ `allAssetsStreamProvider`（asset_ids 排除资产腿）。**§4.6.1 分歧**：端侧 ledger 即真值，无 D1 read model → **无 `freshness` 字段**（同 `get_holdings`）；minor 用 `Decimal`（同 `read_account_window`，比 backend f64 精确、整分等价）。该月度净流聚合是 `compute_net_worth`/`get_cashflow_buckets` 复用的基座。**`get_cashflow_buckets` 落地**（孪生：同窗口算法 + 同 asset-leg 排除，互补地拆 inflow/outflow 分桶而非累计净；schema/desc 逐字 port `get_cashflow_buckets.rs`，纯 `shape()` 逐字 port `cashflow_buckets::aggregate`：`units==0` 跳过(对 units 非 minor) · `minor>0`→inflow 否则 outflow+=-minor 且各计笔数 · 排序 (ym,currency) · `months_back` clamp 1..24 默认 6 · series 加 `net_minor=inflow-outflow`、`inflow_count`/`outflow_count`(int)）。**§4.6.1 第二处分歧**：`source` 用 `device_ledger` 而非 backend 字面量 `read_model`（端侧无 read model，沿用 analytical 工具的 device-specific source 约定，避免谎称 read model）；`freshness` 同样去除。窗口/`_ym` 暂在两个 sibling 各自复制 ~10 行——待 `compute_net_worth` 成第三调用方时再抽 `snapshot_window` 共享层（rule-of-three）。registry 现 **19 工具**。468 ai/ai_chat/ingest 测试零回归（net_worth +6 / cashflow +7：backend `cashflow_buckets.rs` 5 个 aggregate 单测平价镜像 + §4.6.1 envelope + 窗口/币种过滤）。剩余 W-D4.2c：`compute_net_worth`(day/week 采样 + 负债 + 市值) · `compute_xirr`+`get_xirr_summary`(复用 `xirr_engine.dart`，**XIRR 数值平价 = 唯一永久漂移风险 → 必加 `*_parity_test.dart`**) · breakdown industry/geo/market_cap(需 `asset.industry`/`region`/`metadataJson`)
  - [x] ~~**桌面平台支持**（/goal 修订）~~ — `deviceLlmPlatformSupportedProvider` 改为 `!kIsWeb`（含 macOS/Windows/Linux）；§4.6.1 决策 5 + §11 修订；设置页文案 + 测试更新
  - [~] **W-D4.3** Analytical device tools（proof tool 完成）— `get_anomaly_flags` 落地：schema/desc 逐字 port；§4.3.3「端侧是唯一计算者」→ 抽 `analyticalAnomalyUpload` 共享 converter（cloud `ContextPack.analytical_uploads` 与 device 工具单一来源，不漂移），纯 `shape()` 把 upload 投影成 backend flag-row + severity_min 过滤。剩余同模式增量（W-D4.3b）
    - **W-D4.3b 进行中**：`get_recurring_patterns` 落地——schema/desc 逐字 port；抽 `recurringPatternToUpload` 共享 converter 移到 `skills/recurring_detector.dart`（与 RecurringPattern 同源，cloud `_buildAnalyticalUploads` 改调它），device 工具 detectRecurring→共享 converter→纯 `shape()` 投影 backend row + currency/cadence 过滤。`get_refund_links` + `get_transfer_links`（孪生）+ `get_investment_performance` + `get_subscription_changes`。**W-D4.3 + W-D4.3b 完成 = Analytical 层 6 工具全部端侧化**：6 个共享 converter（`analyticalAnomalyUpload`/`recurringPatternToUpload`/`refundMatchToUpload`/`transferMatchToUpload`/`holdingSnapshotToUpload`/`subscriptionChangeToUpload`）分别提到各自 detector/model 旁（`expense_anomaly_insight_provider`/`recurring_detector`/`refund_matcher`/`transfer_matcher`/`investment/data/providers`/`subscription_change_detector`），cloud `_buildAnalyticalUploads` 全改调共享 converter（端/云单一来源，无 Dart 漂移）；每工具纯 `shape()` 投影 backend row + currency/cadence/base_currency 过滤。registry 现 **9 工具**；429 ai/ai_chat/ingest 测试零回归
  - [x] ~~**W-D4.4 Scoped Detail（3/3 完成 = account/asset/category 三窗口全端侧化，见 W-D4.4b）**~~ — `scoped_window.dart` 共享层（port `common.rs`：`scopedParseIso` RFC3339|YYYY-MM-DD-pinned-UTC / `validateScopedRange` ≤31d / `parseScopedLimit` 1..50 / `scopedExcerpt` / `kScopedPurposes`）。`read_account_window` 落地：schema/desc 逐字 port，主路径（account_id × 窗口 × signed min/max × limit × 必填 purpose）忠实 port `account_window::filter_and_sanitise`，读 `journalEntriesWithPostingsStreamProvider` + `accountsStreamProvider`。**§4.6.3 两处刻意分歧**：去 HMAC → 真实 `note_excerpt`（端侧不出设备）；device `JournalEntry` 无 journal-category 轴 → `category` 恒 null，传 `category` 过滤则附 `device_note` 显式说明而非静默错（同 W-D4.2c）。registry 现 **15 工具**。剩余 read_asset_window + read_category_window → W-D4.4b。449 ai/ai_chat/ingest 测试零回归
    - **W-D4.4b（2/2 完成）**：`read_asset_window` 落地（schema/desc 逐字 port，忠实 port `asset_window::filter_and_extract`：postings.unit==asset_id × 窗口 × 非零 qty，返回 qty_delta/side/cost_per_unit/currency，天然无 merchant 脱敏；cost_per_unit = `p.cost?.perUnit ?? p.price?.perUnit`）。`read_category_window` 落地（schema/desc 逐字 port `read_category_window.rs`，忠实 port `category_window::filter_and_sanitise` 的窗口 / `merchant_substring`(原文 note 子串) / date-desc 截断 / summary(单币 `total_minor`·混币 `by_currency`) / 真实 `note_excerpt`）。**§4.6.3 定义性分歧（同 W-D4.2c 风险类）**：device `JournalEntry` 无 `payload.category` 轴 →「category 即支出账户」语义重映：必填 `category` 解析为 `AccountSide.expense` 账户（by id ‖ 大小写不敏感 equals-or-contains 名字），entry 命中 = 有 posting 落在解析出的支出账户（复用 `watchExpenses` 同一权威支出真值，非 backend「sum 正非资产腿」D1 启发式——正常支出 JE 二者等价）；`device_note` 恒附说明重映，命中 0 账户时显式说明「空 ≠ 该类目无交易」（同 `read_account_window`「显式而非静默错」）；去 HMAC → 真实 `note_excerpt`。`nameMatches` 语义内联（不耦合 propose scaffolding）。registry 现 **17 工具**。**W-D4.4 Scoped Detail 系列全部完成 = account/asset/category 三窗口全端侧化**，复用 `scoped_window.dart` 单一共享层。455 ai/ai_chat/ingest 测试零回归（+5：validation · 重映+窗口+金额+summary · 未命中→空+device_note · merchant_substring · 混币 by_currency）
  - [x] ~~**W-D5** 端侧 Vision 摄取（image → content block，用户 key 直发）~~ — `device_vision_parse.dart` 逐字 port `ingest/parse.rs`（emit 工具 schema / system prompt / `buildVisionMessages` PDF→document·其余→image / `extractVisionDraftRows` 含 200 上限 + 缺工具→`VisionNoExtraction`）；`DeviceVisionIngestClient implements CloudIngestClient` 用 `AnthropicClient.complete()` 一发 forced-tool，行映射复用**共享** `parsedTransactionFromWire`（端/云对同一模型 JSON 产出一致 `ParsedTransaction`）；`RoutingCloudIngestClient` 复用 chat 路径同一 `AnthropicClient`（单一凭证/Dio 源）按可用性选 device-or-cloud。**隐私正确分歧**：device Vision 失败**不回落我方 cloud**（用户已选「原图不经我方服务器」，静默重发会破坏该承诺）。privacy gate 不变（在 client 之前已裁决，device-direct 仍属对外 egress，只是换成用户自己的 provider、移除我方服务器）。7 tests（含 parse.rs 平价用例）；test/features/ingest+core/ai+ai_chat 共 422 测试零回归。注：ingest 非 chat turn，AiTrace 不在此路径；透明度文案归 ingest 自有 surface（后续）
  - [x] ~~**W-D6** AiTrace / 透明度页适配「端侧直连 provider」+ 降级路径测试 + 回归 corpus~~ — 透明度保真:`_prepareChatTrace` 在 device runtime 可用时把 seed `copyWith(backend: device, routingReason: 'device_llm_direct', usedCloud: false)`(`kDeviceLlmDirectRoutingReason` + `AiTrace.copyWith` 新增,local-only 无 wire 破坏);徽章 `formatAiTraceBadge` device-direct → 「端侧直连模型 · 请求与数据未经我方服务器」(区别于零模型 rules-device 的「全部本地处理」)。**§4.6.4 失效转移**:`RuntimeRoutingAiChatApiClient` 提取 `DeviceChatRunner` 接口 + buffer-until-content 逻辑——device 未产出任何 assistant 内容(provider 报错/空答/抛错)→ 静默回落 cloud;已出内容后再失败则透传不重启。**静态契约**(corpus 精神适配 device 路径):`kDeviceTools` 单一来源 + `defaultDeviceToolRegistry()`,测试断言每个 device 工具名在 `tool_descriptor.dart` 镜像可解析(§10 漂移守卫)。11 tests;test/core/ai + test/features/ai_chat 共 368 测试零回归
  - [~] **W-D4.5 propose_*（框架 + proof tool 完成）** — 解锁端侧**写**路径。`runtime/device/tools/propose/proposal_plan.dart` 逐字 port `proposals.rs` 的信封（`readyPlan`/`needsClarification`/`proposalBadRequest`）+ 引用解析（`resolveAccount` over 端侧 typed `Account` + `nameMatches` 语义）+ 类目模糊匹配（`matchExpenseCategory`/`kExpenseCategories` 闭集 + top-3 fallback）+ `isRfc3339` 严格。`propose_expense_tool.dart` schema/desc/逻辑逐字 port，返回与 cloud **逐字一致**的 `ready_plan`/`needs_clarification` JSON → W-D3 loop 的 propose 拦截 + 现有 `ProposalEnvelope`/`proposal_applier` 确认流原样消费（§4.5，端侧绝不自动写）。registry 现 **10 工具**。W-D6 静态契约改为「device 工具可为 deviceLocalWrite proposal，但绝不可 externalCall」（§4.5 真不变式）。剩余 propose_* 同 scaffolding 增量（W-D4.5b）。437 ai/ai_chat/ingest 测试零回归
  - [~] **W-D4.5b（2/4 完成）** — `propose_account_create`（纯，无 provider；`type` 闭集校验→needs_clarification）+ `propose_asset_valuation`（`resolveAsset` over `allAssetsStreamProvider`，manual-valuation 闭集 gate）。scaffolding 加 `resolveAsset`/`proposalNewId`/共享 input helpers（`proposalOptionalStr`/`proposalRequireNum`/`proposalRequireStr`/`formatProposalAmount`，propose_expense 改用）。**§10 关键取舍**：device propose_asset_valuation 用 backend `MANUAL_VALUATION_ASSET_TYPES`（含 realEstate/vehicle，命名 `kProposalManualValuationTypes`）——**故意区别于** feature 侧更严的 `kManualValuationAssetTypes`（enums.dart，不含 realEstate/vehicle），保证 device 与 cloud plan 一致而非与某 feature 一致。registry 现 **12 工具**。剩余 propose_trade + propose_liability_payment → W-D4.5c。441 ai/ai_chat/ingest 测试零回归
  - [~] **W-D4.5c（1/2 完成）** — `propose_liability_payment`：scaffolding 加 `resolveLiability`（over `liabilitiesStreamProvider`，narrow_rows 语义同 resolveAccount）；逐字 port（liability 必解析→None/Many 走 needs_clarification、from_account 可选→warn、currency=explicit??liability.currency、RFC3339 date、payload `type:liabilityPayment`）。registry 现 **13 工具**（10 读 + 4 写）。`propose_trade` 完成（逐字 port：type 闭集 / qty>0 / asset+account 必解析 → None·Many 走 needs_clarification / `currency=explicit??account.currency` / RFC3339 trade_date / `format_args_qty` 整数→「N 股」/ price·fee 省略 warn / payload 13 字段 / summary buy·sell·transferIn·transferOut·valuationAdjust 动作映射）。**W-D4.5 系列全部完成 = 5 个 propose_* 写工具全端侧化**，复用 `proposal_plan.dart` 单一 scaffolding。registry 现 **14 工具（10 读 + 4… 实为 5 写）**。446 ai/ai_chat/ingest 测试零回归
  - [ ] **W-D7（后续）** 删除 `apps/backend/src/ai/` + `/ai/chat` + guardrails；read model 表/migration 保留为历史；文档收尾
- [ ] **Phase 5 — 真实 Embedder** — 替换 `StubEmbedder` 为 MiniLM (~30MB ONNX)。`Embedder` 接口已稳定，仅换实现类。
- [ ] **VectorStore: sqlite-vec 后端** — `InMemoryVectorStore` 在 ≥5k 文档时变慢。
- [ ] **「不上云账户」feature + PrivacyGate UI** — 配合此 feature 上线时再做 disclosure consent UI；否则 ScopedDisclosure 仅做 freshness gate 即可。
- [ ] **Disclosure session 缓存** — 用户授权 "本会话允许 drill-down 餐饮" 应缓存避免每次弹窗。
- [ ] **Schema-as-source codegen** — JSON Schema 生成 Dart freezed + Rust serde（`packages/ai_contracts/`）。等 Phase 5 设计锁定后启动。

### 非本架构引入但相关

- 9 个 `test/features/ai_chat/tool_invocation_renderers_test.dart` 测试在 HEAD 即失败（与本架构无关，已在 stash 验证）。
- `apps/backend/src/routes/ai.rs:178` 的 `cargo fmt` 差异同样在 HEAD 即存在。

## 10. Contract Drift Prevention

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

## 11. 关键设计取舍（非显然的决定）

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
- **端侧 LLM 必须 opt-in** — 200MB 级别下载不应阻塞首屏；用户自带 key 路径同样 opt-in（未填 key 不改变现状）。
- **为什么用户自带 key 解除了「端侧直连」的一票否决项**（§4.6）— 原阻碍是「把我方 key 打进二进制 = 盗用 + 计费无上限 + 无法限流」。key 改为用户自己的 provider 账户后，计费与限流由用户账户承担，我方不再是被滥用对象，guardrails 也无需在不可信客户端强制。
- **为什么 device runtime 路径上 freshness gate / ScopedDisclosure 整体消失**（§4.6）— 这两条通道存在的前提是「云端推理需要绕回端侧拿最新真值 / 原始 ledger 不能出设备」。当推理本身就在端侧、直接读 Drift 真源时，既无 stale 也无「出设备」边界，兜底通道在该路径上无意义（cloud relay 路径仍保留它们直到删除）。
- **为什么 Scoped Detail 端侧不再 HMAC 脱敏**（§4.6）— `merchant_hashed` 的唯一目的是「原始字段不出设备到云」。端侧推理明细本就不出设备，脱敏只剩 token/可读性负担；保留 `purpose` 必填 + 写 AiTrace 即可维持同等透明度。
- **为什么 Vision 端侧直发比 Worker 中转更私密**（对比 §11 末条「云端 Vision 无状态零留存」）— 那条的边界是「Worker in-request 处理后即弃」，仍有原图短暂经我方服务器。用户自带 key 直发 provider 后原图根本不到我方服务器，是更强而非更弱的隐私边界。
- **为什么 web 仍走 cloud relay，而桌面与移动一视同仁**（§4.6.1，决策修订）— 浏览器无系统级安全存储（key 只能落 IndexedDB/localStorage），且 Anthropic 浏览器直连需 dangerous header 并把 key 暴露在 JS 内存。**所有原生平台（含 macOS/Windows/Linux）都有系统密钥库 + 原生 HTTP**，与移动端安全前提完全一致，没有理由把桌面排除在端侧 agent 之外；真正的边界是「web vs 原生」而非「移动 vs 桌面」。门控收敛为单一 `!kIsWeb`。原「仅 iOS/Android」是 Phase 5 初版的保守范围，已按需求修订。
- **为什么先并存再删 cloud AI**（§4.6 / §8 / §9 W-D7）— 140 backend tests + 已验证的 read model 主通道是资产；`AiRuntime` registry 让端云并存零成本，端侧路径生产验证稳定后再单独 Wave 做不可逆删除，降低回归风险。
- **为什么 device tool 的 allow-list 是「registry 成员」而非 `allowed_runtimes` 字段**（§4.6.3 / W-D4）— backend `tool_policy.rs` 所有描述符当前是 `CLOUD_ONLY`，mobile 镜像 `tool_descriptor.dart` 也默认 cloud-only。把 `allowed_runtimes` 当 device gate 需要么改 backend（冻结至 W-D7）、么批量改 wire 镜像（§10 漂移风险）。改用「只有注册了 Drift 实现的工具才可被 device 调用」——「没有实现」比「元数据标志」是更强的保证，且零 backend 改动。`allowed_runtimes` 与 backend 的对账并入 W-D7（删 cloud 时一并 flip）。dispatcher 仍按 §4.5 拒绝 `external_call` 副作用作纵深防御。
- **为什么端侧 agent 全 Dart 而非复用 Rust（FFI）**（§4.6）— 复用 Rust 的标准理由是「两份实现永久同步」，但 W-D7 删 cloud 后只剩端侧一份，dual-impl 只是 W-D1~W-D6 共存窗口的临时成本，会自然蒸发。换 FFI 的代价（backend crate 拆 runtime-无关 core / 从零搭 cargo-ndk + iOS xcframework + FRB / Drift 数据只能回调进 Dart 故 tool 取数仍是 Dart）是永久负债。唯一永久漂移风险是数值算法（XIRR Newton-Raphson 等），用 `test/core/ai/.../*_parity_test.dart` roundtrip 对齐 backend 直到 W-D7 删除即可，不值得为此引入 FFI 工具链。
- **NL→QueryPlan 不直接写 SQL** — sealed plan + Drift query builder。新增意图必须改类型，不会「忘了」。
- **Privacy Policy 永久优先于 Source** — 任何 high-risk proposal 不论端侧/云端生成都走同一确认 UI；隐私设置不论 runtime 都执行。
- **为什么摄取草稿用独立本地表而非「待审 OpLog 行」**（§5.10.10）— OpLog 是同步真值，塞入未确认草稿会污染所有设备并绕过确认门；独立本地表让 §4.2 draft gate 自然成立，确认后才经 `proposal_applier` 进 OpLog。
- **为什么去重对账跑 Drift 而非 read model**（§5.10.10）— 用户常「手动记一笔 + 账单又来一笔」，刚录入的还没投影到 read model，只有 Drift 真源能正确判重；这与 §4.2 freshness gate 同源（端侧才有最新真值）。
- **为什么云端 Vision 解析无状态零留存**（§5.10.10）— 截图/账单是最敏感的原始数据，Vision 必须看图像内容（无法脱敏），唯一可接受的边界是 Worker in-request 处理后即弃 + AiTrace 明示「已上云解析（未留存）」。

## 12. 引用 / 入口表

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
