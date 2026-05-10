# NaviWealth 产品路线图（Roadmap）

> 文档版本：2026-05-10 · 当前应用版本：0.2.5
> 本次更新：扩展 §2 中期规划为 6 个工作流 × 3 个里程碑（M1/M2/M3）的可执行计划。
> 分析基础：仓库现状全量扫描（feature 模块、backend 路由、同步协议、测试覆盖、git 历史 FIR-1 ~ FIR-134）。
> 本路线图是**方向性参考**，不是承诺；优先级会随用户反馈与开发节奏调整。

---

## 0. 当前状态速览

| 维度 | 现状 |
|------|------|
| 平台覆盖 | iOS / Android / Web（PWA 完成，桌面端 Shell 在做：FIR-106） |
| 核心域 | 资产 / 账户 / 投资 / 负债 / 支出 / FIRE / 再平衡 / 分析 / AI 助手 已上线 |
| 同步 | Sync Protocol v1.0 已冻结（轮询 30s，HLC + OpLog + 行级 LWW） |
| 后端 | Cloudflare Workers + D1，路由极简（health/auth/me/sync/ai） |
| 测试 | 62 个 `*_test.dart`，分布不均；E2E sync 框架存在但未落地 |
| 国际化 | en + zh；设计稿提及 ja 尚未支持 |
| 安全 | 原生端 SQLCipher；Web 端为 sqlite3 WASM（弱于原生）；JWT HS256 单用户 |

**优势**：投资模块（35 文件，FIFO/LIFO/avg、FX PnL、税务）、AI 对话（22 文件，SSE 流 + 提案/确认）、分析（集中度风险、基准对比）。
**缺口**：`me/`、`more/` 仅占位；`plan/`、`portfolio/` 是薄壳；活动 Feed 单薄；后端 AI 工具中成本基础是粗略近似；Web 安全与 a11y 自动化空白。

---

## 1. 短期（1–2 个月）— 补完已有功能 / 还技术债

目标：把"已经摆上去但还没做完"的部分收尾，让 0.3.x 系列功能闭环。

### 1.1 补完占位模块
- **`features/me/`、`features/more/`**：当前目录为空，需明确产品定位（个人中心？设置入口？快捷面板？）；与 `settings/`、`activity/` 的边界要画清，避免重复。
- **`features/plan/`**：目前只是路由壳（2 个文件），转发到 FIRE / analytics / rebalance。建议要么做成统一的"理财规划工作台"（goal-driven 视图），要么直接合并入 FIRE，删除该模块。
- **`features/portfolio/`**：作为 `assets/` 的薄包装存在；评估能否合并，或将其升级为"组合视角"（按账户/币种/资产类别多维聚合）。

### 1.2 仪表盘洞察补全
- `lib/features/home/data/dashboard_insights_provider.dart:7` 的 TODO："Add more insights when providers are available"。
- 待 providers 成熟后接入：本月支出/上月对比、净资产周/月变化、风险告警 Top-N、再平衡偏离提醒、AI 生成的每周摘要。

### 1.3 后端 AI 工具落地
- `apps/backend/src/ai/tools.rs`：成本基础（FIFO/LIFO）目前是粗略近似，需把客户端的持仓引擎移植到 Worker，或定义"客户端先算、提案携带证据"的协作协议。
- 跨币种合并：当前未做自动 FX 汇总；要支持多币种组合的总览查询。
- 写入提案 `apps/backend/src/ai/proposals.rs` 的 guardrails 需要补充更细的 schema 校验与冲突回退路径。

### 1.4 活动 Feed（`features/activity/`）
- 仅 4 个 UI 文件 + 1 个 domain 模型，缺少筛选（按账户、按时间、按事件类型）、分页、空状态/加载骨架、跳转到详情。
- 缺 data/repository 层；建议明确：activity 是 oplog 投影还是独立事件流。

### 1.5 Web 端体验补齐
- 备份/恢复：`file_saver_stub.dart` / `file_saver_web.dart` 还是 stub，需走 File System Access API（Chromium）+ 下载兜底。
- 安全：Web 端 sqlite3 WASM 没有 SQLCipher 等价方案；至少加上"敏感字段（密码/TOTP）应用层加密"或显式提示用户 Web 端不存敏感凭证。
- 路径策略：核对 `docs/web-routing.md` 检查清单，确保所有 deep link 都能直达。

### 1.6 测试空白补齐
- 没有测试目录的 feature：`me`、`more`、`plan`、`portfolio`。
- 测试明显偏薄的：`activity`（1 个测试）、`home`（仅 domain 测试，无 widget 测试）。
- 文档（`docs/sync-e2e-manual.md`、CLAUDE.md）提到的 `SyncCluster` / `VirtualDevice` E2E 框架尚未在 `test/features/` 落地，需要至少 3–5 个端到端用例：双设备并发写、离线追赶、墓碑同步、HLC 时钟漂移、冲突 LWW。

---

## 2. 中期（3–6 个月）— 扩展产品能力

目标：把 NaviWealth 从"看 + 记"升级到"规划 + 决策"。
范围：6 个工作流并行，分 3 个月度里程碑串联（M1 = 月 1 末，M2 = 月 3 末，M3 = 月 6 末）。每个工作流独立可发，避免大爆炸 release。

> **任务级执行计划**：见 [`docs/roadmap-midterm-execution.md`](./roadmap-midterm-execution.md) — 每条 ticket 含 size / depends / 文件 / DoD。本节仅描述方向与里程碑。

### 2.0 总览（节奏与里程碑）

| 工作流 | M1（0.4.x，月 1） | M2（0.5.x，月 3） | M3（0.6.x，月 6） |
|--------|-------------------|-------------------|-------------------|
| 2.1 预算与现金流 | 数据模型 + 月度预算雏形 | 计划交易 + 进度/告警 | 现金流瀑布 + FIRE 联动 |
| 2.2 投资进阶 | Watchlist α | 分红/拆股事件流 + 税务导出 | DCA 模拟 + 回测 |
| 2.3 多币种 UI | 金额组件 dual-display | 历史汇率曲线 + 自动拉取 | base currency 全局切换 |
| 2.4 桌面 Shell | 命令面板覆盖 80% 导航 | master-detail 三大模块铺开 | 快捷键帮助页 + 发现性 |
| 2.5 AI 助手 | 用户画像 v0 + 引用证据 | 批量提案 + 回滚 | 长任务进度 + 多轮上下文 |
| 2.6 可观测性 | 崩溃上报 opt-in 上线 | 性能埋点 + 后端告警接入 | 仪表盘 + 周报自动化 |

**串联约束**：
- 2.1 / 2.5 共享"提案"基础设施（计划交易由 AI 生成 → 走 proposal 流程），所以 2.5 的 M1 ≤ 2.1 的 M2 起点。
- 2.3 的 dual-display 是 2.1 / 2.2 报表 UI 的前置（避免重复封装），优先在 M1 完成组件抽象。
- 2.6 的崩溃上报应在 M1 上线，给后续两个迭代提供观测反馈。

---

### 2.1 预算与现金流（新模块 `features/budget/`）

**现状**：仓库内**无任何预算 / 计划交易 / 告警实现**。`features/expense/` 只做实绩录入与月度报表。

**目标产出**：
- `features/budget/`（新建，遵循 ui/data/domain 三层）
- 计划交易引擎（生成虚拟未来交易，写入预测视图，不污染 journal）
- FIRE 模块拉取计划交易作为现金流输入

**阶段拆分**：
- **M1（月 1）— 数据模型与月度预算 MVP**
  - Drift 表：`budgets`（period, category_id, amount_minor, currency, rollover_policy）、`recurring_transactions`（rrule, next_run_at, template_posting_json）。
  - Domain：`BudgetPeriod`、`BudgetProgress`（实绩 vs 预算）；与 `expense_categories` 复用分类系统。
  - UI：月度预算编辑页 + 单卡片进度（先不接 dashboard）。
  - 同步：新增 oplog entity 类型，复用现有 LWW；走 `docs/sync-protocol.md` 添加表流程。
- **M2（月 3）— 计划交易 + 告警**
  - 计划交易调度器（基于 RFC 5545 RRULE 子集：FREQ=MONTHLY/WEEKLY/DAILY、INTERVAL、BYMONTHDAY）。运行时机：进入 budget/home 页面时拉取 due-list；不做后台 push（v1 同步协议不支持，留待 §3.1）。
  - 实时进度条 + 超支预警（dashboard 卡片）。预警阈值默认 80%/100%，可在分类粒度覆写。
  - "下个月将到期"列表（订阅、还款、定投预演）。
- **M3（月 6）— 现金流瀑布 + FIRE 联动**
  - 现金流瀑布图（季度/年度）：起始余额 → 收入 → 各分类支出 → 终值，使用 `design_system/charts`。
  - FIRE 模块从计划交易池拉取定期收支，作为蒙特卡洛输入的确定性骨架。

**验收**：
- 一个家庭月度预算（≥ 12 个分类）从录入到 dashboard 显示进度全程 < 60s 操作。
- 计划交易未来 12 个月的展开 < 200ms（10 条 RRULE 规则）。
- 预算 oplog 在双设备并发编辑下走 LWW 不丢数据（添加到 §1.6 E2E 用例）。

**风险**：
- 预算与 expense 类别耦合，分类重命名 / 删除需级联策略。**对策**：先冻结分类的 `id` 不变 → 任何重命名只改 label。
- 计划交易与"未来仓位预测"是否合并到 FIRE，**M2 末做合流决策评审**，避免 M3 重写。

---

### 2.2 投资进阶

**现状（已具备）**：`features/investment/domain/` 已有 cost_basis 引擎、fx_pnl、tax_policy/jurisdiction_tax_policy、cash_dividend & corporate_actions 模型、holding_report、portfolio_return_service。`data/market/` 有 Yahoo/CoinGecko/Sina + 缓存 + 限流。
**缺口**：UI 端无 watchlist；事件流（分红/拆股）只有模型未串成时间线；税务有数据但无导出；无 DCA 模拟器。

**阶段拆分**：
- **M1（月 1）— Watchlist α**
  - 新增 `features/investment/watchlist/`，复用 `data/market/composite_market_data_service.dart` 的行情通道与限流器。
  - Drift 表：`watchlist_items`（symbol, market, added_at, alert_rules_json）。
  - UI：列表 + 搜索添加 + 简单告警（价格跌破 / 涨破 X，告警通过 `core/logging/crash_reporter.dart` 同链路的本地通知通道展示）。
  - 不做：跨设备告警推送（依赖 §3.1 实时通道）。
- **M2（月 3）— 事件流 + 税务导出**
  - 事件时间线：把 `cash_dividend.dart` / `corporate_actions.dart` 已有数据投影为按持仓的 timeline 视图（已实现盈亏 / 股息 / 拆股 / 配股）。
  - 公司行动录入：拆股 / 配股 / 股息再投资（DRIP）的 trade_entry 入口。
  - 税务导出：基于 `domain/tax/jurisdiction_tax_policy.dart` 输出年度汇总（已实现盈亏 + 股息毛 / 净额）。
    - 格式：CSV（必做）、PDF（可选，复用现有打印渠道）。
    - 涵盖 jurisdiction：US / HK / CN（已有 policy 落地的）；其他显式标注 "policy 未配置"。
- **M3（月 6）— DCA 策略模拟 + 回测**
  - DCA 模拟器：选定 symbol/篮子 + 频率 + 金额 + 时间窗，输出累计收益、平均成本、最大回撤；与 `features/rebalance/` 引擎共享投资组合抽象。
  - 回测数据源：复用 market data cache；缺数据时用最近可用价 + 标注。**不做撮合层**，纯 buy-and-hold 模型。
  - 与 rebalance 联动：把 DCA 计划写入 §2.1 计划交易作为输入。

**验收**：
- Watchlist 30 个 symbol 刷新一次 < 5s（受限速器约束），缓存命中下 < 200ms。
- 税务导出：US 1099-style 关键字段（proceeds / cost basis / gain/loss / wash sale flag occlusion）齐备；与 `cost_basis_engine` 单测交叉验证。
- DCA 回测覆盖 5 年月度数据（60 个采样点）渲染 < 1s。

**风险**：
- 行情 API 限流（Yahoo 经常 429）。**对策**：watchlist 加观察周期（默认 5 min poll，前台才生效），并强制走 `data/market/cache/`。
- 税务导出的合规免责：在导出 PDF 顶部固定免责声明（"本报表仅供个人参考，不构成报税依据"）。

---

### 2.3 多币种与汇率体验

**现状**：`features/settings/fx_rates/fx_rate_sync_service.dart` 已存在；`domain/services/currency_converter.dart` 已统一汇率换算；`data/repositories/fx_rate_repository.dart` 持久化。
**缺口**：UI 端金额展示零散（部分显示原币、部分显示折算、部分仅 base），无历史曲线，base currency 切换需重启。

**阶段拆分**：
- **M1（月 1）— 金额组件 dual-display**
  - `design_system/widgets/money_text.dart`（新建或合并已有 money 组件）：默认显示 base，长按 / hover 切换原币；支持 caption 模式（小字双显）。
  - 全量替换：所有页面金额组件迁移到统一 widget（覆盖 accounts / investment / expense / liabilities / fire / analytics）。
  - Lint 规则（custom analyzer 或 grep PR check）：禁止直接拼接 `.toStringAsFixed` 显示 Money。
- **M2（月 3）— 历史汇率 + 自动拉取**
  - `fx_rate_sync_service` 升级为周期任务（前台 + 进入相关页面时触发），存历史快照（按日，HLC 标记来源 = `auto`/`manual`）。
  - 历史曲线 mini chart（在 settings/fx_rates 页 + 资产折算溢价提示中复用）。
  - 数据源：开放免费 API（exchangerate.host 或 ECB Frankfurter，避免商用 key）；有 fallback；离线读取最后已知。
- **M3（月 6）— base currency 全局切换**
  - 切换 base 不重启 app：所有 provider 监听 `baseCurrencyProvider`，受影响范围（dashboard、analytics、FIRE）触发 rebuild。
  - 后端聚合接口（如有）支持 base currency 参数（目前 sync 是行级 raw，无服务端聚合，纯客户端工作）。
  - 切换时给一次性提示："历史回顾视图将按当前汇率重算" → 选择"快照汇率"还是"当前汇率"。

**验收**：
- 切换 base currency 后 dashboard 在 < 500ms 内完成 rebuild（10k journal entries）。
- dual-display 组件单测覆盖 4 种 locale 下的 RTL / 长货币代码 / 高精度小数。
- 自动拉取在 24h 内至少一次成功的概率 > 99%（带 retry + fallback 源）。

---

### 2.4 桌面端 Shell 完整化

**现状**：`core/command_palette/` 已落地（FIR-87），`app/desktop_sidebar.dart` + `app/master_detail_layout.dart` + `app/shell_preferences.dart` 已存在（FIR-106），`core/shortcuts/` 已有 8 个 shortcut 文件。

**阶段拆分**：
- **M1（月 1）— 命令面板覆盖率达标**
  - 行动清单（高频）：跳转任意账户/资产/投资标的 + "新增交易/支出/账户" + "切换主题/语言/base currency" + "导出报表"。
  - 实现：每个 feature 模块导出 `command_palette_contributions.dart`，bootstrap 时聚合（避免 1 个巨大注册表）。
  - 模糊搜索 + 最近使用排序（持久化在 `shell_preferences`）。
  - 验收：覆盖 ≥ 80% 主导航 + ≥ 90% "新建"动作。
- **M2（月 3）— master-detail 三大模块铺开**
  - accounts、assets、investments 三个列表页在 `≥ 1024dp` 宽度下自动转 master-detail。
  - 详情区独立 router 子路由：URL 可深链到 detail（不破坏 web routing 检查清单）。
  - 列偏好（FIR-106 续作）：每列宽度 + 排序持久化到 `shell_preferences`。
- **M3（月 6）— 快捷键发现性**
  - 帮助页：从 `core/shortcuts/shortcut_bindings.dart` 自动渲染所有绑定 + 当前平台修饰键。
  - 触发方式：`?` 或 `Cmd+/` 打开 cheatsheet（已有 `shortcut_help_dialog.dart` 升级）。
  - 触发面板内联提示：每条 action 末尾显示快捷键（如已有）。
  - 文档：`docs/desktop-shell.md`（新增），列出键位约定与扩展规范。

**验收**：
- 命令面板冷启动渲染 < 100ms（含 200+ 项注册）。
- master-detail 三个模块 deep link 在 web routing 检查清单 100% 通过。
- 帮助页与代码绑定零漂移（`shortcut_bindings_test.dart` 验证一致性）。

---

### 2.5 AI 助手能力升级

**现状**：`features/ai_chat/` 22 文件已上线 SSE 流 + 提案/确认；`apps/backend/src/ai/` 有 anthropic.rs / sse.rs / tools.rs / proposals.rs / guardrails.rs；多 session 已具备但**无用户画像、无批量提案、无回滚**。

**阶段拆分**：
- **M1（月 1）— 用户画像 v0 + 引用证据**
  - 客户端聚合"画像因子"（消费集中度、储蓄率、风险偏好的代理：投资板块/资产类别分布、定期定额情况），作为只读上下文注入 system prompt。
  - **不持久化在后端**：画像每次会话开始时由客户端组装并随首条消息发送（局部计算，避免后端越界）。
  - 引用证据：`tools.rs` 工具返回结果在客户端 UI 中显示"基于这 N 笔交易/这 X 个账户"，链接可跳转。
  - 提案 / 工具卡片复用现有组件，新增 evidence 区块。
- **M2（月 3）— 批量提案 + 回滚**
  - 后端 `proposals.rs` 支持批量提案（一次确认 N 个写操作，原子性走客户端事务）。
  - 客户端"撤销最近 N 个 AI 写入"：从 oplog 标记 `actor = ai_proposal:{proposal_id}` 倒序逆向（生成补偿 op，不直接删 oplog，保持审计）。
  - 撤销窗口默认 24h，超出后需手动定位逐条撤销。
- **M3（月 6）— 长任务进度 + 多轮上下文**
  - 长任务（多步 tool 调用）SSE 中加 `progress` 事件，UI 进度条显示当前步骤。
  - 多轮会话级 memory：轻量级"会话摘要"由模型自维护（每 5 轮压缩一次），存 session 元数据，不上传后端。
  - 工具可视化升级：树形展示 reasoning → tool call → result → next step。

**验收**：
- 画像生成 < 50ms（10k journal entries）。
- 批量提案确认 / 回滚双设备 LWW 一致（E2E 用例）。
- 长任务 SSE 在网络波动下不丢 progress（重连后续传，已有 SSE 基础上加 last-event-id）。

**风险**：
- 用户画像注入可能让 prompt 体积膨胀。**对策**：硬上限 8KB，超出降级（只发"profile_summary_hash"，模型按需用 tool 拉取）。
- 回滚需要 oplog 反向操作语义稳定 → 在 §3.1 解冻 v2 之前，先约束回滚仅作用于 v1 协议范围内的实体（账户、交易、预算）。

---

### 2.6 可观测性与运营

**现状**：`core/logging/crash_reporter.dart` 已有 Sentry 集成 scaffolding（默认不启用，opt-in）；`docs/sync-monitoring.md` 有后端基线但告警通道未配。

**阶段拆分**：
- **M1（月 1）— 崩溃上报 opt-in 上线**
  - Settings 页加"诊断与隐私"区块，**默认关闭**；开启时 Sentry DSN 由 `--dart-define` 注入。
  - 自动脱敏：金额、symbol、自由文本（错误消息只保留类名 + 行号）。明确文档化什么会上传（`docs/observability.md` 新增）。
  - 后端：增加错误响应统一上报到 Cloudflare Analytics（已是免费 tier）。
- **M2（月 3）— 性能埋点 + 后端告警**
  - 客户端关键路径（启动、dashboard 首屏、push/pull 一次往返、AI 首 token）打 Trace；本地保留最近 100 次，opt-in 上传聚合。
  - 后端 `sync-monitoring.md` 列的 SLO 接 Cloudflare Analytics + Email/Slack 告警（push p99 > 2s、err rate > 1%、HLC 偏差 > 5min）。
  - 仪表盘：在 Cloudflare 工作台或一次性脚本拉数据 → Markdown 周报。
- **M3（月 6）— 仪表盘 + 周报自动化**
  - 后端起一个 `/admin/metrics` 路由（JWT 限本人）输出 JSON。
  - 周报生成 GitHub Action：每周一拉取上一周数据 → 生成 issue 评论形式。
  - 前端：开发者菜单加"性能 trace 查看器"（仅 debug build）。

**验收**：
- 崩溃上报有效率 ≥ 90%（崩溃发生 → 后台收到事件，opt-in 用户群）。
- 后端核心 SLO 告警在 SLO 违反 5 分钟内推送。
- 周报自动生成（无手动编辑）。

**风险**：
- 隐私合规：上报内容审计不严会泄露财务数据。**对策**：脱敏函数 + 单测 + PR 模板的"如果触碰上报路径必须列出新增字段"勾选。

---

## 3. 长期（6–12 个月+）— 平台化与差异化

### 3.1 同步协议 v2（解冻）
当前 v1 是轮询 + 行级 LWW，文档 `docs/sync-protocol.md` 已明确以下为 out-of-scope：
- 端到端加密（FIR-31）；
- WebSocket / SSE 实时推送（FIR-33）；
- 字段级 LWW（目前是行级）。
长期需要重新评估：
- **E2EE**：服务端零知识，密钥派生自登录密码 + 设备认证；
- **实时推送**：Cloudflare Durable Objects + WebSocket，把 30s 轮询降到秒级；
- **冲突可读化**：冲突历史给用户可见，必要时提供合并 UI。

### 3.2 多用户 / 协作
当前后端是 single-user JWT，无注册端点。长期方向：
- 家庭账户（共享部分账户、保留私密账户的可见性控制）；
- 财务顾问只读视图（导出加密报表 + 签名链接）。

### 3.3 数据导入生态
- 银行 CSV / OFX / QIF 导入；
- 经纪商对接（从地区开始：美股 IBKR、港股富途、A 股 Tushare/同花顺导出）；
- 支付平台（支付宝/微信账单解析）。

### 3.4 国际化扩展
- 增加 ja（设计稿 §1.4 已提到 textScaleFactor 检查）、zh-Hant、ko；
- 区域化：日期/数字/货币展示按 locale，而不仅是 base currency；
- 货币列表覆盖完整 ISO 4217（目前未审计完整度）。

### 3.5 高级分析
- 因子分析（Beta、行业暴露、地理暴露）；
- Monte Carlo 报表导出（FIRE 已有，需要可分享版本）；
- 与基准（标普、沪深 300、自定义篮子）的对比已有，可加滚动相关性 / 回撤分析。

---

## 4. 跨领域工程项

这些不是单一 feature，但会影响所有功能的可信度。

### 4.1 测试
- **覆盖率**：当前目标 60%（项目）/ 70%（patch），需检查 `me`、`more`、`plan`、`portfolio`、`activity` 是否在 codecov ignore 之外；
- **黄金图测试（visual regression）**：`docs/visual-baseline/` 已有规划（FIR-113），需要在 CI 落地（platform pinned，每个主页面至少 1 个 golden）；
- **E2E sync**：见 §1.6；
- **a11y 自动化**：`docs/design/12-usability-self-check.md §7` 提到引入 `dart_a11y` 或自定义 Semantics 校验器，目前是手工 checklist。

### 4.2 性能
- Web 包体：`docs/web-bundle.md` 有基线，需把 deferred imports 覆盖率写进 CI 阈值（每页首屏 ≤ X KB）；
- 大账户/大持仓场景压测：100k+ journal entries 的 Drift 查询、滚动 + 图表渲染基准；
- 启动时间：冷启动 → 仪表盘可交互的预算（目标：原生 < 1.5s，Web < 3s）。

### 4.3 可访问性 & 可用性
- Semantics labels 全量审计（特别是图表、自定义手势区）；
- 触达区 ≥ 44×44dp 自动校验；
- 文字缩放至 130% / 150% 不破版（设计稿要求）。

### 4.4 安全
- Web 端敏感数据存储模型重审（见 §1.5）；
- JWT 刷新窗口、设备撤销链路压测（已有 FIR-29/30/37 基础）；
- 依赖审计：`security.yml` 已周扫 + 锁文件变更触发，可加 SBOM 产出。

---

## 5. 已知技术债

| 债务 | 文件/位置 | 影响 |
|------|----------|------|
| Backend 成本基础粗略近似 | `apps/backend/src/ai/tools.rs:34-39` | AI 提案对成本基础类问题的回答可能与客户端不一致 |
| Web 端弱于原生的存储加密 | `core/db/connection_*.dart` | Web 端不应承诺与原生同等的安全等级 |
| `me/` `more/` 空目录 | `lib/features/me/`、`lib/features/more/` | 占位含义不明，影响新人理解 |
| `plan/` `portfolio/` 薄壳 | `lib/features/plan/`、`lib/features/portfolio/` | 模块边界与 FIRE/assets 重叠 |
| 单一后端路由表无 domain endpoint | `apps/backend/src/routes/` | 所有非 sync 查询走 oplog 物化，未来扩展可能撞瓶颈 |
| Activity Feed 缺 data 层 | `lib/features/activity/` | 难以扩展过滤/分页/事件类型 |

---

## 6. 明确不做（Out of Scope，至少近 6 个月）

- 加密货币交易撮合 / DEX 对接（仅作为持仓资产呈现）；
- 社交化（晒账本、跟单）；
- 信贷 / 借贷撮合等金融业务（合规风险）；
- 自托管后端打包（Cloudflare Workers 是当前唯一目标）。

---

## 7. 优先级排序（建议）

按"价值 / 完成度"两个维度，建议下一阶段优先做：

1. **【收尾】** 补完仪表盘洞察 + activity feed → 用户每日打开就能看到的体验提升 (§1.2 / §1.4)
2. **【收尾】** `me`/`more`/`plan`/`portfolio` 的产品定位决策 + 合并或落地 (§1.1)
3. **【拓展 / M1】** 多币种 dual-display 组件 → 是 §2.1 / §2.2 报表 UI 的前置（§2.3 M1）
4. **【拓展 / M1】** 预算与现金流模块 MVP → 当前最显著的产品空白（§2.1 M1）
5. **【基础 / M1】** 崩溃上报 opt-in 上线 → 给后续两个迭代提供观测反馈（§2.6 M1）
6. **【基础】** E2E sync 测试 + visual regression 上 CI → 让后续大改不再心虚（§4.1）

剩余项可在 §1–4 的 backlog 中按 FIR 编号细化跟踪。中期 §2 的详细分解见每个工作流下的 M1/M2/M3 拆分。

---

## 附：与现有文档的关系

- 本文档是**方向**；具体实现细节看 `docs/sync-protocol.md`、`docs/web-routing.md`、`docs/visual-baseline/`、`apps/mobile/README.md`。
- 任务级别跟踪走 FIR-XXX 编号（见 CLAUDE.md 中的引用方式）。
- 路线图调整请提交 PR 同时更新本文件顶部的"文档版本"。
