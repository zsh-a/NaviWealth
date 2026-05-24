# NaviWealth 开发计划（v0.5.x → v0.7.x）

> 本文档是**当前唯一的开发计划入口**。它的作用域被
> [`lifeos-architecture-northstar.md`](./lifeos-architecture-northstar.md) 严格约束:
> **只规划 FinanceOS(NaviWealth 当前唯一存在的域)**,不包含任何 HealthOS / TimeOS /
> LivingOS 的阶段化计划——这类规划由北极星 §1.8 明确禁止,触发条件见 §6。
>
> 各执行轨道的**任务级细节**仍在原 detail 文档里;本文档只做**统一调度 + 优先级 + 触发条件 + 反目标**。
>
> 与既有 detail 文档的关系:
> - 短期任务细节 → [`roadmap-phase1.md`](./roadmap-phase1.md)
> - 中期任务细节 → [`roadmap-midterm-execution.md`](./roadmap-midterm-execution.md)
> - FIRE OS 引擎 → [`roadmap-fire-os.md`](./roadmap-fire-os.md)
> - Options Income → [`options-income.md`](./options-income.md)
> - AI 运行时设计 → [`ai-architecture.md`](./ai-architecture.md)
> - 旧的 [`roadmap.md`](./roadmap.md) 内容被本文档统一调度,作为历史参考保留。

---

## 0. 约束(读懂这里再排期)

1. **作用域**:FinanceOS 域路线(本文档)+ Phase D 状态指针(§10,详见 `lifeos-shell.md`)。HealthOS 域 SSOT 在 `healthos-domain.md`,**不重复**。TimeOS / KnowledgeOS / LivingOS 未触发,本文档不规划。
2. **IA 锁定**:Today / Activity / Wealth / Plan + 全局 Settings + Search 已锁定。任何新功能必须归位到现有 tab,**不**新增 tab、不重命名 tab、不引入"Analytics"标签。见 memory `ia_contract.md`。
3. **架构边界**: 新增代码遵守北极星 §2。新 device tool 必须放 `features/<域>/ai_tools/`(尚未启用迁移,但**新增**不要再往 `core/ai/runtime/device/tools/` 里堆 Finance tool)。
4. **抽象克制**: 单域 generalization 不做。任何"为以后可能的第二个域而提前抽象"的 PR 视为违反 §1.2,拒绝。
5. **运行模式**: 本地优先(local-first),用户自带 LLM key,Web 无 AI。**不**回退到云 AI relay,**不**做 Flutter+Rust local engine 全面 pivot。

---

## 1. 已发布(v0.5.2,2026-05-24 基线)

仅做事实记录,**不**作为路线规划。详情见各 detail 文档。

- **核心账本**: 资产、账户、负债、支出、投资、再平衡、活动流
- **AI 运行时**: 设备端 multi-profile,34 个 device tool,Opik 风格 trace,W-D7 云端代码彻底删除
- **FIRE OS**: Phase 0–5 完成(安全等级、bucket、压力测试、Review、AI Copilot tools)
- **Income Planner**: P0–P3 完成(profile、approved underlyings、covered call scanner、trade journal)
- **Sync**: v2 row-state 单端点 `POST /sync` 全量切换完成(client `SyncEngine` + backend `sync/store.rs`),v1 OpLog 代码已下线;30s 轮询保留。详见 `sync-v2.md`
- **IA**: Today / Activity / Wealth / Plan 已迁移完成(commits aacded4 / 3e37cfc)
- **AI 边界审计**: 2026-05-24 完成,清理 ~4.4k 行 phantom infrastructure

---

## 2. 进行中(Now,~v0.5.3–v0.5.5,2–3 周)

> Phase 1 全部条目已完成。v0.5.x 收尾,重心移到 §3 / §4。

| ID | 轨道 | 说明 | 来源 |
|---|---|---|---|
| N-1 | AI runtime polish | ✅ 已落地 (2026-05-24):`ToolDescriptor` 4 个新回归测试 + LLM profile model hint 引用 `kDefaultDeviceModel` 常量 | recent commits db1d472 / a5fc6e3 |
| N-2 | E2E sync 5 case 补齐 | ✅ 已落地 (2026-05-24):补足 phase1 P1-G 缺的 E2E-3 / E2E-4 / E2E-5 | `apps/mobile/test/e2e/sync_e2e_test.dart` |
| N-3 | 测试覆盖率提升 | ✅ 已落地 (2026-05-24):home/activity 空白补齐 — `currency_mismatch_banner` (3) + `ai_insight_feed` (3) + `activity_timeline_preview` (3) + `home_greeting_header` (4) + `activity_feed_filter_sheet` (4) + `activity_page_kind_filter` (3),共 20 个新 widget test;`flutter test test/features/{home,activity}/` 全绿(47/47)。 | [phase1 P1-H](./roadmap-phase1.md) |
| N-4 | Wealth tab "多视角聚合" 重设计 | ✅ 已落地 (2026-05-24):`features/wealth/domain/wealth_perspective.dart` — `WealthPerspective{byCategory, byCurrency}` + `buildWealthAggregation` pure 聚合器(liability 排除 / 同币种合并 / 大小写归一 / 排序);UI 段控 `WealthPerspectiveSection` + `wealthPerspectiveProvider` 接到 `WealthHubPage`,新 l10n 6 个键 EN/ZH。"by account" 维度由 `AccountsGroupedSections` 在同一页继续承担,不重复。10 个测试(7 聚合 + 3 widget)。 | [phase1 P1-D 注记](./roadmap-phase1.md#状态注记2026-05-24) |

> 注 — 以下 phase1 条目在最近的工作中已完成或作废,不再开放:
> - ✅ **P1-A** (`me/`/`more/` 清理) — IA contract migration (commits aacded4 / 3e37cfc)
> - ✅ **P1-B** (Dashboard Insights 4 类) — `InsightKind` 已含全部 4 类
> - ✅ **P1-C** (Activity feed 分页) — `activity_feed_provider.dart` 已支持
> - ❌ **P1-E** (后端 AI 工具补全) — W-D7 删除后端 AI relay 后作废
> - ✅ **P1-F** (Web 备份/恢复) — `features/settings/backup/` 已实现 web/native split
> - ✅ **P1-G** (E2E sync 5 case) — 已在本批落地
>
> 已完成项的详细状态见 [phase1.md 顶部 status 注记](./roadmap-phase1.md#状态注记2026-05-24)。

**Definition of done**: N-3 / N-4 已落地 (2026-05-24),Phase 1 关闭。工作完全转入 §3 / §4。

---

## 3. 下一程(Next,v0.6.x,8–14 周)

> 必须在 §2 完成或并行启动。**优先级**按下表从上到下。

### 3.1 多币种双显示组件(M1)

> 是 Phase 2 报表的**前置条件**。先做,后面所有金额展示统一基于它。

- ✅ **M1.1 widget 落地** (2026-05-24): `DualMoneyText` 在 `design_system/widgets/money_text.dart`,支持 inline / stacked 两种 layout;同币种自动隐藏 caption;a11y label 整合两个金额。5 个 widget test 覆盖。
- ✅ **M1.2 全量替换调用点** (2026-05-24): 明确金额展示已迁移到 `DualMoneyText` / `MoneyText` / `AppFormatters.currency`;当前 `apps/mobile/lib` 剩余 84 处裸 `.toStringAsFixed` 均为百分比、耗时、AI cost 诊断、图表缩写、Decimal rounding 或 AI prompt compact 文案,已登记到 `tool/money-display-to-string-allowlist.txt`。
  - 后续新增裸 `.toStringAsFixed` 必须优先使用 money formatter;非金额用途需带理由进入 allowlist。
- ✅ **M1.3 Lint 脚本禁止裸金额显示** (2026-05-24): `tool/lint-money-display.sh` 已切到 allowlist 驱动的 strict gate,并在 mobile CI 使用 `--strict`。
  - `tool/lint-money-display.sh --strict` 会阻止未登记的新增裸 `.toStringAsFixed`;allowlist 只接受百分比、耗时、AI cost、图表缩写、Decimal rounding 等非金额语义。
- 详: [midterm 2.3 M1](./roadmap-midterm-execution.md)

### 3.2 Budget & Cashflow MVP(M1)

> 当前产品最大空白。无 budget 是 FIRE 路径上 cashflow 端的硬伤。

- ✅ **数据层落地** (2026-05-24): `budgets` 表 (schema v15) + `BudgetRepository`,sync 走 row-state。9 个 repo 测试。
- ✅ **Riverpod provider 接线** (2026-05-24): `budgetRepositoryProvider` / `budgetsStreamProvider` / `budgetsForMonthProvider` 在 `data/repositories/providers.dart`,可被任何 UI 消费。
- ✅ **读模型 `MonthlyBudgetSummary`** (2026-05-24): `features/cashflow/domain/budget_summary.dart`,`buildMonthlyBudgetSummary` pure 聚合器(joins budgets × spend by categoryId,过滤异币种 / 跨月 / tombstone),输出 `rankedByStrain`,total over/under flag。7 个测试。
- ✅ **`/plan/budget` page 落地** (2026-05-24): `features/cashflow/ui/budget_page.dart` 接 `budgetsForMonthProvider`,Plan hub 加 Budget tile + 路由注册 + l10n 双语。4 个 widget 测试(empty / populated / 跨月过滤 / tombstone drop)。
- ✅ **Budget × FIRE 接口契约** (2026-05-24): `features/cashflow/domain/budget_signal.dart` — `BudgetSignal{noData, comfortable, strained, overBudget}` + `budgetSignalFor(summary)` pure 分类器(< 80% / 80–100% / > 100% bands + single-category overbudget bumps to strained);`monthlyBudgetSignalProvider(month)` family 让 FIRE / dashboard 单点订阅。8 个分类器测试。**FIRE service 改动作为单独 PR**(只需 watch 此 provider,无需引入 BudgetRepository 反向依赖)。
- 详: [midterm 2.1 M1](./roadmap-midterm-execution.md)

### 3.3 Income Planner P4(Wheel/收益周期)

> P0–P3 已完成。P4 是 state machine,纯设备端,**不**触碰后端。

- ✅ **State machine 落地** (2026-05-24): `wheel_lifecycle.dart`,9 个 stage(between / cashWaiting / shortPut / putExpired / putAssigned / sharesHeld / shortCall / callExpired / callCalled)+ `buildWheelLifecycle` pure function 从 trade journal 派生。10 个测试覆盖完整状态转换。
- ✅ **`/plan/wheel` page 落地** (2026-05-24): `features/options_income/presentation/wheel_lifecycle_page.dart` 接 `wheelLifecyclesProvider`(纯派生自 trade journal stream);Plan hub 加 Wheel tile + 路由 + l10n。每个 cycle 显示 symbol / 阶段标签 / 累计收益。3 个 widget 测试(空状态 / 多个 cycle 渲染 / 开仓优先排序)。
- ✅ **AI tool `get_wheel_lifecycle`** (2026-05-24): `core/ai/runtime/device/tools/get_wheel_lifecycle_tool.dart`,读 `wheelLifecyclesProvider`,可选 symbol filter,输出 cycle 数组 + evidence anchors(每个 journal entry 一个)。注册到 `kDeviceTools` + `allToolDescriptors`(catalog 35 → 含 P4)。8 个工具单元测试(descriptor / 未加载引导 / 全量 / symbol filter / 大小写不敏感 / 无匹配 / open vs closed 序列化 / evidence)。
- 详: [options-income P4](./options-income.md)

### 3.4 AI Copilot M1: user profile + evidence

> 让 AI 回答时引用本地 trace 证据,而不是凭空生成数字。

- ✅ **UserProfile contract 落地** (2026-05-24): `core/ai/contracts/user_profile.dart`,`composeUserProfile` pure function (consumption concentration + savings rate + risk appetite),snake_case JSON 接口 + < 8KB roundtrip 验证。11 个测试。
- ✅ **System prompt 注入** (2026-05-24): `core/ai/runtime/device/device_user_profile_prompt.dart` 的 `renderContextPackSystemAppendix(pack)` 把 `ContextPack.BaseContext` 渲染成 < 1KB 中文 appendix(风险偏好 + 报表币种 + 月均收支 + 趋势 + FIRE 进度);`DeviceLlmRuntime.run` 把它喂给 `DeviceSession.systemAppendix`。CN literal allowlist 已登记。8 个测试。
- ✅ **Evidence anchor 契约** (2026-05-24): `core/ai/contracts/evidence_anchor.dart` — `EvidenceAnchor({entity_table, entity_id, label?})` + `withEvidence()` helper + `readEvidence()` 解析器。Tools 可往返 `output.evidence` 数组,UI 用 entity_table+entity_id 做 deep-link dispatch。`get_wheel_lifecycle_tool` 已经率先把每个 journal entry 作为 evidence anchor 输出。7 个 contract 测试 + 1 个工具集成测试。
- ✅ **Chat UI evidence chip 渲染** (2026-05-24): `features/ai_chat/ui/tool_invocation_card.dart` 现在先读 `output.evidence` 数组(`readEvidence()`),按 entity_table 映射到 5 个 JumpKind(assets / accounts / liabilities / journal_entries / options_trade_journal);anchor 自带 label 时优先用,否则用 l10n 模板。未识别 entity_table 静默丢弃。Legacy `asset_id` / `account_id` 启发式作为 fallback 保留。新 l10n 键 5 个 EN + ZH。5 个 widget 测试。
- 详: [midterm 2.5 M1](./roadmap-midterm-execution.md)

### 3.5 Watchlist + Event timeline(M1/M2)

- ✅ **Watchlist** — 已有(`features/investment/data/watchlist_*`、`presentation/watchlist_page.dart`)
- ✅ **Event timeline 域** (2026-05-24): `features/investment/domain/reporting/event_timeline.dart`,`CorporateActionEvent` + `buildEventTimeline`(symbol filter / 时间窗 / chronological sort / dedup)。9 个测试。
- ✅ **yfinance parser** (2026-05-24): `data/market/providers/yfinance_corporate_actions.dart` `parseYahooCorporateActions()` pure 函数,从 yfinance `chart.result[0].events.{dividends,splits}` JSON 提取 `CorporateActionEvent` 列表;defensive,malformed row 丢弃不抛;事件 id 稳定(`div_SYMBOL_YYYY-MM-DD` / `split_SYMBOL_YYYY-MM-DD`)。7 个测试。
- ✅ **EventTimelineSection embeddable widget + provider** (2026-05-24): `features/investment/ui/event_timeline_section.dart` 接 `upcomingEventsForSymbolProvider(symbol)` family,按时间排序渲染分红 / 拆股 / 配股 / DRIP 行。5 个 widget 测试 + 新 l10n。
- ✅ **yfinance 网络抓取 wire-up** (2026-05-24): `data/market/services/corporate_actions_service.dart` — 调用 yfinance `chart` 端点 `events=div,splits`,经 `parseYahooCorporateActions` 解析。12 小时 TTL in-memory 缓存 + 15 分钟 error TTL(防故障期间反复打);concurrent calls 同 symbol 自动 dedup;404/500 → 空列表 + 日志(best-effort,UI 静默)。`event_timeline_providers.dart` 升级到 FutureProvider 接服务,`EventTimelineSection` 通过 `AsyncValue.value ?? []` 优雅降级。8 个服务测试(快乐路径 / 缓存 / dedup / 多 symbol / HTTP 失败缓存 / invalidate / 空 symbol / 货币 fallback)。
- ✅ **EquityAssetDetailPage 嵌入** (2026-05-24): `features/assets/ui/equity_asset_detail_page.dart` 在 trend chart 卡片之后渲染 `EventTimelineSection(symbol: asset.symbol)`;`_supportsCorporateActions(asset)` predicate 仅对 US/HK 股票触发(yfinance 覆盖范围),crypto / FX / A 股不打无效请求。
- 详: [midterm 2.2 M1/M2](./roadmap-midterm-execution.md)

### 3.6 Crash reporting opt-in(M1)

> Phase 2 后续 observability 工作的依赖项。**必须 opt-in**,默认关闭。

- ✅ **Preference + gating** (2026-05-24): `core/logging/crash_reporting_preference.dart`。`crashReportingEnabledProvider` 默认 OFF,`OptInCrashReporter` wrapper 包装任意底层 reporter,disabled 时丢弃所有事件包括 breadcrumb。4 个测试。
- ✅ **Provider 接线 + Settings UI** (2026-05-24): `crashReporterProvider` 现在包装 delegate + opt-in 状态;Settings 页 Data section 加 `_CrashReportingRow`(`InlineSwitchRow`);新增 l10n key + zh 翻译。3 个集成测试(默认 OFF / 持久化 / opt-in 生效)。
- ✅ **`LoggingCrashReporter`** (2026-05-24): `core/logging/logging_crash_reporter.dart` — dev/staging 用的 reporter,把 captureError/captureMessage/breadcrumb 路由到 `Talker`,让 opt-in pipeline 在没有 Sentry 依赖时也能端到端 visible(在 logs / TalkerScreen 里看到事件)。5 个测试。
- ✅ **debug builds 默认装载 LoggingCrashReporter** (2026-05-24): `app/bootstrap.dart` 在 `kDebugMode` 时把 `crashReporterDelegateProvider` 重写为 `LoggingCrashReporter(talker)`。Release 仍是 `NoopCrashReporter` 默认,等 Sentry SDK 接入;opt-in gate 同时套着两者。这意味着开发者现在可以在 dev 里**直接验证 opt-in pipeline 端到端**:翻开 Settings → 启用 → 触发任意错误 → TalkerScreen 可见。
- ✅ **AppConfig DSN slot 已落地** (2026-05-24):`AppConfig.sentryDsn` 通过 `--dart-define=SENTRY_DSN=...` 注入,`hasSentryDsn` 提供布尔门;默认空 = NoopCrashReporter 不变。2 个 config 单测。
- ⏳ Sentry SDK 实际接入(`sentry_flutter` 依赖 + `SentryCrashReporter` 在 `bootstrap.dart` 里替换 `crashReporterDelegateProvider`)— 决策门 (§8) 已选 **Sentry SaaS** (sentry.io managed),等用户提供 DSN secret + 同意添加 ~2MB SDK 依赖后单独 PR 接入
- 详: [midterm 2.6 M1](./roadmap-midterm-execution.md)

---

## 4. 中期(Mid,v0.7.x,14–28 周)

> 不预排时间。完成 §3 的 5/6 条目后才启动。

| ID | 轨道 | 说明 |
|---|---|---|
| M-1 | Desktop shell master-detail | ✅ **已基本落地**:`app/master_detail_layout.dart` 两栏带 splitter + URL-driven 选择 crossfade,接到 `_DesktopShell`(`AppRootShell` ≥ 1240dp 分支)+ accounts / assets / ai_chat master 列表;5 个 layout test。后续如出现新 master-list 域,直接复用该 widget,不再当 M-1 条目计 |
| M-2 | AI Copilot M2 | **Contract 层已落地** (2026-05-24):`core/ai/contracts/proposal_envelope.dart` 新增 `BatchProposal` sealed subtype + `BatchUndoToken`(拒绝 external / 拒绝嵌套 / 空 children 触发 assert);`interaction_mode.dart` 加 `_deriveBatchMode`(最保守-子项胜出,oneTap<swipe<confirmDiff,batch 永不到 typed)。`core/ai/progress/long_task_progress.dart` — 进度描述符(id/label/detail/ratio/cancelable + 钳位 + elapsed)。新增 12 个单测(6 envelope+mode / 6 progress)。**UI wire-up 是后续 PR**(`propose_card.dart` 路由 BatchProposal + DriftUndoStack 加 `batch_undo` kind + 长任务进度条 widget) |
| M-3 | Income Planner P5 | 🚧 **被决策门阻塞**(§8:Tradier OAuth backend proxy 单独 Worker 与否未定);Tradier OAuth + 真 greeks。**Backend proxy 必须 schema-agnostic**,走 `sync_rows`,不在 Worker 里写业务逻辑。决策出来前不动 |
| M-4 | Investment advanced M2/M3 | DCA simulator ✅ **已落地** (`features/investment/domain/dca/dca_simulator.dart` + `presentation/dca_simulator_page.dart`,挂在 `/plan/dca`,带 golden + engine 测试)。Event timeline ✅ **MVP 已闭合**(§3.5,12hr cache + EquityAssetDetailPage 嵌入)。**Tax export 🚧 被决策门阻塞**(§8:IRS / 中国个税 / 通用 CSV 优先级未定);domain 层 `features/investment/domain/tax/` 已有 `tax_policy` / `jurisdiction_tax_policy` / `tax_jurisdiction` 骨架,export pipeline 等格式决策后单独 PR |
| M-5 | Performance traces | ✅ **harness 已落地** (2026-05-24):`core/perf/frame_timing_collector.dart` 接 `SchedulerBinding.addTimingsCallback` 维护 600 帧 ring buffer + p50/p95/jank 统计;`perf_trace_recorder.dart` 暴露 `begin/end/measure` 名义窗口,基于 vsync 时间戳过滤而非 wall clock,保证多窗口不互相串扰;`providers.dart` 在 `frameTimingCollectorProvider` 首读时 attach,bootstrap eager init。10 个单测(ring 容量 / 空状态 / jank 计数 / p50+p95 插值 / 窗口过滤 / begin-end / 嵌套报错 / measure 抛异常仍释放)。后续如需 UI 看板可单建 dev surface,不阻塞 M-5 关闭 |
| M-6 | Command palette + 快捷键 | ✅ **已落地**:`core/command_palette/` 全套(`command_palette_dialog.dart` + `default_commands.dart` + `ask_ai_result_pane.dart`)挂在全局 Cmd/Ctrl+K;`core/shortcuts/` 完整(global/scope/master-detail 三层 + 帮助对话框 + 键位平台适配)。测试:command palette 2 个文件 85 cases,shortcuts 3 个文件 65 cases。Desktop shell 接 `GlobalShortcutsScope` 已 wire |

---

## 5. 触发性(Triggered,不预排,不写时间)

> 这些**有设计**但**不进开发计划**。只有"触发条件"成立时才动。
> 在触发之前出现"顺手做一点"的 PR,**拒绝**。
>
> **2026-05-24 现状盘点**:盘点 §5 各条在仓库的真实落地度后,**Sync v2 提前以"全量切换"形态落地**(见下表注释),其余条目仍是触发性。`features/ingest/` 的通用 CSV / 共享意图 / 云 OCR 通道也已构建完成,只是 provider-specific 解析器没做。其他条目均未启动。

| 轨道 | 触发条件 | 落地度 | 设计参考 |
|---|---|---|---|
| **FIRE OS Phase 6 sync** | 出现 ≥1 例用户报告的跨端 FIRE plan 不一致 | ❌ **未启动**(`features/fire/data/*_preferences.dart` 显式注释 "Phase 6 will migrate to a `fire_plans` table",当前 FIRE plan 留在 SharedPreferences 不走 sync) | [roadmap-fire-os.md Phase 6](./roadmap-fire-os.md),memory `fire_os_design.md` |
| **Sync v2 切换** | v1 polling 在生产中出现可测量的延迟痛点(>10s 中位数);**或**多设备用户达到 ≥3 个 | ✅ **已全量切换**(触发前完成):`apps/backend/src/sync/store.rs` 是 v2 row-state 通用 store,`apps/mobile/lib/core/sync/sync_engine.dart` 是 v2 cycle(单 `POST /sync` push+pull),v1 OpLog 代码已全部下线(grep 不到任何 `/sync/push` / `/sync/pull` / `oplog`)。CLAUDE.md 也已标 v2 active。**§5 这条等同于历史档案,不再触发**| [sync-v2.md](./sync-v2.md) |
| **Sync v2 E2EE** | v2 切换完成 ≥1 个月稳定后 | ❌ **未启动**(`core/sync/` 下无 encrypt / E2EE / libsodium 代码)。v2 已切换日期可作为窗口起点;若 ≥1 月生产稳定,可触发 | [sync-v2.md](./sync-v2.md) §安全 |
| **Memory Layer 落地** | 至少出现 1 个具名 Finance caller(例如 AI Copilot 需要长期偏好检索) | ❌ **未启动**(只有 `core/ai/local/embedding/semantic_memory.dart` 显式自标 "Deliberate stub … production consumer is intentionally absent",pipeline 就绪但无 caller) | 北极星 §2.6 |
| **数据导入生态(支付宝/微信/券商对账单)** | 用户实际反馈现有手工录入瓶颈 | ⚠️ **基础设施已就绪,provider-specific 解析器未做**:`features/ingest/` 已有 `csv_ingest_parser`(CJK 表头别名)/ `ingest_pipeline` / `ingest_dedup` / `ingest_draft_store` / 云 Vision (`cloud_ingest_client`) / `share_intent_service` / 隐私门 / Review 页 + 9 个 ingest test 文件。**待触发的是 alipay/wechat/券商对账单**的命名解析器层 | [roadmap.md Phase 3](./roadmap.md) |
| **i18n 扩展(ja/zh-Hant/ko)** | 出现非中文用户群 | ❌ **未启动**(`lib/l10n/` 只有 `app_en.arb` + `app_zh.arb`) | [roadmap.md Phase 3](./roadmap.md) |
| **多用户/家庭账本** | 用户实际请求 + 设计审 | ❌ **未启动**(`lib/features/` 下无 household / family / multi_user 目录) | [roadmap.md Phase 3](./roadmap.md) |

---

## 6. 反目标(NOT,任何 PR 想做就拒绝)

> 这是北极星 §1 的操作化版本。**这一节的存在本身**就是为了在 PR review 时援引。

### 6.1 LifeOS / 多域抽象类(援引北极星 §1.1 / §1.2 / §1.5 / §1.8)

- ❌ 新增 `core/ai/intent/AiIntentInvocation` 的 `domain` 字段
- ❌ 在 `core/ai/runtime/device/tools/` 之外**先建** `features/<未来域>/ai_tools/` 空目录
- ❌ 在 `core/auth/` 加跨域权限 / opt-in / scope 概念
- ❌ 在 `core/sync/` 引入 row family 按域 namespace
- ❌ 把 `data/db/` 改名/迁移到 `core/persistence/` 纯为"反映跨域角色"
- ❌ 在 `features/<finance>/` 内 import `features/<其它>/`(`shared/` 例外)
- ❌ 把 Finance 实体(`Money` / `Account` / `JournalEntry`)塞进任何 `core/ai/contracts/` / `core/sync/` 协议字段
- ❌ 写**未触发域**(TimeOS / KnowledgeOS / LivingOS)的"Phase 0–N"路线图。HealthOS 已触发(2026-05-24),其 SSOT 在 `healthos-domain.md`,本条目不再阻止

### 6.2 产品形态类(援引北极星 §1.7)

- ❌ 社交 feed / 评论 / follow
- ❌ 高频内容 / 短视频 / 直播
- ❌ 通用 SaaS / 企业协作 / 团队工作流
- ❌ ToC 娱乐功能(成就墙、游戏化排行榜等)

### 6.3 技术 pivot 类(援引北极星 §1.3 / §1.6)

- ❌ Flutter UI + Rust 本地引擎全面 pivot(FFI 仍可在**有明确 caller**的局部使用,例如 sync 加密)
- ❌ sync-v2 升级成事件平台 / CRDT 框架 / 多 schema 协商
- ❌ 把 `AiTrace` 从本地 Drift 表升级成跨端事件总线

### 6.4 IA 类(援引北极星 §1.4)

- ❌ 在 Today / Activity / Wealth / Plan 之外**新增** tab
- ❌ 把现有 tab 改名(尤其禁止 "Analytics" 字样)
- ❌ 拆分 Plan tab(Plan = FIRE + Budget + Cashflow + Income Planner 的集合页)

---

## 7. 与 detail 文档的同步规则

| detail 文档 | 同步规则 |
|---|---|
| `roadmap-phase1.md` | 任务级细节 SSOT;**任务完成**只标在 detail 文档,本文档每月看一次刷新 §2 |
| `roadmap-midterm-execution.md` | 任务级细节 SSOT;M1→§3,M2→§4,M3→§4 |
| `roadmap-fire-os.md` | FIRE OS 引擎 SSOT;Phase 6 触发条件本文档 §5 |
| `options-income.md` | Income Planner SSOT;P4/P5 进入本文档 §3.3 / §4 M-3 |
| `ai-architecture.md` | AI 设计 SSOT;本文档**不**重复 |
| `roadmap.md` | **历史参考**。本文档 §3–§5 已 supersede 其 Phase 1/2/3 调度,但 Phase 3 的具体候选项(数据导入、i18n、多用户)挪进本文档 §5 触发表 |

---

## 8. 决策门(到点必须显式决定的事)

> 不是阻塞,但拖延会让下一程模糊。每条都关联到一个 §3 / §4 任务。

| Gate | 关联 | 状态 / 决策 |
|---|---|---|
| ~~`me/` 与 `more/` 的最终去留~~ | §2 N-3 | ✅ **已关闭** (2026-05-24):IA migration (commits aacded4 / 3e37cfc) 后两个目录均不再存在,功能已挪进 Today / Settings。无遗留 caller |
| ~~Plan tab 内 FIRE / Budget / Cashflow / Income 的二级 IA(平铺还是分组)~~ | §3.2 / §3.3 | ✅ **已关闭** (2026-05-24):`features/plan/ui/plan_hub_page.dart` 已落 flat tile grid (`_PlanSectionGrid`),按"决策面" tile 罗列;不引入二级 tabs,避免 IA 三层嵌套 |
| Tax export 格式优先级(IRS Schedule D / 中国个税 / 通用 CSV) | §4 M-4 | ⏳ 待决:M-4 启动前需选定 |
| ~~Crash reporter 后端(自托管 Sentry / Cloudflare D1 自存 / 第三方 SaaS)~~ | §3.6 | ✅ **已决策** (2026-05-24):**Sentry SaaS** (sentry.io managed)。理由:`sentry_flutter` 是行业标配,opt-in 阀已在客户端把关(默认 OFF),不必为单用户 app 跑自托管基础设施;DSN 通过 `--dart-define=SENTRY_DSN=...` 注入。剩余工作:依赖添加 + `SentryCrashReporter` 实现,等 DSN secret |
| Tradier OAuth 的 backend proxy 是否单独 Worker | §4 M-3 | ⏳ 待决:P5 启动前需选定 |

---

## 9. 使用方式

- 排期周会:看 §2(必做)+ §3(优先级);**不**在会上讨论 §5(触发性,无法预排)
- PR review: 触及 `core/` 或新建跨 feature import 时,把 PR 对照 §6 + 北极星 §2 走一遍
- 改本文档前自问:是 §2/§3/§4 的事实推进?还是 §5 的触发条件成立?
  - 都不是 → 不应该改本文档。先去 detail 文档动手
- 本文档目标长度: **< 400 行**(当前在限内)。超出意味着在写 detail,应该回流到 detail 文档

---

## 10. Phase D 状态 (2026-05-24 启动)

> Phase D 是 LifeOS 多域 shell 启动。本节是**指针**,真正的 SSOT 在 `lifeos-shell.md`。
> 决策记录见 `lifeos-decision-2026-05-24.md`,架构边界更新见 `lifeos-architecture-northstar.md` §4。

| 阶段 | 状态 |
|---|---|
| D-0 决策落地 + 文档基线 | ✅ 完成 (2026-05-24) |
| D-1.7 Memory Layer substrate (vector store + embedder seam) | ✅ 完成 (2026-05-24) |
| D-1.7b Memory Runtime (typed records + lifecycle + ContextBuilder) | ✅ 完成 (2026-05-24) |
| D-1.7c Rust EmbeddingGemma-300M drop-in (fastembed/ort, ONNX INT8, 768-d) | ✅ 落地 (2026-05-24) — fastembed-rs 5.13, 18 MB dylib (ORT bundled), AppConfig opt-in, host build 验证;iOS/Android cross-compile 待用户机器执行 (`lifeos-shell.md` §6.6) |
| D-1.1 / 1.2 / 1.3 / 1.4 / 1.5 / 1.6 / 1.8 | ⏳ 未启动 |
| D-2 HealthOS MVP | ⏳ 等 D-1 |
| D-3+ TimeOS / KnowledgeOS / LivingOS | ❌ 触发性,未触发 |

**Phase D-1 期间 §3 / §4 FinanceOS 新功能冻结**: 只接 P0 bug 修复。§3.2 (Budget × FIRE 接线) / §3.6 (Sentry SDK 接入) 这两个尾巴可在 D-1 启动前清掉,清完即冻结。

**Rust 边界**: Phase D 期间新增 Rust 模块**仅** Memory Layer embedder + tokenizer(D-1.7),装在 `apps/mobile/native/lifeos_native/` 单一 crate。其它所有 D-1.x / D-2.x 全留 Dart。详见 `lifeos-shell.md` §10。

**相关文档**:
- `lifeos-decision-2026-05-24.md` — 启动 ADR(为什么 HealthOS / 为什么不并发 / 约束)
- `lifeos-shell.md` — 跨域 shell SSOT(IA / Memory / sync namespace / auth scope / tool 分层 / Rust 边界 / CI gate)
- `healthos-domain.md` — HealthOS 域 SSOT(scope / schema / AI tools / IA placement)
