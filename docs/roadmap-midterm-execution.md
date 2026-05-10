# NaviWealth 中期执行计划（M1 → M3，6 个月）

> 文档版本：2026-05-10 · 关联：`docs/roadmap.md` §2
> 这是 §2 中期规划的**任务级展开**。颗粒度目标：拿到任意一张 ticket，工程师当天能开 PR。
> 高层节奏与里程碑请看 roadmap §2.0。

---

## 0. 怎么用这份文档

- **Ticket ID**：`MT-{workstream}.{milestone}.{seq}`，如 `MT-2.1.M1.3` = 工作流 2.1（预算）的 M1 第 3 个任务。每条 ticket 对应至多 1 个 PR；过大时拆 a/b/c。
- **Size**：`S` ≤ 1 day · `M` 2–3 days · `L` 4–7 days · `XL` 需先拆。**禁止 XL ticket 直接进入开发**。
- **Depends**：上游 ticket。同一行多个 = 全部完成才能开始。
- **DoD 通用清单**（每条 ticket 隐含）：
  - [ ] 单元 / widget 测试（覆盖核心路径与至少 1 个边界）
  - [ ] `flutter analyze --fatal-infos` / `cargo clippy -- -D warnings` 通过
  - [ ] 涉及金额字段：使用 `Money` / `Decimal`，无 `double`
  - [ ] 涉及同步表：oplog 验证 + 双设备 LWW 用例（如有 sync 影响）
  - [ ] 用户可见文案：en + zh 双 locale（ARB）
  - [ ] PR 描述链接到本文档对应 ticket
- 在 PR 标题首部添加 ticket：`MT-2.1.M1.3 budget: add Drift table`。

## 1. 节奏

- **6 个 Sprint × 2 周 = 12 周** 覆盖 M1（Sprint 1–2）+ M2（Sprint 3–6 的前半）。M3 的精细化可在 M1 接近末期再做一次重新估算。
- 每 Sprint 结束做：①demo + ②metrics review（来自 §2.6 埋点）+ ③下一 Sprint backlog 锁定。
- **优先级 P0 / P1 / P2** 标在每条 ticket 前缀（P0 = 阻塞下个里程碑；P1 = 该里程碑必做；P2 = 可挪到下里程碑）。

---

## 2.1 预算与现金流（`features/budget/` 新建）

### M1（Sprint 1–2）数据模型 + 月度预算 MVP

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.1.M1.1 | P0 | M | Drift 表 `budgets` + `budget_progress_view` | — | `data/db/tables.dart`, `data/db/converters.dart` |
| MT-2.1.M1.2 | P0 | M | Drift 表 `recurring_transactions`（不调度，先存） | — | 同上 |
| MT-2.1.M1.3 | P0 | M | Sync 协议接入：oplog entity 类型登记 + 后端 materialise | MT-2.1.M1.1, MT-2.1.M1.2 | `apps/backend/src/sync/`, `apps/backend/migrations/0006_*.sql`, `docs/sync-protocol.md` |
| MT-2.1.M1.4 | P0 | M | Domain 层：`BudgetPeriod`、`BudgetProgress`、`BudgetRepository` | MT-2.1.M1.1 | `features/budget/domain/`, `features/budget/data/` |
| MT-2.1.M1.5 | P1 | M | UI：月度预算编辑页（按 expense 分类，单卡片进度） | MT-2.1.M1.4 | `features/budget/ui/budget_editor_page.dart` |
| MT-2.1.M1.6 | P1 | S | 路由 + 入口：从 settings / more 进入 | MT-2.1.M1.5 | `app/router.dart`, `features/settings/` |
| MT-2.1.M1.7 | P1 | M | 测试：domain 单测（rollover policy）+ widget 测试（编辑页保存）+ E2E LWW 用例 1 条 | MT-2.1.M1.5, MT-2.1.M1.3 | `test/features/budget/`, `test/e2e/` |
| MT-2.1.M1.8 | P1 | S | i18n：en + zh ARB 全量 | MT-2.1.M1.5 | `lib/l10n/` |

**Schema 草案**（草拟，落地时以 migration 为准）：

```sql
-- budgets
id TEXT PRIMARY KEY,
period_kind TEXT NOT NULL CHECK(period_kind IN ('monthly','weekly')),
period_start TEXT NOT NULL,                       -- ISO date
category_id TEXT NOT NULL REFERENCES expense_categories(id),
amount_minor INTEGER NOT NULL,                    -- minor units
currency TEXT NOT NULL,
rollover_policy TEXT NOT NULL DEFAULT 'reset',   -- 'reset' | 'carry'
created_at_hlc TEXT, updated_at_hlc TEXT,
deleted_at_hlc TEXT,
UNIQUE(period_kind, period_start, category_id);

-- recurring_transactions
id TEXT PRIMARY KEY,
rrule TEXT NOT NULL,                              -- RFC5545 subset
template_posting_json TEXT NOT NULL,              -- frozen JSON of postings
next_run_at TEXT,                                 -- materialised hint
enabled INTEGER NOT NULL DEFAULT 1,
created_at_hlc TEXT, updated_at_hlc TEXT,
deleted_at_hlc TEXT;
```

**M1 验收**：在 demo 环境录入 12 个分类的月度预算，dashboard 显示进度卡片，双设备并发改预算后 LWW 一致。

### M2（Sprint 3–4）计划交易 + 告警

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.1.M2.1 | P0 | L | RRULE 子集 parser + expander（FREQ/INTERVAL/BYMONTHDAY） | — | `features/budget/domain/recurring/` |
| MT-2.1.M2.2 | P0 | M | RecurringScheduler（前台触发，无后台任务） | MT-2.1.M2.1 | `features/budget/domain/recurring/scheduler.dart` |
| MT-2.1.M2.3 | P1 | M | UI：计划交易 CRUD 页（频率 picker + 模板复用过往交易） | MT-2.1.M2.2 | `features/budget/ui/recurring_*` |
| MT-2.1.M2.4 | P1 | M | Dashboard 卡片：本月预算进度 + 超支预警 | MT-2.1.M1.5 | `features/home/`, `features/budget/ui/` |
| MT-2.1.M2.5 | P1 | M | "下个月将到期"列表（订阅 / 还款 / 定投预演） | MT-2.1.M2.2 | `features/budget/ui/upcoming_page.dart` |
| MT-2.1.M2.6 | P2 | S | 阈值偏好（80%/100% 默认 + 分类粒度覆写） | MT-2.1.M2.4 | `features/budget/data/` |
| MT-2.1.M2.7 | P0 | M | RRULE expander 单测 ≥ 30 用例（含 DST、闰年、月末日 31 → 30/2 月） | MT-2.1.M2.1 | `test/features/budget/recurring/` |

### M3（Sprint 5–6）现金流瀑布 + FIRE 联动

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.1.M3.1 | P0 | L | 现金流瀑布图 widget（季度/年度切换） | MT-2.1.M2.* | `design_system/charts/cashflow_waterfall.dart` |
| MT-2.1.M3.2 | P1 | M | FIRE 模块拉取计划交易作为蒙特卡洛骨架 | MT-2.1.M2.2 | `features/fire/` |
| MT-2.1.M3.3 | P1 | M | 性能：12 个月 RRULE 展开 < 200ms 基准 + bench 测试 | MT-2.1.M2.1 | `test/features/budget/perf/` |
| MT-2.1.M3.4 | P2 | S | 文档：`features/budget/README.md` | MT-2.1.M3.* | — |

**M3 决策点**：M2 末评审是否将"计划交易"与 FIRE 的"未来现金流预测"合并到 FIRE，避免 M3 重写。

---

## 2.2 投资进阶

### M1 — Watchlist α

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.2.M1.1 | P0 | M | Drift 表 `watchlist_items` + repo | — | `data/db/tables.dart`, `features/investment/watchlist/data/` |
| MT-2.2.M1.2 | P0 | M | Watchlist provider 复用 `composite_market_data_service` + 限速器 | MT-2.2.M1.1 | `features/investment/watchlist/data/providers.dart` |
| MT-2.2.M1.3 | P1 | M | UI：列表 + 添加搜索（复用现有 symbol search） | MT-2.2.M1.2 | `features/investment/watchlist/ui/` |
| MT-2.2.M1.4 | P1 | M | 简单告警规则（价格跌破 / 涨破 X）+ 本地通知触发 | MT-2.2.M1.2 | 同上 |
| MT-2.2.M1.5 | P1 | M | 行情刷新策略：前台 5 min poll + cache 命中优先 | MT-2.2.M1.2 | `features/investment/watchlist/` |
| MT-2.2.M1.6 | P0 | M | 测试：30 symbol 5s SLA bench + 限速器协作单测 | MT-2.2.M1.5 | `test/features/investment/watchlist/` |

### M2 — 事件流 + 税务导出

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.2.M2.1 | P0 | M | 事件时间线投影：dividend / split / rights 由现有模型聚合 | — | `features/investment/domain/reporting/event_timeline.dart` |
| MT-2.2.M2.2 | P1 | M | UI：持仓详情页加 "事件" tab | MT-2.2.M2.1 | `features/investment/presentation/holding_detail/` |
| MT-2.2.M2.3 | P0 | L | 公司行动录入入口（拆股 / 配股 / DRIP）走 trade_entry | MT-2.2.M2.1 | `features/investment/domain/trade_entry/`, `features/investment/presentation/` |
| MT-2.2.M2.4 | P0 | L | 税务报表生成器（CSV）：US / HK / CN 三 jurisdiction | — | `features/investment/domain/tax/export/` |
| MT-2.2.M2.5 | P1 | M | UI：导出 dialog + 文件保存（Web 端走 `file_saver_web`） | MT-2.2.M2.4 | `features/investment/ui/tax_export_*` |
| MT-2.2.M2.6 | P1 | S | 免责声明组件（导出页 + PDF 顶部固定） | MT-2.2.M2.5 | `design_system/widgets/legal_disclaimer.dart` |
| MT-2.2.M2.7 | P0 | M | 税务导出与 `cost_basis_engine` 交叉验证测试 | MT-2.2.M2.4 | `test/features/investment/tax_export/` |

### M3 — DCA 模拟 + 回测

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.2.M3.1 | P0 | L | DCA 模型（symbol/篮子 + 频率 + 金额 + 窗口） | — | `features/investment/domain/dca/` |
| MT-2.2.M3.2 | P0 | M | 回测引擎（市场缓存 + 缺数标注） | MT-2.2.M3.1 | 同上 |
| MT-2.2.M3.3 | P1 | M | UI：参数面板 + 结果图（累计收益、平均成本、回撤） | MT-2.2.M3.2 | `features/investment/ui/dca_*` |
| MT-2.2.M3.4 | P1 | M | 与 §2.1 计划交易联动：导出 DCA 计划为 recurring_transactions | MT-2.2.M3.1, MT-2.1.M2.2 | 跨模块 |
| MT-2.2.M3.5 | P0 | M | 60 月数据回测 < 1s bench | MT-2.2.M3.2 | `test/features/investment/dca/perf/` |

---

## 2.3 多币种与汇率体验

### M1 — `MoneyText` dual-display + 全量替换

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.3.M1.1 | P0 | M | `MoneyText` widget（默认 base，长按 / hover 切原币，caption 双显） | — | `design_system/widgets/money_text.dart` |
| MT-2.3.M1.2 | P0 | L | 全量替换：accounts / investment / expense / liabilities / fire / analytics | MT-2.3.M1.1 | 跨多个 features |
| MT-2.3.M1.3 | P0 | S | grep PR check：禁止直接 `.toStringAsFixed` 显示 Money | — | `tool/lint-money-display.sh`, `.github/workflows/mobile.yml` |
| MT-2.3.M1.4 | P1 | M | 单测：4 locale × RTL × 长货币代码 × 高精度小数 | MT-2.3.M1.1 | `test/design_system/widgets/money_text_test.dart` |
| MT-2.3.M1.5 | P1 | S | Visual baseline：每个使用 page 加 1 个 golden | MT-2.3.M1.2 | `docs/visual-baseline/` |

### M2 — 历史汇率曲线 + 自动拉取增强

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.3.M2.1 | P0 | M | `fx_rates` 表加 `source` 字段（`auto`/`manual`）+ 迁移 | — | `data/db/tables.dart`, `data/repositories/fx_rate_repository.dart` |
| MT-2.3.M2.2 | P0 | M | `FxRateSyncService` 升级：周期任务 + 多源 fallback（exchangerate.host / Frankfurter） | MT-2.3.M2.1 | `features/settings/fx_rates/fx_rate_sync_service.dart` |
| MT-2.3.M2.3 | P1 | M | mini chart 组件 + settings 页历史曲线 | MT-2.3.M2.1 | `features/settings/fx_rates/` |
| MT-2.3.M2.4 | P1 | S | 离线 fallback：读最后已知 + 标注 stale | MT-2.3.M2.2 | 同上 |
| MT-2.3.M2.5 | P0 | M | 24h 至少 1 次成功率 > 99% 集成测试（mock 多源） | MT-2.3.M2.2 | `test/features/settings/fx_rates/` |

### M3 — base currency 全局热切换

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.3.M3.1 | P0 | L | `baseCurrencyProvider` 重构为可观察 + 受影响 provider 全量挂载 | — | `domain/services/`, 跨 features |
| MT-2.3.M3.2 | P1 | M | 切换提示对话框（快照汇率 / 当前汇率二选一） | MT-2.3.M3.1 | `features/settings/` |
| MT-2.3.M3.3 | P0 | M | 性能 bench：10k journal entries 切换 < 500ms | MT-2.3.M3.1 | `test/perf/base_currency_switch_test.dart` |
| MT-2.3.M3.4 | P1 | S | 文档：`docs/multi-currency.md` | MT-2.3.M3.* | — |

---

## 2.4 桌面端 Shell 完整化

### M1 — 命令面板覆盖率达标

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.4.M1.1 | P0 | M | 每个 feature 模块导出 `command_palette_contributions.dart` 协议 | — | `core/command_palette/` |
| MT-2.4.M1.2 | P0 | M | bootstrap 聚合注册表 + 模糊搜索增强 | MT-2.4.M1.1 | `core/command_palette/command_palette.dart` |
| MT-2.4.M1.3 | P0 | M | 跳转动作：账户 / 资产 / 投资标的（动态生成） | MT-2.4.M1.1 | accounts, assets, investment 三模块 |
| MT-2.4.M1.4 | P0 | M | 新建动作：交易 / 支出 / 账户 | MT-2.4.M1.1 | accounts, expense, investment |
| MT-2.4.M1.5 | P1 | S | 设置类动作：主题 / 语言 / base currency | MT-2.4.M1.1 | `features/settings/` |
| MT-2.4.M1.6 | P1 | M | 最近使用排序持久化 | MT-2.4.M1.2 | `app/shell_preferences.dart` |
| MT-2.4.M1.7 | P0 | M | 200+ 项注册下冷启动 < 100ms bench | MT-2.4.M1.2 | `test/core/command_palette/perf/` |

### M2 — master-detail 三大模块

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.4.M2.1 | P0 | M | accounts 列表页接入 master-detail | — | `features/accounts/` |
| MT-2.4.M2.2 | P0 | M | assets 列表页接入 | — | `features/assets/` |
| MT-2.4.M2.3 | P0 | M | investments 列表页接入 | — | `features/investment/presentation/` |
| MT-2.4.M2.4 | P0 | M | 详情子路由 deep link（不破坏 web routing 检查清单） | MT-2.4.M2.1, .2, .3 | `app/router.dart` |
| MT-2.4.M2.5 | P1 | M | 列偏好持久化（宽度 / 排序） | MT-2.4.M2.* | `app/shell_preferences.dart` |
| MT-2.4.M2.6 | P0 | S | web routing 检查清单 100% 通过 | MT-2.4.M2.4 | `docs/web-routing.md`, `web_smoke/` |

### M3 — 快捷键发现性

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.4.M3.1 | P0 | M | 帮助页：从 `shortcut_bindings.dart` 自动渲染 + 平台修饰键 | — | `core/shortcuts/shortcut_help_dialog.dart` |
| MT-2.4.M3.2 | P1 | S | `?` / `Cmd+/` 快捷键打开帮助 | MT-2.4.M3.1 | 同上 |
| MT-2.4.M3.3 | P1 | S | 命令面板内联快捷键提示 | MT-2.4.M3.1 | `core/command_palette/` |
| MT-2.4.M3.4 | P0 | S | 帮助页与代码绑定漂移检测 | MT-2.4.M3.1 | `test/core/shortcuts/` |
| MT-2.4.M3.5 | P1 | S | 文档：`docs/desktop-shell.md` | MT-2.4.M3.* | — |

---

## 2.5 AI 助手能力升级

### M1 — 用户画像 v0 + 引用证据

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.5.M1.1 | P0 | M | 客户端 profile composer（消费集中度、储蓄率、风险偏好代理） | — | `features/ai_chat/domain/profile/` |
| MT-2.5.M1.2 | P0 | M | system prompt 注入 profile（首条消息携带，会话内复用） | MT-2.5.M1.1 | `features/ai_chat/data/`, `apps/backend/src/ai/anthropic.rs` |
| MT-2.5.M1.3 | P0 | S | 8KB 硬上限 + 降级策略（仅发 hash） | MT-2.5.M1.1 | 同上 |
| MT-2.5.M1.4 | P0 | M | 工具返回结果加 evidence 字段（涉及的交易 / 账户 ID 列表） | — | `apps/backend/src/ai/tools.rs` |
| MT-2.5.M1.5 | P1 | M | UI：工具卡片 evidence 区块 + 点击跳转 | MT-2.5.M1.4 | `features/ai_chat/ui/` |
| MT-2.5.M1.6 | P0 | M | 10k entries profile 生成 < 50ms bench | MT-2.5.M1.1 | `test/features/ai_chat/profile/` |

### M2 — 批量提案 + 回滚

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.5.M2.1 | P0 | L | `proposals.rs` 支持 batch 提案 schema（多个 plan 原子性） | — | `apps/backend/src/ai/proposals.rs` |
| MT-2.5.M2.2 | P0 | M | 客户端事务执行（任一失败回滚整批） | MT-2.5.M2.1 | `features/ai_chat/domain/proposal_plan.dart` |
| MT-2.5.M2.3 | P0 | L | oplog `actor` 字段补 `ai_proposal:{id}` + 后端 materialise | — | `apps/backend/src/sync/`, migration `0007_*.sql` |
| MT-2.5.M2.4 | P0 | L | 撤销最近 N 个 AI 写入（生成补偿 op，不删 oplog） | MT-2.5.M2.3 | `features/ai_chat/domain/undo/` |
| MT-2.5.M2.5 | P1 | M | UI：撤销面板 + 24h 窗口提示 | MT-2.5.M2.4 | `features/ai_chat/ui/` |
| MT-2.5.M2.6 | P0 | M | E2E：批量提案双设备 LWW 一致性 | MT-2.5.M2.* | `test/e2e/sync/` |

### M3 — 长任务进度 + 多轮上下文

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.5.M3.1 | P0 | M | SSE 增加 `progress` 事件 + last-event-id 续传 | — | `apps/backend/src/ai/sse.rs`, `features/ai_chat/data/` |
| MT-2.5.M3.2 | P1 | M | UI：长任务进度条 + 步骤树 | MT-2.5.M3.1 | `features/ai_chat/ui/` |
| MT-2.5.M3.3 | P1 | M | 会话级摘要（每 5 轮压缩，存 session 元数据） | — | `features/ai_chat/domain/chat_models.dart` |
| MT-2.5.M3.4 | P0 | M | 网络波动下 SSE 不丢 progress 集成测试 | MT-2.5.M3.1 | `test/features/ai_chat/sse/` |

---

## 2.6 可观测性与运营

### M1 — 崩溃上报 opt-in 上线

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.6.M1.1 | P0 | M | Settings "诊断与隐私" 区块 + opt-in toggle（默认关） | — | `features/settings/` |
| MT-2.6.M1.2 | P0 | M | Sentry DSN 通过 `--dart-define` 注入 + 启用门控 | MT-2.6.M1.1 | `core/logging/crash_reporter.dart`, `core/config/app_config.dart` |
| MT-2.6.M1.3 | P0 | M | 脱敏函数 + 单测（金额 / symbol / free-text） | — | `core/logging/sanitizer.dart`, `test/core/logging/` |
| MT-2.6.M1.4 | P0 | S | 后端：错误响应统一上报 Cloudflare Analytics | — | `apps/backend/src/error.rs` |
| MT-2.6.M1.5 | P0 | S | 文档：`docs/observability.md`（明确什么会上传） | MT-2.6.M1.* | — |
| MT-2.6.M1.6 | P0 | S | PR 模板：触碰上报路径需勾选"已审计新增字段" | — | `.github/pull_request_template.md` |

### M2 — 性能埋点 + 后端告警

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.6.M2.1 | P0 | M | 客户端 trace 框架（启动 / dashboard / push-pull / AI 首 token） | — | `core/observability/trace.dart` |
| MT-2.6.M2.2 | P1 | M | 本地 100 次 ring buffer + opt-in 聚合上传 | MT-2.6.M2.1 | 同上 |
| MT-2.6.M2.3 | P0 | M | 后端 SLO 告警：push p99 > 2s / err > 1% / HLC 偏差 > 5min | — | `apps/backend/src/`, Cloudflare Analytics 配置 |
| MT-2.6.M2.4 | P1 | S | 告警通道：Email + Slack webhook | MT-2.6.M2.3 | wrangler secrets |

### M3 — 仪表盘 + 周报自动化

| ID | P | Size | Title | Depends | Files |
|---|---|---|---|---|---|
| MT-2.6.M3.1 | P0 | M | `/admin/metrics` 路由（JWT 限本人）输出 JSON | — | `apps/backend/src/routes/` |
| MT-2.6.M3.2 | P1 | M | 周报 GitHub Action：每周一 issue 评论 | MT-2.6.M3.1 | `.github/workflows/weekly-report.yml` |
| MT-2.6.M3.3 | P2 | S | 开发者菜单 trace 查看器（debug build only） | MT-2.6.M2.1 | `features/settings/dev_menu/` |

---

## 3. 跨工作流共享 / 前置任务

这些不属于任一工作流但被多个引用，应在对应 milestone 启动前完成。

| ID | P | Size | Title | 阻塞 |
|---|---|---|---|---|
| MT-X.1 | P0 | M | Sync 协议添加表的 SOP 文档 + checklist | MT-2.1.M1.3, MT-2.5.M2.3 |
| MT-X.2 | P0 | S | RRULE 子集规范 ADR | MT-2.1.M2.1 |
| MT-X.3 | P0 | S | Money 显示 lint script + CI 接入 | MT-2.3.M1.3 |
| MT-X.4 | P1 | S | E2E sync harness 在 `test/e2e/` 落地最小骨架 | MT-2.1.M1.7, MT-2.5.M2.6 |
| MT-X.5 | P1 | S | `docs/sync-protocol.md` 升级为 v1.1（追加新表，仍兼容 v1.0 客户端） | MT-2.1.M1.3 |

---

## 4. 风险登记册

| 风险 | 影响范围 | 概率 | 缓解 | Owner（占位） |
|------|---------|------|------|--------------|
| RRULE 复杂度低估 | 2.1 M2 | 中 | M1 末做 spike，先实现最小子集 | TBD |
| 行情 API 限流 | 2.2 M1 / M3 | 高 | 强制 cache-first + 前台 only poll + 多源 fallback | TBD |
| 税务导出合规 | 2.2 M2 | 中 | 顶部固定免责，UI 文案审核 | TBD |
| base currency 切换性能 | 2.3 M3 | 中 | M2 起做 perf bench，提前发现回归 | TBD |
| AI 回滚语义在 v2 协议下不兼容 | 2.5 M2 | 中 | 范围先约束为 v1 实体；§3.1 v2 设计时纳入 | TBD |
| 隐私合规（崩溃上报泄露财务数据） | 2.6 M1 | 高 | 脱敏单测 + PR 模板审计 | TBD |
| 命令面板贡献协议 ergonomics | 2.4 M1 | 低 | 以 1 个 feature 试点 1 周再全量 | TBD |

---

## 5. 待决策清单（M1 启动前需要回答）

- [ ] **D1**: `me/` `more/` 模块的产品定位 → 决定预算入口位置（§1.1 收尾任务交叉影响）。
- [ ] **D2**: 计划交易是否合并入 FIRE → M2 末决策评审，影响 M3 走向。
- [ ] **D3**: 税务导出格式优先级（CSV vs PDF） → 影响 MT-2.2.M2.4 / .5 工作量。
- [ ] **D4**: 崩溃上报 backend：自托管 Sentry 还是 SaaS → 影响 MT-2.6.M1.2 部署成本。
- [ ] **D5**: master-detail 阈值（默认 1024dp）→ 影响 MT-2.4.M2.* 测试覆盖。
- [ ] **D6**: AI profile 是否上传后端做指纹 → 否则 MT-2.5.M1.1 完全客户端实现。

---

## 6. 状态追踪模板

每 Sprint 结束后，PM/Tech Lead 在本节追加一段：

```
### Sprint N（YYYY-MM-DD ~ YYYY-MM-DD）

完成：
- MT-2.1.M1.1 ✅ (#PR-123)
- MT-2.1.M1.2 ✅ (#PR-124)

进行中：
- MT-2.1.M1.3 (50%, blocked on D1)

下 Sprint 计划：
- MT-2.1.M1.5, MT-2.3.M1.1, MT-2.6.M1.1

风险变化：
- 行情 API 限流风险升级为高（Yahoo 上周限流增加）
```

---

## 附：与 roadmap 的关系

- 本文档描述**怎么做**；roadmap §2 描述**做什么 / 为什么**。
- 任何 ticket 的 scope 漂移如果触动 milestone 边界，先更新 roadmap，再更新本文档。
- 每个 ticket 完成后 PR 描述要回链到本文档锚点。
