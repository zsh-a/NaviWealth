# NaviWealth Income Planner（期权现金流机会引擎）

> 文档版本：2026-05-21
> 关联：[`docs/ai-architecture.md`](./ai-architecture.md)、[`docs/ai-protocol.md`](./ai-protocol.md)、[`docs/roadmap-fire-os.md`](./roadmap-fire-os.md)、[`docs/market-data-providers.md`](./market-data-providers.md)、[`docs/sync-protocol.md`](./sync-protocol.md)
> 定位：在 NaviWealth 已有的"持仓 + 现金 + FIRE 现金桶 + 风险偏好"之上，新增一个**低频期权现金流规划器**。
>
> 状态（2026-05-21）：设计阶段。MVP 行情源锁定 yfinance；AI tool **只读 cache**，不触发实时扫描。

---

## 0. 一句话目标

Income Planner **不是**期权扫描终端，也**不是**最高 premium 排行榜。

它持续回答一个问题：

> 在我已有资产、可用现金、风险偏好和市场环境下，**当前有没有风险可承受、收益合理、流动性足够、可解释**的 sell put / covered call 机会？

产出不是"买这个"，而是：

```text
这是不是一个适合"我"的机会？
为什么？
坏情况是什么？
占用多少现金/股票？
是否符合我的资产配置上限？
```

---

## 1. 产品边界

### 1.1 做什么（MVP–P4）

- **Covered Call 扫描**：基于用户已持仓（≥100 股）找出合适的卖 call 机会。
- **Cash-secured Put 扫描**：基于"用户愿意以这个价格长期持有"的标的清单找出卖 put 机会。
- **风险与适配性评估**：硬过滤（流动性、DTE、事件窗口）+ 软评分（收益 / 流动性 / 安全边际 / IV / 组合契合 / 事件安全）。
- **结构化解释**：每个机会输出 `whyGood` / `whyRisky` / `bestFor` / `avoidIf` 字段，**由评分引擎生成**，不由 LLM 重算。
- **交易日志（Trade Journal）**：用户成交后写入复盘记录，跟踪真实策略收益。
- **AI 解释层**：在 ai_chat 里通过 read-only tool 让 LLM 帮用户读懂某个机会。

### 1.2 不做什么

第一阶段明确不做：

- **不下单**。不接券商交易 API，不发出实盘订单。下单是 `SideEffect.externalCall`，是独立战役（远期）。
- **不预测价格**。不预测 underlying 涨跌方向，不预测 IV 走势。
- **不全市场扫描**。只扫用户已持仓 + "愿意持有清单" + 系统默认优质池（QQQ/SPY/VTI/SCHD/AAPL/MSFT/NVDA/GOOGL 等）。
- **不做单一指标排行榜**（不按年化降序）。必须同时满足流动性 + 风险边界 + 组合契合。
- **不向不愿持有的标的卖 put**（硬约束）。
- **不向不愿卖出的持仓卖 covered call**（硬约束）。
- **不让 AI 触发实时扫描**。AI tool **只读** scan cache（详见 §8）。
- **不在 web 构建出现**。Income Planner 仅 iOS / Android（与 AI device-only 一致，见 [`docs/ai-architecture.md`](./ai-architecture.md) §1）。

### 1.3 产品原则

| 原则 | 含义 |
|------|------|
| Local-first | 行情拉取、normalize、评分、cache 全部在端侧。Backend 在 P5 之前**不出现一行代码**。 |
| 显性持有意愿 | sell put / covered call 都要求标的进入"approved underlyings"清单。LLM 不能绕过。 |
| 解释结构化 | 评分引擎产 `OpportunityExplanation` 结构体；UI 与 AI 共享同一份解释，杜绝双源。 |
| 最坏情况优先 | 卡片必须显示"被行权后会发生什么"；不只是收益数字。 |
| AI 只读 cache | LLM 不能让扫描重跑，只能读最近一次扫描结果；保证可解释性 + 控本。 |
| Decimal-only | premium / strike / cash_required / pnl 全部 `Decimal` + `Money`。禁止 `double`。 |
| 渐进增强 | MVP 走 yfinance 非官方端点；接 OAuth 数据源（Tradier/Schwab）放到 P5。 |

---

## 2. 架构承接点

### 2.1 硬性约束（来自现有架构）

| 约束 | 来源 | 对设计的影响 |
|---|---|---|
| AI 完全设备端，无 `/ai/chat` 中继 | [`ai-architecture.md`](./ai-architecture.md) §4.6（W-D7） | 评分 + tool 实现全部 Dart。Backend 不解析期权语义。 |
| Backend 只做 OpLog 透传 | [`sync-protocol.md`](./sync-protocol.md) v1.0 frozen | 派生数据（opportunity cache）**不上同步**；用户状态（profile / approved / journal）走 OpLog。 |
| Read Model 三层 | `lib/core/ai/contracts/tool_descriptor.dart` | profile = `snapshot`，opportunity = `analytical`，single chain = `scopedDetail`。 |
| Money 类型 | CLAUDE.md「Money」 | 所有期权金额走 `Money` + `Decimal`。 |
| Web 无 AI | CLAUDE.md「AI」 | Income Planner 通过 `kIsWeb` 短路；`web_smoke` 反向断言不出现期权文案。 |
| Modal 系统 | memory: modal_system | 详情面板用 `showAppFormSheet` + `AppSheetFooter`；CI 由 `tool/check-modal-helpers.sh` 守护。 |
| Forui + design tokens | `apps/mobile/lib/design_system/` | `FCard` / `FButton` + `AppSpacing` / `AppRadius`，不写魔法数字。 |

### 2.2 不会被打破的现有原则

- 不重蹈 W-D7 的覆辙：**评分逻辑不上 Worker**。P5 接 OAuth 行情源时，Worker 角色严格限制为"凭证持有 + HTTP 透传"，禁止任何 normalize / score / cache。
- 不破坏 [`market-data-providers.md`](./market-data-providers.md) 的 valuation / metadata 双路径：`OptionsChainProvider` 是**第三条**路径——"low-frequency user-initiated scan"，单独定义 cache 与 rate limit 策略。
- 不污染 FIRE engine：期权产生的现金流通过既有 `cashflow_buckets` 接入 FIRE，FIRE engine 不感知期权语义。

---

## 3. 数据流总览

```text
                ┌──────────────────────────────────────────────┐
                │  User Inputs (Drift, synced via OpLog)       │
                │   • OptionsStrategyProfile                    │
                │   • ApprovedUnderlyings                       │
                │   • Portfolio holdings + cash (existing)      │
                └─────────────────┬────────────────────────────┘
                                  │
                  ┌───────────────▼───────────────┐
                  │ Tradable Universe Builder      │
                  │  (Dart, pure function)         │
                  └───────────────┬───────────────┘
                                  │
            ┌─────────────────────▼─────────────────────┐
            │ OptionsChainProvider (lib/data/market/)    │
            │  • yfinance_options_provider (MVP)         │
            │  • shares MarketHttpClient + RateLimiter   │
            └─────────────────────┬─────────────────────┘
                                  │
                  ┌───────────────▼───────────────┐
                  │ Normalizer                     │
                  │  → NormalizedOptionContract    │
                  └───────────────┬───────────────┘
                                  │
                  ┌───────────────▼───────────────┐
                  │ OpportunityScorer (pure Dart)  │
                  │  hard filters → soft score     │
                  │  + OpportunityExplanation      │
                  └───────────────┬───────────────┘
                                  │
                  ┌───────────────▼───────────────┐
                  │ OptionsOpportunityCacheTable   │
                  │  (Drift, LOCAL ONLY, no sync)  │
                  └─────┬──────────────────┬──────┘
                        │                  │
                ┌───────▼──────┐   ┌──────▼─────────────────────┐
                │ UI cards     │   │ AI tool                    │
                │ (Forui)      │   │ get_options_income_         │
                │              │   │ opportunities (READ CACHE) │
                └──────────────┘   └────────────────────────────┘
```

**关键点**：UI 与 AI tool 读同一张 cache 表，所以两边永远看见相同的解释字段。AI tool 不能旁路评分引擎自己算分。

---

## 4. 行情源决策

### 4.1 MVP：yfinance 非官方端点

复用 `lib/data/market/providers/yfinance_provider.dart` 同款 `MarketHttpClient` + `RateLimiter`，新增 `lib/data/market/providers/options/yfinance_options_provider.dart`。

**配额策略**：

- yfinance 现有 `MarketHttpClient` 限流为 60 req/min，由 quote 路径占用。
- 期权 chain 接口**复用同一 RateLimiter 实例**——一个 underlying 同时刷 quote + chain 不能把限额打爆。
- 在 `OptionsChainProvider` 侧加 **per-symbol 二级节流**：单一 underlying 同一 expiration 的 chain 在 5 分钟内只拉一次。

**TOS 约束**（继承 [`market-data-providers.md`](./market-data-providers.md)）：

- yfinance 禁商业再分发。期权 chain 数据**只在端侧**消费，**不写进**任何同步表，**不发送**到 backend。
- 失败时不阻塞 UI：返回上一次 cache + freshness badge（沿用现有 `DataFreshness` 机制）。
- 期权扫描**必须用户手势触发**——不挂任何后台定时任务，不挂任何 render 路径。这是和 `searchSymbol` 同级的约束。

### 4.2 后续路线

| Phase | 数据源 | 触发 | 备注 |
|---|---|---|---|
| P1–P4 | yfinance | 用户点 "刷新机会" | 当前文档范围 |
| P5 | Tradier sandbox | 同上 | 第一个有正式 greeks 的源；OAuth 必须，需要 backend 透传 |
| P6+ | Schwab Trader API | 同上 | 需要 backend 透传 + 用户级 OAuth；评估再决定是否做 |

**P5 backend proxy 规则**（提前在此锚定，防止漂移）：

- 路由位于 `apps/backend/src/routes/market/options.rs`。
- 只接 `symbol` + `params`，**拒绝任何评分参数**。
- 不 normalize、不 cache、不打分。错误回 `AppError`。
- 凭证仅保存在 backend（OAuth refresh token），客户端只持短期 access token 或纯通过 backend 透传。

---

## 5. 领域层

位置：`apps/mobile/lib/features/options_income/domain/`。

### 5.1 实体

```dart
@freezed
class OptionContract with _$OptionContract {
  const factory OptionContract({
    required String underlying,
    required String optionSymbol,
    required OptionType type,            // call | put
    required DateTime expiration,
    required int dte,
    required Money strike,
    required Money bid,
    required Money ask,
    required Money mid,
    required int volume,
    required int openInterest,
    Decimal? impliedVolatility,
    OptionGreeks? greeks,
    required Money underlyingPrice,
    required Decimal bidAskSpreadPct,
  }) = _OptionContract;
}

@freezed
class OptionsOpportunity with _$OptionsOpportunity {
  const factory OptionsOpportunity({
    required OptionsStrategy strategy,    // cashSecuredPut | coveredCall
    required OptionContract contract,
    required OpportunityMetrics metrics,
    required OpportunityRisk risk,
    required OpportunitySuitability suitability,
    required OpportunityExplanation explanation,
    required Decimal score,
    required DateTime scannedAt,
  }) = _OptionsOpportunity;
}

@freezed
class OptionsStrategyProfile with _$OptionsStrategyProfile {
  const factory OptionsStrategyProfile({
    required StrategyMode mode,           // conservative | balanced | aggressive
    required Set<OptionsStrategy> allowedStrategies,
    required IntRange targetDteRange,
    required DecimalRange targetDeltaPut,    // e.g. [-0.30, -0.15]
    required DecimalRange targetDeltaCall,   // e.g. [0.15, 0.30]
    required Decimal maxCapitalPerTradePct,
    required Decimal maxUnderlyingExposurePct,
    required Decimal minAnnualizedYield,
    required int minOpenInterest,
    required int minVolume,
    required Decimal maxBidAskSpreadPct,
    required bool avoidEarnings,
    required bool avoidMacroEvents,
    required bool onlyOnApprovedUnderlyings,
    DateTime? riskDisclosureAckAt,        // OCC ODD acknowledgement
  }) = _OptionsStrategyProfile;
}
```

### 5.2 值对象

`OpportunityExplanation` 是 UI 与 AI 共享的解释结构：

```dart
@freezed
class OpportunityExplanation with _$OpportunityExplanation {
  const factory OpportunityExplanation({
    required String summary,
    required List<String> whyGood,
    required List<String> whyRisky,
    required String bestFor,
    required String avoidIf,
    required Map<String, Decimal> scoreBreakdown,  // {yield: 0.84, liquidity: 0.71, ...}
  }) = _OpportunityExplanation;
}
```

### 5.3 类型边界

- `Money` 不允许跨币种相加（已有）。`cashRequired = strike * 100` 走 `Money.scale(int)`，**不是** `Money + Money`。
- `Decimal` 用于 delta / IV / 百分比 / 评分。
- `IntRange` / `DecimalRange` 在 `lib/domain/values/` 已有或新增。

---

## 6. 数据层

### 6.1 同步策略（与 OpLog 边界）

| 表 | 同步 | 理由 |
|---|---|---|
| `options_strategy_profile` | ✅ OpLog | 用户偏好，跨设备一致 |
| `options_approved_underlyings` | ✅ OpLog | 用户清单，跨设备一致 |
| `options_trade_journal` | ✅ OpLog | 真实复盘，需要历史 |
| `options_opportunity_cache` | ❌ 本地 | 派生数据，重算成本低；跨设备各自扫描 |

**OpLog op 类型**（client 自定义，backend 不解析语义）：

```
options_profile.upsert
options_approved.upsert
options_approved.delete
options_journal.insert
options_journal.update
options_journal.close
```

### 6.2 Drift 表落点

加到 `apps/mobile/lib/data/db/tables.dart`（同步表）：

```dart
class OptionsStrategyProfileTable extends Table {
  TextColumn get userId => text()();
  TextColumn get mode => text()();                    // conservative | balanced | aggressive
  IntColumn get minDte => integer()();
  IntColumn get maxDte => integer()();
  TextColumn get deltaPutMin => text().map(decimalConverter)();
  TextColumn get deltaPutMax => text().map(decimalConverter)();
  TextColumn get deltaCallMin => text().map(decimalConverter)();
  TextColumn get deltaCallMax => text().map(decimalConverter)();
  TextColumn get maxCapitalPerTradePct => text().map(decimalConverter)();
  TextColumn get maxUnderlyingExposurePct => text().map(decimalConverter)();
  TextColumn get minAnnualizedYield => text().map(decimalConverter)();
  IntColumn get minOpenInterest => integer()();
  IntColumn get minVolume => integer()();
  TextColumn get maxBidAskSpreadPct => text().map(decimalConverter)();
  BoolColumn get avoidEarnings => boolean()();
  BoolColumn get avoidMacroEvents => boolean()();
  BoolColumn get onlyOnApprovedUnderlyings => boolean()();
  DateTimeColumn get riskDisclosureAckAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId};
}

class OptionsApprovedUnderlyingsTable extends Table {
  TextColumn get userId => text()();
  TextColumn get symbol => text()();
  BoolColumn get allowPut => boolean()();
  BoolColumn get allowCall => boolean()();
  TextColumn get maxBuyPrice => text().nullable().map(decimalConverter)();
  TextColumn get minSellPrice => text().nullable().map(decimalConverter)();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, symbol};
}

class OptionsTradeJournalTable extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get strategy => text()();
  TextColumn get symbol => text()();
  TextColumn get optionSymbol => text()();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get entryCredit => text().map(decimalConverter)();
  TextColumn get exitDebit => text().nullable().map(decimalConverter)();
  TextColumn get realizedPnl => text().nullable().map(decimalConverter)();
  TextColumn get status => text()();              // open | closed | assigned | expired
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

加到本地非同步表区域（新建 `apps/mobile/lib/data/db/local_only_tables.dart`，与 `event_log_tables.dart` 并列）：

```dart
class OptionsOpportunityCacheTable extends Table {
  TextColumn get scanId => text()();              // 一次扫描批次
  TextColumn get optionSymbol => text()();
  TextColumn get underlying => text()();
  TextColumn get strategy => text()();
  DateTimeColumn get expiration => dateTime()();
  TextColumn get strike => text().map(decimalConverter)();
  IntColumn get dte => integer()();
  TextColumn get delta => text().nullable().map(decimalConverter)();
  TextColumn get bid => text().map(decimalConverter)();
  TextColumn get ask => text().map(decimalConverter)();
  TextColumn get mid => text().map(decimalConverter)();
  TextColumn get iv => text().nullable().map(decimalConverter)();
  IntColumn get volume => integer()();
  IntColumn get openInterest => integer()();
  TextColumn get annualizedYield => text().map(decimalConverter)();
  TextColumn get breakeven => text().map(decimalConverter)();
  TextColumn get score => text().map(decimalConverter)();
  TextColumn get riskLevel => text()();
  TextColumn get explanationJson => text()();     // OpportunityExplanation 序列化
  DateTimeColumn get scannedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {scanId, optionSymbol};
}
```

cache 表有 TTL：单批保留 24 小时，新批扫描时清除超过 1 周的旧批。

---

## 7. 评分引擎

位置：`apps/mobile/lib/features/options_income/domain/services/opportunity_scorer.dart`。
形态参考 FIRE engine（`lib/features/fire/domain/`）——**纯函数、无 IO、可重放**。

### 7.1 硬过滤（Hard Filters）

任一条命中直接淘汰，理由写进 `OpportunityScore.rejected.reasons`：

```text
bid <= 0
openInterest < profile.minOpenInterest
volume < profile.minVolume
bidAskSpreadPct > profile.maxBidAskSpreadPct
dte < profile.targetDteRange.min OR dte > profile.targetDteRange.max
delta 缺失且无法估算
strategy == put AND symbol NOT IN approvedUnderlyings WHERE allow_put
strategy == call AND user_holdings[symbol] < 100
strategy == put AND cashRequired > availableCash * profile.maxCapitalPerTradePct
profile.avoidEarnings AND earningsWithinDays(symbol, 7)
profile.avoidMacroEvents AND macroEventWithinDays(7)   // CPI / FOMC
```

### 7.2 软评分（Soft Score）

```text
final_score =
    0.25 * yield_score
  + 0.20 * liquidity_score
  + 0.20 * safety_margin_score
  + 0.15 * iv_score
  + 0.10 * portfolio_fit_score
  + 0.10 * event_safety_score
```

权重通过 `Provider<ScoringWeights>` 注入；测试可 override；高级用户后续可调。

每个子分数都在 `OpportunityExplanation.scoreBreakdown` 里暴露，便于：

- UI 显示"为什么这个得分这样"
- AI tool 让 LLM 引用具体维度生成自然语言解释
- 单元测试针对每个维度单独断言

### 7.3 解释生成

`OpportunityExplanation` 由评分引擎在 score 完成后**直接产出**，模板化短句拼装：

- `whyGood`：从 score breakdown 排前 3 维度倒推（"流动性好：bid-ask spread 1.2%"）。
- `whyRisky`：从 hard filters 接近边界的项 + soft score 倒数 2 维度。
- `bestFor` / `avoidIf`：基于 strategy + profile.mode 的固定模板。

**LLM 不重写这些字段**，只可以基于它们做更自然语言的复述。

---

## 8. AI 集成（read-cache-only 决策）

### 8.1 决策记录

> **AI tool 只读 cache，不触发实时扫描。**
>
> 理由：
> 1. yfinance 是非官方端点；让 LLM 触发拉取会让限流不可预测，且违背 [`market-data-providers.md`](./market-data-providers.md) 的"用户手势触发"原则。
> 2. 实时扫描会让 tool latency 不可控，影响 ai_chat 体验。
> 3. UI 与 AI 读同一份 cache → 解释一致性，避免双源 drift。
> 4. 控本：LLM 不可能让用户在没意识到的情况下打高频请求。

### 8.2 Tool 注册

加到 `lib/core/ai/contracts/tool_descriptor.dart` 的 `allToolDescriptors`：

```dart
ToolDescriptor(
  name: 'get_options_income_opportunities',
  access: Access.read,
  risk: RiskLevel.suggest,
  requiresConfirmation: Confirmation.none,
  allowedContextTier: BudgetTier.standard,
  readModelLayer: ReadModelLayer.analytical,
),
ToolDescriptor(
  name: 'get_options_strategy_profile',
  access: Access.read,
  risk: RiskLevel.info,
  requiresConfirmation: Confirmation.none,
  allowedContextTier: BudgetTier.small,
  readModelLayer: ReadModelLayer.snapshot,
),
ToolDescriptor(
  name: 'propose_options_profile_update',
  access: Access.propose,
  risk: RiskLevel.propose,
  requiresConfirmation: Confirmation.oneTap,
  allowedContextTier: BudgetTier.standard,
  sideEffect: SideEffect.deviceLocalWrite,
),
ToolDescriptor(
  name: 'propose_options_journal_entry',
  access: Access.propose,
  risk: RiskLevel.propose,
  requiresConfirmation: Confirmation.oneTap,
  allowedContextTier: BudgetTier.standard,
  sideEffect: SideEffect.deviceLocalWrite,
),
```

**故意不加**：`propose_options_trade`（下单是 `SideEffect.externalCall`，不在本设计范围）。

### 8.3 Tool 实现

文件落点 `lib/core/ai/runtime/device/tools/`：

```
get_options_income_opportunities_tool.dart
get_options_strategy_profile_tool.dart
propose/
  propose_options_profile_update_tool.dart
  propose_options_journal_entry_tool.dart
```

`get_options_income_opportunities` 的合约：

```
Input:
  - strategy?: "cash_secured_put" | "covered_call" | null  (null = both)
  - max_results?: int = 5
  - min_score?: Decimal = 0.6

Behavior:
  - 读 OptionsOpportunityCacheTable 最新一批
  - 不触发扫描；不调用任何 OptionsChainProvider
  - 若 cache 为空或最近扫描 > 24h，返回 stale 标志 + 引导用户在 UI 手动刷新
  - 不重写 OpportunityExplanation 字段

Output:
  - opportunities: List<OptionsOpportunity>（结构化）
  - cache_state: { last_scanned_at, is_stale, scan_id }
  - guidance: "若需要最新数据，请在 Income Planner 页面手动刷新" (when stale)
```

### 8.4 LLM 在 ai_chat 里的合理用法

用户可以问的事：

```text
"这次扫描里风险最低的两个机会是什么？"
"AAPL 那个 sell put 我为什么应该考虑？为什么应该犹豫？"
"如果 AAPL 跌到行权价我会发生什么？"
"这次扫描和上次相比，覆盖标的变了吗？"
```

LLM **不能**做的事（dispatcher 层不强制，但 system prompt 提示）：

- 不能宣称"现在的市场价是 X"——它只有 cache 里那个时刻的快照。
- 不能让用户"现在就下单"——没有 trade tool。
- 不能改 explanation 的 `whyGood/whyRisky` 字段，只能引用 + 复述。

---

## 9. UI 落点

### 9.1 入口

主页面：`apps/mobile/lib/features/options_income/presentation/pages/income_planner_page.dart`，命名 **Income Planner / 期权现金流规划**。

页内四 tab：

```text
Conservative Income      保守现金流机会
Higher Yield             高收益高风险机会
Portfolio Repair         降低持仓成本机会
Watchlist Opportunities  关注标的机会
```

每张卡片：

- 外层 `FCard`，padding `AppSpacing.lg`。
- 顶部 chip：strategy 类型 + risk 等级，颜色映射 design tokens 的 semantic role。
- 中部数字栏：年化、占用资金、盈亏平衡，走 `core/format/MoneyFormatter` + `PercentFormatter`。
- 底部："Why good" / "Why risky" 双列，最多各 3 条，直接读 `OpportunityExplanation`。
- CTA："了解详情" → `showAppFormSheet(opportunityDetailSheet)`，**必须**走统一 modal helper（CI 守护）。

### 9.2 偏好设置

`profile_settings_sheet.dart`（`showAppFormSheet`）：

- StrategyMode 三选一（conservative / balanced / aggressive）—— 预填 delta / DTE / 收益阈值。
- ApprovedUnderlyings 列表：增删 + 单个标的的 `allowPut` / `allowCall` / `maxBuyPrice` / `minSellPrice`。
- 首次进入强制弹"期权风险披露"（基于 OCC ODD），用户确认后写入 `riskDisclosureAckAt`。

### 9.3 web 行为

```dart
if (kIsWeb) return const SizedBox.shrink();
```

入口在 web 构建中不显示。`web_smoke` 加一条反向断言："web build 不应出现 'Income Planner' 字样"。

---

## 10. 与现有 feature 的耦合

| 耦合方 | 交互方式 |
|---|---|
| `features/investment` | `ExposureChecker` 读 holdings snapshot：covered call 要求 ≥100 股；cash-secured put 行权后单标的暴露 ≤ profile 上限。 |
| `features/accounts` + `cashflow` | 计算 `availableCashForOptions = cashAccounts - kCashReserveBuffer`，与 FIRE 现金桶规则相容。 |
| `features/rebalance` | **软约束**：covered call strike 高于 rebalance target sell price → 加分；sell put strike 低于 target buy price → 加分。**不阻塞** rebalance 计算。 |
| `features/fire` | 期权 premium 入账后通过 `cashflow_buckets` 体现为 "options income"。FIRE engine 不感知期权语义。 |
| `features/activity` | `OptionsTradeJournalTable` 写入触发 domain event log，进 activity timeline。 |
| `features/ai_chat` | 通过 §8 注册的 tool 读 cache。无新 chat 入口。 |

---

## 11. 风险与硬约束

### 11.1 必须显示的最坏情况

| 策略 | 最坏情况文案（必须出现） |
|---|---|
| Cash-secured Put | "如果 {symbol} 跌破 ${strike}，你将以 ${breakeven} 实际成本买入 100 股，占用现金 ${cashRequired}。" |
| Covered Call | "如果 {symbol} 涨到 ${strike}，你将以 ${strike} 卖出 100 股，错过该价位以上的全部上涨。最大总收益锁定为 ${strikePlusPremium}。" |

### 11.2 OCC 风险披露

首次进入 Income Planner 强制读 OCC ODD 摘要，用户必须显式确认才能写入 `riskDisclosureAckAt`。沿用 `core/auth` 的"首次同意"模式。

### 11.3 不可在文案中出现

- "稳定收益" / "稳赚" / "保底"
- "推荐你买" / "我建议你做"（AI 输出也不行）
- 任何形如"概率 X%"的精确预测（除非来自 `abs(delta)` 这个明确口径，且必须标注是 delta 近似）

---

## 12. 落地路线

| Phase | 范围 | 行情源 | Backend 改动 |
|---|---|---|---|
| **P0** | Profile + Approved List + OCC 披露 + Drift 表 + OpLog op | — | ❌ 无（client 自定义 op 类型，server 透传） |
| **P1** | Covered Call Scanner（yfinance）+ `OpportunityScorer`（call 路径）+ income_planner_page tab 1 + `get_options_income_opportunities` tool | yfinance | ❌ |
| **P2** | Cash-secured Put Scanner + sell put 路径 + cash 暴露检查 | yfinance | ❌ |
| **P3** | Trade Journal + `propose_options_journal_entry` tool + activity 接入 | — | ❌ |
| **P4** | Wheel / Income Cycle 状态机 + 复盘视图 | yfinance | ❌ |
| **P5** | Tradier sandbox 接入 | Tradier (OAuth) | ✅ 新增 `routes/market/options.rs` 透传 |

P0–P4 backend 不动一行代码。本设计文档的有效范围到 P4 结束。P5 接 OAuth 行情源时需另起一份 ADR 说明 backend 透传契约。

---

## 13. 不做清单（防漂移锚点）

- ❌ 不做"全市场期权扫描"。
- ❌ 不做"按年化降序排行榜"。
- ❌ 不做"自动卷动 (auto-wheel)"。
- ❌ 不把评分 / 排名 / 候选生成放在 Worker。
- ❌ 不让 AI tool 触发实时扫描。
- ❌ 不在 web 构建出现 Income Planner 入口。
- ❌ 不绕过 `OptionsApprovedUnderlyings` 给"陌生标的"打分。
- ❌ 不引入新的 chat 入口或新的 AI runtime——所有 LLM 调用走现有 `DeviceAgentLoop`。
- ❌ MVP 不接券商交易 API；不存在 `propose_options_trade` 工具。

---

## 14. 决策记录（ADR-lite）

| 日期 | 决策 | 备选 | 选择理由 |
|---|---|---|---|
| 2026-05-21 | MVP 行情源 = yfinance | Tradier sandbox / Polygon | 零成本、复用现有 `MarketHttpClient`；TOS 约束已被 [`market-data-providers.md`](./market-data-providers.md) 锚定 |
| 2026-05-21 | AI tool 只读 cache | tool 可触发扫描 | 控本 + 解释一致性 + 限流可预测；详见 §8.1 |
| 2026-05-21 | 评分引擎在端侧（纯 Dart） | 在 Worker 上 | 与 W-D7 device-only 原则一致；评分逻辑不下放 server |
| 2026-05-21 | opportunity cache 不上同步 | 走 OpLog | 派生数据，重算成本低；跨设备各自扫描更新鲜 |
| 2026-05-21 | profile / approved / journal 走 OpLog | 仅本地 | 用户状态，跨设备一致性必要 |
| 2026-05-21 | 模块为独立 feature `options_income/` | 塞进 `investment/` | 跨 investment / accounts / fire / rebalance，独立 feature 避免双向依赖 |
| 2026-05-21 | 命名 "Income Planner" | "Options Scanner" | 避免被识别成交易终端；与 NaviWealth 财富管理定位一致 |

---

## 15. 相关代码路径（实施时填充）

```
apps/mobile/lib/features/options_income/        # 新建 feature
apps/mobile/lib/data/market/providers/options/  # OptionsChainProvider 实现
apps/mobile/lib/data/db/tables.dart             # 三张同步表
apps/mobile/lib/data/db/local_only_tables.dart  # cache 表（新建文件）
apps/mobile/lib/core/ai/contracts/tool_descriptor.dart   # tool 描述符
apps/mobile/lib/core/ai/runtime/device/tools/   # tool 实现
apps/backend/src/routes/market/options.rs       # 仅 P5+，透传代理
```
