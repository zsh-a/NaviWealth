# Phase 1 详细 Spec — 收尾与还债（1–2 个月）

> 文档版本：2026-05-08 · 配套 [roadmap.md](./roadmap.md) §1
> 目标版本窗口：0.3.0 – 0.3.x
> 阅读对象：实现这些工作的开发者；每个条目可以独立拆出 PR。

## 核对修正（与 roadmap §1.1 的差异）

实际仓库现状（`lib/app/route_paths.dart:99-104`）显示主 tab 是 Home / Portfolio / Activity / Plan。所以：

- **`portfolio/`**（`portfolio_page.dart` 24 行）：是 Portfolio tab 容器，包了 `AssetsPage`。**不是要删除的薄壳，是需要扩展能力的 tab**。
- **`plan/`**（`plan_page.dart` 20 行 + `ui/plan_overview.dart`）：是 Plan tab 容器，承载 FIRE/Analytics/Rebalance 三个子入口。**已是合理结构**。
- **`me/` 与 `more/`**：完全空目录，未在路由中出现。**这两个才是真正的死目录**。

下文 spec 按此现状校正。

---

## 索引

| ID | 标题 | 优先级 | 估算 |
|----|------|--------|------|
| P1-A | 清理空目录 me/ 与 more/ | P0 | 0.5d |
| P1-B | Dashboard Insights 扩展（4 类洞察） | P0 | 3d |
| P1-C | Activity Feed 数据层 + 过滤/分页 | P0 | 4d |
| P1-D | Portfolio Tab 升级（多视角聚合） | P1 | 5d |
| P1-E | 后端 AI 工具补全（持仓引擎对齐 + 跨币种） | P1 | 6d |
| P1-F | Web 备份/恢复完成 + 安全提示 | P1 | 3d |
| P1-G | E2E sync 测试落地（最小集合 5 例） | P1 | 4d |
| P1-H | 测试覆盖空白补齐（home / activity / portfolio） | P2 | 3d |

合计 ~28 个工作日，按 1 人 estimate；可并行（A/B/C 一组，D/E 一组，F/G/H 一组）。

---

## P1-A · 清理空目录 me/ 与 more/

**问题**：`lib/features/me/` 和 `lib/features/more/` 为空目录，未在 `route_paths.dart`、`router_builder.dart`、`app_shell.dart` 中出现。新人 onboarding 时会困惑。

**决策**：直接删除。今后如果要做"个人中心"或"更多入口"，与已有的 `settings/` 合并扩展即可——目前的 4-tab IA（Home/Portfolio/Activity/Plan + 右上 Settings 入口）足够清晰。

**改动**：
- 删除 `apps/mobile/lib/features/me/`
- 删除 `apps/mobile/lib/features/more/`
- 检查全仓库无任何引用（`grep -r "features/me\|features/more" apps/mobile/lib`）

**验收**：`flutter analyze --fatal-infos` 通过；`flutter test` 通过。

**风险**：低。如果 git 历史里这两个目录是有意保留的占位（例如某个未合并的 PR），需要先与团队确认；已经搜过路由表无引用，但 PR 描述中提一下"如果有正在做的相关分支请同步"。

---

## P1-B · Dashboard Insights 扩展

**现状**：`lib/features/home/data/dashboard_insights_provider.dart:41-44` 有明确 TODO，目前只展示 FIRE 一条洞察。

**目标**：仪表盘 InsightStrip 在数据齐备时展示 1–4 条洞察，覆盖以下 4 类：

### 1. Portfolio drift（再平衡偏离）
- 数据源：`features/rebalance/data/` 的 `RebalanceEngine` / 当前 active scheme。
- 触发：任一资产类别偏离目标 ≥ 阈值（默认 5pp，可在 settings 调整）。
- 文案：`组合偏离 · {topClass} +/- {n}pp` → 跳转 `AppRoutes.planRebalance`。
- 需要新增 `rebalanceDriftInsightProvider` 在 `features/rebalance/data/`，返回 `Option<DriftSummary>`。

### 2. Upcoming deposit maturities（定期存款临近到期）
- 数据源：`features/assets/` 中 deposit 类资产 + 到期日字段（已存在于 deposit form）。
- 触发：14 天内将到期的定期存款。
- 文案：`{count} 笔定期 {days}d 内到期`，多笔时取最近一笔的天数 → 跳转资产列表过滤到 deposit。
- 需要 `depositMaturityInsightProvider` 在 `features/assets/data/`。

### 3. Expense trend anomaly（支出异常）
- 数据源：`features/expense/domain/` 已有月度聚合。
- 触发：当月已发生支出 vs. 过去 3 个月同期投影偏差 ≥ 25%（按当前到月底的天数比例外推）。
- 文案：高于阈值时 `本月支出预计 +{n}%`（warning 色），低于时 `本月支出预计 -{n}%`（neutral）。
- 需要 `expenseAnomalyInsightProvider` 在 `features/expense/data/`。

### 4. FIRE（已有）
- 现有逻辑保留；调整 label 文案与 i18n 化（当前是硬编码英文 `'FIRE'` / `'Goal reached!'` / `'to go'`）。

### 通用规则
- Provider 失败/loading 时**静默跳过**，不阻塞 strip 渲染。
- Strip 顺序固定：FIRE → Drift → Maturity → Anomaly（稳定，避免抖动）。
- 每条 insight 必须可点击跳转到对应详情页。
- i18n：所有文案通过 `app_en.arb` / `app_zh.arb` 走，不留硬编码字符串。

### 文件改动
- 修改：`lib/features/home/data/dashboard_insights_provider.dart`
- 新增：`lib/features/rebalance/data/rebalance_drift_insight_provider.dart`
- 新增：`lib/features/assets/data/deposit_maturity_insight_provider.dart`
- 新增：`lib/features/expense/data/expense_anomaly_insight_provider.dart`
- 修改：`lib/l10n/app_en.arb`、`app_zh.arb`（新增 ~12 条 key）
- 修改：`lib/features/home/ui/insight_strip.dart`（如果需要点击跳转支持）

### 验收
- 4 类 insight 在有数据时正确展示；无数据时静默；
- 每条点击跳转目的地正确；
- 单测：每个新 provider ≥ 3 个 case（有数据/无数据/边界）；widget 测试覆盖 strip 渲染顺序。

---

## P1-C · Activity Feed 数据层 + 过滤/分页

**现状**：
- `lib/features/activity/data/` 是空目录；
- `activity_feed.dart` 直接消费 `journalEntriesWithPostingsStreamProvider`（journal 仓储的全量流）；
- 无过滤、无分页、无空态变体。账户多/历史长时性能堪忧。

**目标**：把 ActivityFeed 升级为可用的"流水时间线"。

### 数据层
新增 `lib/features/activity/data/activity_feed_query.dart`：

```dart
@freezed
class ActivityFeedQuery with _$ActivityFeedQuery {
  const factory ActivityFeedQuery({
    @Default(null) DateTimeRange? dateRange,
    @Default(<String>{}) Set<String> accountIds,
    @Default(<ActivityKind>{}) Set<ActivityKind> kinds, // expense/transfer/trade/adjust/...
    @Default(50) int pageSize,
  }) = _ActivityFeedQuery;
}
```

新增 `activityFeedProvider`（`AsyncNotifierProvider`，遵守 `ConventionalAsyncNotifier`）：
- 接受 query；
- 内部仍走 `journalEntryRepository`，但增加 SQL where + LIMIT/OFFSET（或 keyset pagination by HLC timestamp）；
- 暴露 `loadMore()`、`refresh()`、`mutateQuery()`。

> **优先选 keyset pagination**（按 `(date, hlc)` 倒序、用最后一行作为游标），offset 在大数据量下慢且不稳定。

### UI
- AppBar 增加 filter 图标 → 弹出 BottomSheet（移动）/ Popover（桌面），多选 account + 多选 kind + 日期区间；
- 列表底部 sentinel 触发 `loadMore()`；
- 空态：未筛选 vs. 筛选后无结果两种文案；
- 滚动到底"已加载全部"提示。

### 文件改动
- 新增：`lib/features/activity/data/activity_feed_query.dart` + `.freezed.dart`
- 新增：`lib/features/activity/data/activity_feed_provider.dart`
- 修改：`lib/data/repositories/journal_entry_repository.dart`（如需要新增 query 方法）
- 新增：`lib/features/activity/ui/activity_feed_filter_sheet.dart`
- 修改：`lib/features/activity/ui/activity_feed.dart`（接 provider，加分页 sentinel）
- 修改：`lib/l10n/app_en.arb`、`app_zh.arb`（新增 filter UI 文案）

### 验收
- 5k+ journal entries 滚动流畅（profile 模式 frame time ≤ 16ms p95）；
- 筛选条件持久化到 URL query string（go_router 已支持），刷新页面后保留；
- 测试：`test/features/activity/` 至少新增 3 个测试（数据层 query、分页边界、过滤 UI 交互）。

---

## P1-D · Portfolio Tab 升级（多视角聚合）

**现状**：`lib/features/portfolio/portfolio_page.dart` 只是包了 `AssetsPage`。但 Portfolio 作为主 tab，应该提供"组合层面"的视角。

**目标**：在原 AssetsPage 上方加一层"视角切换"：

| 视角 | 内容 |
|------|------|
| 资产列表（默认） | 当前 AssetsPage |
| 按账户 | 按账户分组 + 折叠每个账户内的持仓 |
| 按币种 | 按币种聚合，展示原币 + base currency 折算 |
| 按类别 | 按 asset class 聚合（cash / deposit / wealth / equity / physical / liability 抵扣） |

实现思路：
- 不动 `AssetsPage`；
- 新增 `lib/features/portfolio/ui/portfolio_view_switcher.dart`，segmented control 切换；
- 对应 4 个 view widget：`portfolio_by_asset.dart`（即 AssetsPage）、`portfolio_by_account.dart`、`portfolio_by_currency.dart`、`portfolio_by_class.dart`；
- 每个 view 独立 provider，复用现有 `data/repositories` 数据；
- 视角选择持久化到 `shell_preferences.dart`。

### 验收
- 4 个视角切换流畅，状态持久；
- 单元货币聚合在多币种场景下正确展示原币 + 折算；
- `flutter analyze --fatal-infos` 与 `flutter test` 通过；新增 widget 测试覆盖切换交互。

### 风险
- 与 §2.3（多币种全局体验，见 roadmap）有耦合：如果"按币种"视角先做完整版，会落到 phase 2 范围。**建议 phase 1 只做 by-account 与 by-class，phase 2 一起把 by-currency 升级**——避免做两遍。

---

## P1-E · 后端 AI 工具补全

**现状**（`apps/backend/src/ai/tools.rs` 头部注释明确）：
- `get_holdings` 是"postings 近似读模型"，带 `approximation: true`；
- 跨币种合并被显式延后（"We do *not* fabricate cross-currency totals"）；
- FIR-48 holding engine 未移植到 Worker。

**目标**：让 AI 工具产出与客户端一致的数字，去掉 `approximation: true` 标签。

### 三种实现路径权衡

1. **客户端先算、提案携带证据**（推荐）
   - 客户端把当前持仓快照（带成本基础、币种、FX 折算）作为 conversation context 发给后端；
   - 后端工具直接读 context，而不是从 D1 重算；
   - 优点：不用移植 holding engine，单一计算源；缺点：context 体积、隐私。

2. **将 FIR-48 holding engine 移植到 Worker**（重）
   - 把 `lib/features/investment/domain/` 的 cost basis 引擎用 Rust 重写；
   - 优点：服务端可独立计算；缺点：双实现需要长期对齐。

3. **保持现状，仅在系统提示中告知 LLM "approximation 数字仅供说明，金额请引用客户端给出的"**（最轻）
   - 短期解；不是真正解决。

**建议路径 1**：phase 1 落地。具体做法：
- 客户端在每次会话开始时，向 `/ai/chat` 附带一个 `portfolio_snapshot` field（最近一次成功的 holding 计算结果，schema 与客户端 `Holding` 对齐）；
- `apps/backend/src/ai/tools.rs::get_holdings` 改为先读 snapshot；如果 snapshot 缺失，再走 D1 近似（保留作为 fallback）；
- `approximation: true` 仅在走 fallback 时保留。

### 跨币种合并
- `compute_*` 工具新增 `base_currency` 参数；
- 如果 snapshot 中 holding 已带 base 折算，直接用；否则后端通过 `data/market` 的 FX rate 折算（FX rate 可由客户端 snapshot 一起带过来，或服务端缓存）。

### 文件改动
- 修改：`apps/backend/src/ai/tools.rs` — 增加 snapshot 读取；调整 `compute_*` 跨币种参数。
- 修改：`apps/backend/src/ai/anthropic.rs` — request body 接受 `portfolio_snapshot`。
- 修改：`apps/backend/src/ai/guardrails.rs` — system prompt 更新（不再警告"不能跨币种"）。
- 修改：`apps/mobile/lib/features/ai_chat/data/` — 在请求构造时附带 snapshot。

### 验收
- AI 对"我现在的持仓总值是多少"类问题回答的数字与 dashboard 一致（误差 ≤ 0.01）；
- `cargo clippy --target wasm32-unknown-unknown -- -D warnings` 通过；
- `cargo fmt --all -- --check` 通过；
- 新增集成测试：固定 snapshot input，断言工具 dispatch 输出。

### 风险
- snapshot 体积：5k 持仓量级时 JSON 可能 ~200KB，需要监控 request body 大小；必要时只发 top-N + 摘要。

---

## P1-F · Web 备份/恢复完成 + 安全提示

**现状**：`lib/core/backup/` 有 `backup_codec.dart`、`backup_service.dart`、`providers.dart`，但 web 端的 file save 是 stub（`file_saver_stub.dart` / `file_saver_web.dart`）。

**目标**：
1. Web 端备份导出走 File System Access API（Chromium）+ Blob 下载兜底（Firefox/Safari）；
2. Web 端恢复支持文件上传（`<input type="file">` 走 FileReader）；
3. 在 settings 备份页明确标注"Web 端不存储凭证类敏感数据，导出/导入请使用强密码加密"。

### 文件改动
- 修改：`lib/core/backup/file_saver_web.dart` — 实现 `showSaveFilePicker`（feature-detect）+ Blob 下载 fallback；
- 新增：`lib/core/backup/file_loader_web.dart`（如不存在）；
- 修改：`lib/features/settings/ui/backup_page.dart` — 增加 web 安全提示横幅（仅 `kIsWeb` 时显示）；
- 修改：`lib/l10n/app_en.arb`、`app_zh.arb` — 新增提示文案。

### 验收
- Chrome / Edge：使用原生 file picker 导出；
- Firefox / Safari：Blob 下载兜底正常；
- 上传同样走 feature-detect；
- 在 `web_smoke/` 增加备份导出 + 恢复 happy-path 测试。

### 安全增强（最小可行）
- 备份文件强制密码加密（已有 `backup_codec.dart`，确认 web 端启用相同 codec）；
- Web 端 settings 页加一条 banner："Web 端的本地数据库未启用 SQLCipher，建议不要在 Web 端长期保存敏感账户。"

---

## P1-G · E2E sync 测试落地

**现状**：`docs/sync-e2e-manual.md` 与 CLAUDE.md 都提到 `SyncCluster` / `VirtualDevice` 框架，但 `apps/mobile/test/e2e/` 是否存在需确认；至少 features 目录下没有协议级 E2E。

**目标**：落地 5 个最小可信集合：

| ID | 场景 | 关键断言 |
|----|------|---------|
| E2E-1 | 双设备并发写同一账户余额 | LWW 决出唯一胜方；败方副本被覆盖；oplog 中两条 op 都保留 |
| E2E-2 | 设备 A 离线 1h，期间 B 写入 50 条；A 上线后追赶 | A 最终状态等于 B；同步轮次 ≤ ceil(50/batch_size) |
| E2E-3 | 删除后再创建同 id 资产 | 墓碑不会复活旧记录；新记录正常存在 |
| E2E-4 | HLC 时钟回拨（设备时钟错乱） | HLC 单调性保证；不出现负的 logical 差 |
| E2E-5 | push 失败重试 | 客户端 outbox 不丢；最终一致 |

### 文件
- 新增：`apps/mobile/test/e2e/sync_cluster.dart`（如未存在 harness）
- 新增：`apps/mobile/test/e2e/scenario_*.dart`（5 个文件）
- CI：在 `mobile.yml` 中把 `flutter test test/e2e` 加入 job（独立 step，可 fail-fast）。

### 验收
- 所有 5 个用例稳定通过 100 次（脚本 `flutter test --reporter expanded test/e2e --total-shards 1` × 100）；
- 在 `docs/sync-protocol-tests.md` 中标记哪些 case 已自动覆盖。

---

## P1-H · 测试覆盖空白补齐

按 codecov 60%/70% 阈值，目前空白集中在：

- `features/home/`：缺 widget 测试（仅有 domain 测试）。补：DashboardPage 渲染 + InsightStrip × 4 类 insight 渲染。
- `features/activity/`：仅 1 个测试。配合 P1-C 一起补到 ≥ 4 个（query / pagination / filter / widget）。
- `features/portfolio/`：无测试。配合 P1-D 一起补到 ≥ 3 个（视角切换 / 数据聚合 / 空态）。

不在 phase 1 强制补的（codecov 中应加入 ignore 或暂时降低阈值）：
- `features/me/`、`features/more/` → P1-A 删除后无需测试；
- `features/plan/`：当前只是路由壳，子页面 fire/analytics/rebalance 已有测试，可暂缓。

---

## 跨条目通用规范

1. **每个 PR 必须**：
   - 通过 `flutter analyze --fatal-infos`；
   - 通过 `flutter test`；
   - 后端 PR 通过 `cargo clippy --target wasm32-unknown-unknown -- -D warnings` + `cargo fmt --all -- --check`；
   - 新增字符串都走 ARB（`app_en.arb` + `app_zh.arb`）；
   - 新增 provider 命名 `xxxProvider`；新增常量 `kXxx`。
2. **不在 phase 1 做的**（明确推到 phase 2+）：
   - 多币种全局 UI 体验（仅做 Portfolio by-currency 视角的最小版）；
   - WebSocket 实时同步（保留 30s 轮询）；
   - 预算 / 计划交易模块；
   - 命令面板（FIR-87）。
3. **代码风格**：strict-casts / strict-inference / strict-raw-types；不要新增 `dynamic` / `// ignore`。

---

## 完成判定（Definition of Done for Phase 1）

- [ ] P1-A 至 P1-H 全部 merge 到 main；
- [ ] codecov 项目覆盖率 ≥ 60%（patch 70%）；
- [ ] `flutter build web --release --pwa-strategy=none` 产物大小 vs. v0.2.5 baseline 增量 ≤ +5%（见 `apps/mobile/docs/web-bundle.md`）；
- [ ] 5 个 E2E sync 用例稳定通过；
- [ ] 在 web/iOS/Android 三端各跑一次 happy path 验收（dashboard 加载 → 添加交易 → 查看 activity feed → 查看 portfolio 切视角 → 与 AI 对话 → 备份导出/恢复）；
- [ ] 发布 0.3.0 tag，更新 `roadmap.md` phase 1 章节为 ✅ 状态。

---

## 已知风险与回退

| 风险 | 触发 | 回退方案 |
|------|------|---------|
| P1-E 客户端 snapshot 体积超限 | 持仓 ≥ 5k | 退化为 top-N + 摘要；保留 D1 近似作为 fallback |
| P1-C keyset pagination 在某些 query 下慢 | 多 filter 组合且无索引 | 加 SQLite 复合索引；最坏退化为 LIMIT/OFFSET 但页大小限制 ≤ 200 |
| P1-G 双设备并发用例 flaky | HLC 物理时间敏感 | 用注入时钟（`makeStubStamper`）取代真实时钟；CI 串行执行 E2E job |
| P1-F Web File System Access API 不支持 | Firefox / Safari 现状 | feature-detect → Blob 下载兜底已包含在范围内 |
