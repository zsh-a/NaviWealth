# HealthOS 域 SSOT

> Phase D 第一个第二域。**本文档在 Phase D-1 shell 落地后正式填充**;当前为骨架 + scope 锁定。
>
> 上位文档:`lifeos-shell.md` (跨域基础设施) + `lifeos-decision-2026-05-24.md` (启动 ADR)。

---

## 0. 状态

**当前阶段**: D-2.1 已落地 (2026-05-26)。D-1 shell foundation 7 项全部完工 (D-1.6/D-1.6b 同日合并),D-1.8 的 UI dock 等 D-2 第二域真正运行后激活。

D-2 子阶段进度:

- ✅ **D-2.1 域骨架 + Drift tables** (2026-05-26) — `health_metrics` 表 (schema v18) + `HealthMetric` Freezed 实体 + `HealthMetricKind` 枚举 + `HealthMetricRepository` (upsert / listByKind / watchRecent / findById) + 7 个仓库测试通过
- ✅ **D-2.4a AI tools (read-only)** (2026-05-27) — 4 个 device tool 落地 (`get_recent_sleep_summary` / `get_hrv_trend` / `get_activity_summary` / `get_recovery_signal`) + 22 个测试通过 + `kHealthDeviceTools` barrel + bootstrap 域级 opt-in gate (`domainOptInsProvider`)
- ✅ **D-2.4b Memory Layer 第二 caller** (2026-05-27) — `HealthMetricMemoryIndexer` 落地:每条 `health_metrics` 行写一个 `EventRecord`(7 种 type:sleep/hrv/steps/rhr/active_energy/weight/body_fat);notable 睡眠会话(< 5h / > 9h / 带 `payloadJson` 注释)额外写 `episodic MemoryRecord` 进 `scope='health'`,带 `short_sleep` / `long_sleep` / `noted_sleep` entity 便于跨域召回。Bootstrap 经 `memory_indexers_bootstrap.dart` 接入;indexer 内部读 `domainOptInsProvider` 域级 opt-in,Health OFF 时不订阅。9 个 indexer 测试通过(event emission 3 + episodic 5 + idempotency 1)
- ✅ **D-2.3 IA 接入(seam + 直链)** (2026-05-27) — `healthDomainShell(l10n)` (3 tabs: Today/Trend/Plan) + `AppRoutes.healthToday`/`.healthTrend`/`.healthPlan` + 3 个 placeholder 页(`HealthPlaceholderPage`)+ `bootstrap.dart` 在 Health 域 opt-in 时 append spec 到 `activeDomainShellsProvider`(`domainDockVisibleProvider` 自动翻 true)+ Settings → LifeOS 域 加 HealthOS 入口直链。3 个 shell-spec 测试通过。**dock UI 渲染**(改 `app_shell.dart` 的 StatefulShellRoute 让 dock 可视)留作 D-2.3b — 当前 Health 页面经 Settings 直链或直接 URL 访问,蚪自己 dogfood 验 Option B 是否顺手再决定全量切换
- ✅ **D-2.5 Morning Briefing agent (programmatic MVP)** (2026-05-27) — `core/ai/agents/{agent,agent_schedule,agent_registry,agent_runner}.dart` 通用框架 + `features/health/agents/morning_briefing_agent.dart` 第一个具名 agent。每日 07:00 (jitter ±5min) 触发,读取过去 24h Memory Layer 跨域 events,程序化合成 sleep/HRV/finance 三段摘要写为 `episodic MemoryRecord` (`scope='*'`,entity `morning_briefing` + dayKey)。Agent runner 通过 `EventRecord` 记录每次运行 (`source='agent_run'`,3 种 type:completed/skipped/failed)。Bootstrap 在 Health opt-in 时注册到 `agentRegistryProvider`。19 个测试通过 (schedule 8 + runner 6 + briefing 5)。**LLM 合成 + 平台原生 cron** 留作 D-2.5b follow-up。
- ✅ **D-2.3b dock UI 渲染** (2026-05-27) — Plan B 双层 shell 落地:外层 `ShellRoute(AppDockShell)` 承担 share-intent / AI route-context / system-back / 域 dock chrome(`domainDockVisibleProvider=true` 时渲染:tablet/desktop 左侧 56dp 竖 dock + tooltip,mobile 顶部 switcher chip 横条);两个内层 `StatefulShellRoute` 各域自洽 —— `features/finance/composition/finance_routes.dart` (4 branches) + `features/health/composition/health_routes.dart` (3 branches),均由通用 `DomainTabsShell` 渲染(消费 `DomainShellSpec`,Finance 走 `showMobileSearchSlot: true`)。删除 `app_shell.dart`,Finance 路由从 `router_builder.dart` 迁出,Health 三条 top-level GoRoute 进 StatefulShellRoute。`kPrimaryTabPaths` 扩 Finance + Health 七条。5 个新 widget test (Finance-only dock 隐藏 / 双域 chip 显示 / desktop dock / `/health` 渲染 / 点击切换) + 既有 3 个 shell-spec 测试通过。**第三个域(TimeOS / Knowledge)接入只需新建 `<domain>_routes.dart`**,outer shell 零改动。
- ✅ **D-2.2 HealthKit / Health Connect 适配** (2026-05-27) — 走 `package:health: ^13.3.1`。`HealthPlatformAdapter` 抽象接口 + `HealthPlatformSnapshot`/`RawSleepSession`/`RawDailyValue`/`RawPointValue` 平台无关数据形状(`features/health/data/health_platform_adapter.dart`)。`_io.dart` 实现走 health 包(iOS:`SLEEP_ASLEEP` + `HEART_RATE_VARIABILITY_SDNN`;Android:`SLEEP_SESSION` + `HEART_RATE_VARIABILITY_RMSSD`;两边 RHR/STEPS/ACTIVE_ENERGY/WEIGHT/BODY_FAT 共用,body fat 自动 PERCENT→fraction `*0.01`);`_stub.dart` web/desktop 返回 not-supported。`dart.library.io` 条件导出 `_factory.dart`。`HealthSyncService` (testable orchestrator):`syncRange({window=30d, from?, to?})` → adapter fetch → 转 `HealthMetric` → `repo.findById` 比内容差异 → 仅在变化时 `MutationStamper.stamp` + `repo.upsert`,**幂等不刷 outbox**(unchanged 不入队)。Stable id 用 `'hk:<type>:<uuid>'` / `'hc:<type>:<uuid>'` 或合成 `'<prefix>:<kind>:<yyyy-mm-dd>'` (daily 聚合)。Settings → HealthOS 加 "Sync from HealthKit / Health Connect" 按钮(请权限→拉数据→显示 "N 新写入 / M 未变 · 拉取 K 项")。iOS:`Info.plist` 加 `NSHealthShareUsageDescription` + 创建 `Runner.entitlements`(用户需在 Xcode Signing & Capabilities 加 HealthKit capability 完成绑定);Android:`AndroidManifest.xml` 加 `READ_STEPS/SLEEP/HEART_RATE_VARIABILITY/RESTING_HEART_RATE/ACTIVE_CALORIES_BURNED/WEIGHT/BODY_FAT` + `ACTIVITY_RECOGNITION` + Health Connect package queries + `ViewPermissionUsageActivity` activity-alias + `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE` intent-filter。`dependency_overrides: device_info_plus: ^13.0.0` 解 health → win32 链冲突。6 个 sync service 测试通过(unavailable / permissions denied / snapshot→rows mapping / 幂等 / value mutation 重写 / explicit from/to)。**iOS 已知 caveat**: SLEEP_ASLEEP 按 segment 发,一晚会出 3–7 行;下游 AI tool 按日聚合所以不破。**未做**:背景刷新 / WorkManager / 写回 HealthKit (§10 反目标) / iOS sleep segment→session 合并。
- ✅ **D-2.6 workoutSession + vo2Max kinds** (2026-05-27) — 扩 `HealthMetricKind` 加 `workoutSession`(wire `workout_session`, unit `s`, `payloadJson` 存 `{activity_type, total_energy_kcal, total_distance_meters}`)+ `vo2Max`(wire `vo2_max_daily`, unit `ml_kg_min`)。Schema 无 migration(`kind` 是 free-text 列)。`HealthPlatformSnapshot` 加 `workouts: List<RawWorkoutSession>` + `vo2Max: List<RawDailyValue>`,`totalCount` 跟着扩。`_io.dart` 走 `package:health` 的 `HealthDataType.WORKOUT`(iOS + Android 共用),`WorkoutHealthValue` 的 energy / distance / activityType 在 boundary 统一换算成 kcal + meters + 小写 activity 字符串。**`vo2Max` 当前 adapter 返回空列表**:`package:health@13.3.1` 没暴露 `VO2_MAX` enum(已查 `flutter pub outdated`,最新版本一致),pipeline 的其它环节(repo / sync / indexer / AI tools / tests)都已通,等 plugin 支持或加 native MethodChannel 时只改 `_io.dart`。`HealthSyncService` 加 `_workoutMetric`(payload 用 `dart:convert.jsonEncode` 稳定序列化,空 payload → null)+ vo2Max 经 `_dailyMetric` 路径,两边都受 `_upsertIfChanged` 幂等保护。Memory indexer 加 `kEventWorkoutCompleted` + `kEventVo2MaxRecorded` 事件 type(无 episodic;模式判断留给 Morning Briefing agent),workout > 60min 时 importance 微抬到 0.6。`get_activity_summary` 加每日 `workout_count` / `workout_minutes` / `workout_distance_km` + summary 三个 workout 总计;`get_recovery_signal` 加 VO₂max sub-score(同 HRV 的 ±20%→±25 分缩放),`inputs.latest_vo2_max` 上 LLM 提示。Android `AndroidManifest.xml` 加 `READ_EXERCISE`(`READ_VO2_MAX` 暂不申请,plugin 没数据通道);iOS `Info.plist` 的 `NSHealthShareUsageDescription` 文案加 "训练 / Workout"。**iOS 部署仍需 Xcode 在 HealthKit capability 把 workout types 勾上**(同 D-2.2 caveat,没 Xcode 自动化)。新增测试:sync (3) + indexer (2) + activity (1) + recovery (1),既有 60 个测试 + 7 个新测试 = 67 个全过,`flutter analyze --fatal-infos` 全项目 clean。
- ✅ **D-2.5b LLM 合成 + 平台 cron + push 通知** (2026-05-27) — `BriefingSynthesizer` 接口 (`features/health/agents/briefing_synthesizer.dart`):`ProgrammaticBriefingSynthesizer` 包装原 D-2.5 静态逻辑;`LlmBriefingSynthesizer` 调用户配置的 `DeviceLlmClient.complete`(Anthropic 或 OpenAI-compatible),system prompt 限制 LLM 只能用结构化输入的数字(不准造数),任何失败(超时/网络/解析)自动 fallback 到 programmatic。`MorningBriefingAgent` 改造为注入 `BriefingSynthesizer` + 可选 `NotificationService`;bootstrap override `morningBriefingAgentProvider` 在 `deviceLlmRuntimeProvider != null` 时注入 LLM synth,否则 programmatic。`memory.outcome.synthesis_source` 字段标 `'llm'` / `'programmatic'`,前端可见。平台 cron 走 `package:workmanager: ^0.9.0+3`:`core/background/{background_scheduler,_io,_stub,_factory,background_callback,providers}.dart` 抽象 + iOS BGTaskScheduler / Android WorkManager 实现 + 顶层 `@pragma('vm:entry-point')` `lifeosBackgroundCallback`(背景 isolate 无 Riverpod,只设 `kMorningBriefingDueAtKey` SharedPrefs flag + 发占位通知)。前台 `pendingBriefingRunProvider` 在 bootstrap cold-start 时读 flag,有就跑 agent(此时有完整 Memory Runtime + LLM)→ agent 写终态通知(替换占位)。`manualMorningBriefingRunProvider` 给 Settings UI "Run Morning Briefing now" 按钮。`morningBriefingCronProvider` 监听 `domainOptInsProvider`,Health ON 注册 periodic task,OFF 取消。本地通知走 `package:flutter_local_notifications: ^18.0.1`,`core/notifications/{notification_service,_io,_stub,_factory,providers}.dart`,Android channel `lifeos.health.briefing`,id `yyyymmdd` 同日去重。Settings → HealthOS 加 "Run Morning Briefing now" 按钮显示上次结果。iOS:`Info.plist` 加 `UIBackgroundModes (fetch, processing)` + `BGTaskSchedulerPermittedIdentifiers ['com.naviwealth.morningBriefing']`;`AppDelegate.swift` import workmanager + `WorkmanagerPlugin.registerBGProcessingTask(...)`(**iOS 部署仍需 Xcode 加 HealthKit capability,见 D-2.2**)。Android:`AndroidManifest.xml` 加 `POST_NOTIFICATIONS` / `RECEIVE_BOOT_COMPLETED` / `WAKE_LOCK`。7 个 synth 测试 (Programmatic 3 + Llm 4) + 既有 5 个 agent 测试 + 5 个 dock 测试通过。**iOS BGTaskScheduler caveats**: ≈15min 最低频率,OS 机会窗触发不保时(写入文档,不是 bug)。**未做**:跨域 agent 编排框架 (单个 Briefing 现已够用)、Today 顶部卡片 UI、用户可配通知时段。

---

## 1. Scope

**包含**:

- 睡眠 (sessions / 阶段 / 时长)
- HRV / RHR / 静息心率趋势
- 步数 / 活动卡路里 / 训练负荷
- Workout sessions(类型 / 时长 / 卡路里 / 距离,D-2.6)
- VO₂max(daily,D-2.6;adapter pipeline 已通,等 `package:health` 暴露 `VO2_MAX` enum 后接通数据)
- 体重 / 体脂(若用户录入)
- 简单饮食标签(若用户录入,可选)

**不包含**:

- 实时心率流(只取 HealthKit/Health Connect 聚合值,不订 raw event stream)
- 血糖(医疗设备依赖,触发性)
- 月经周期(隐私分级 + UI 单独设计,触发性)
- 病历 / 用药记录(超出 personal infrastructure 范畴)

---

## 2. 数据来源

| 平台 | API | 模式 |
|---|---|---|
| iOS | HealthKit (`package:health`) | read-only;按日 / 按 session 聚合 |
| Android | Health Connect (`package:health`) | 同上 |
| Web | — | **不支持**(local-first;Health 不上 web) |

**不主动上传到 backend**。默认本地。用户在 Settings 显式开启 Health domain opt-in 后,走 `health:*` row family 同步。

**D-2.2 接入路径**: `package:health: ^13.3.1` → `HealthPlatformAdapter` 抽象 (`features/health/data/health_platform_adapter.dart`,`_io.dart` 走 native 插件, `_stub.dart` web fallback,`dart.library.io` 条件导出) → `HealthSyncService.syncRange()` 转 `HealthMetric` + `HealthMetricRepository.upsert`(只在内容变化时 stamper + outbox,unchanged 跳过)。手动触发自 Settings → HealthOS → "Sync from HealthKit / Health Connect" 按钮;背景调度在 D-2.5b。iOS Sleep MVP 按 segment 发(同晚会出多行);下游 AI tool 按日聚合所以不破,follow-up 改 segment→session 合并。

---

## 3. Drift schema (D-2.1 定稿,2026-05-26)

实际定义: `apps/mobile/lib/core/persistence/health_tables.dart` (跟 Finance 表共用 `core/persistence/` 是 Drift 单库的约束,不是设计意图;长期目标是按域拆 `features/<domain>/data/db/`,D-1 follow-up)。

```dart
@DataClassName('HealthMetricRow')
class HealthMetrics extends Table with SyncableTable {
  TextColumn get id => text()();                        // UUID PK
  DateTimeColumn get capturedAt => dateTime()();        // session start / day start UTC
  TextColumn get kind => text()();                      // 'sleep_session' | 'hrv_daily' | …
  RealColumn get value => real()();
  TextColumn get unit => text()();                      // 's' | 'ms' | 'bpm' | 'kg' | …
  TextColumn get payloadJson => text().nullable()();    // 阶段直方图 / 平均窗口 / …
  TextColumn get sourceDevice => text().nullable()();
  // SyncableTable mixin → ownerUserId / updatedAt / updatedByDevice / hlc / deletedAt
}
```

- Schema v17 → **v18** (migration 在 `core/persistence/app_database.dart` 的 `onUpgrade if (from < 18)`)
- 索引: `(owner_user_id, kind, captured_at)` 满足"最近 N 天 <kind>"的典型读;`(owner_user_id, hlc)` 跟 Finance 表一致服务 sync 扫描
- Sync row_kind: `health:health_metrics` (D-1.4 row family namespace,触发 sync 时由 D-2.2 adapter 添加)
- 域实体 `HealthMetric` (Freezed) 在 `features/health/domain/health_metric.dart`,内嵌 `SyncMeta` (跨域 sync 信封,2026-05-27 起住在 `core/sync/sync_meta.dart`;`Hlc` / `MutationStamper` / `outboxStoreProvider` 同期上提到 `core/sync/`,Health 域无任何 `features/finance/` import)

---

## 4. AI tools (D-2.4a 已落地 2026-05-27)

**Read tool 优先,无 write tool**(健康数据隐私敏感,不让 AI 改)。位置:`features/health/ai_tools/`。注册:`features/health_ai_tools.dart::kHealthDeviceTools` → bootstrap `deviceToolsProvider` override (仅在 `domainOptInsProvider.contains(DomainScope.health)` 时拼入,Health 默认 OFF)。

| 工具 | 输入 | 输出 | 用途 |
|---|---|---|---|
| `get_recent_sleep_summary` | `days_back` (1–90, 默认 7) | `{from, to, sessions[{started_at, duration_hours, source_device?}], summary{session_count, total_hours, average_hours}, note?}` | 睡眠时长趋势,seconds/min/h 自适应换算 |
| `get_hrv_trend` | `window_days` (枚举 7/14/30/60/90, 默认 30) | `{window_days, from, to, points[{date, hrv_ms}], summary{latest_ms, average_ms, first_half_average_ms, second_half_average_ms, delta_pct}?, note?}` | HRV 序列 + 前后半 delta,< 4 样本时不算 delta |
| `get_activity_summary` | `days_back` (1–90, 默认 7) | `{from, to, days[{date, steps, active_kcal}], summary{total_steps, average_steps, total_active_kcal, average_active_kcal, step_day_count, kcal_day_count}, note?}` | 按日 join steps/kcal,缺一边时另一边返回 null |
| `get_recovery_signal` | 无入参 | `{score (0–100 或 null), verdict (rested/balanced/strained/insufficient_data), inputs{latest_hrv_ms, avg_sleep_hours, latest_rhr_bpm}}` | 综合恢复评分:recent (7d) vs baseline (7–28d) HRV/RHR + 睡眠对 7h 锚点 |

**算法约定**:
- baseline 窗口是 7–28 天前(**排除最近 7 天**),避免近期改善被自己稀释
- 每项子分数 0–100,arithmetic mean → score。HRV/RHR 用 baseline 偏差;sleep 用绝对小时
- score < 40 strained / 40 ≤ score < 70 balanced / ≥ 70 rested
- 基线 < 5 天 OR 最近无任何信号 → `insufficient_data` (模型回避建议)

**不做** (MVP):
- AI 写健康数据
- AI 自动训练计划生成
- 真实时检测(MVP 日级聚合)
- 跨工具复合 prompt 自动判定(Morning Briefing agent 是 D-2.5)

---

## 5. IA placement (D-2.3,等 shell §3 决定)

HealthOS 内部 tabs(在 Option B domain dock 下):

- **Today** — 今日睡眠 / HRV / 恢复信号 + AI 简报
- **Trend** — 周 / 月图表
- **Plan** — 恢复建议 / 负荷调节(MVP 只显示,不自动调度)

共用全局 Settings(Data section 加 Health opt-in)+ Search。

---

## 6. Cross-domain hooks

HealthOS 通过 shell §4 的 `DomainContextProvider` 注册自己,供 cross-domain composition 使用:

- AI Chat 跨域问答(如"我睡眠差的时候交易表现如何")
- Morning Briefing agent (shell §7.3) 同时拉 Finance + Health

**不允许** `features/health/` 直接 import `features/finance/`(northstar §2.1)。

---

## 7. Memory Layer 接入 (D-2.4b 已落地 2026-05-27)

Health 域是 Memory Layer 第二个 caller(shell §6),首个非 Finance 域接入。位置:`features/health/data/health_metric_memory_indexer.dart`。

**Event 发射(每条 row 都发)**:

| `HealthMetricKind` | Event type | Importance |
|---|---|---|
| `sleepSession` | `sleep_session_ended` | 0.7 if outlier (< 5h / > 9h) else 0.5 |
| `hrvDaily` | `hrv_recorded` | 0.55 |
| `rhrDaily` | `rhr_recorded` | 0.55 |
| `stepsDaily` | `steps_recorded` | 0.45 |
| `activeEnergyDaily` | `active_energy_recorded` | 0.45 |
| `weight` | `weight_recorded` | 0.5 |
| `bodyFat` | `body_fat_recorded` | 0.5 |
| `unknown` | (skipped) | — |

事件 ID 格式 `health:health_metrics:<type>:<rowId>` 确保再 indexing 幂等。

**Episodic memory 发射(仅 sleep session 选择性发)**:

| 触发条件 | Entity | Importance | Confidence |
|---|---|---|---|
| 时长 < 5h | `short_sleep` | 0.7 | 0.7(无 note)/ 0.85(有 note) |
| 时长 > 9h | `long_sleep` | 0.6 | 同上 |
| 含 `payloadJson` 注释 | `noted_sleep` | 0.65 | 同上 |
| 普通时长 + 无 note | — | — | — |

`scope='health'`,memory ID `health:health_metrics:episodic:<rowId>`,payload 用 episodic 约定 `{context, decision (null), reasoning (note), outcome{value, unit, duration_hours, shape}}`。

**HRV / 步数 / RHR 等不发 episodic**:这些需要跨多行的模式判断(例如"HRV 连续 5 天下降"),由 D-2.5 Morning Briefing agent 在更高抽象层做,不在逐行 indexer 范围。

**Subscription 形态**:`healthMetricMemoryIndexerProvider` 在 Health 域 opt-in 时订阅 `watchRecent(sleepSession, 60)` + `watchRecent(hrvDaily, 90)`,流变化触发全量 re-index(stable id ⇒ 上游 store 幂等)。OFF 时不订阅,零开销。

Shell §6 contract 保持跨域中立:`EventRecord` / `MemoryRecord` 没有 health-specific 字段;`source` 和 `entities` 是 free-text。AI Chat 调 `build_context` / `query_memory` 时可按 `scope='health'` / `entityFilter={'short_sleep'}` 召回。

---

## 8. 第一个 cross-domain agent: Morning Briefing (D-2.5 落地 2026-05-27)

每日 07:00 local (±5min jitter) autonomous run。**当前**为 programmatic MVP — D-2.5b 会换 LLM 合成 + 平台 cron。

**Read**: `MemoryRuntime.recentEvents(window=24h)` 拉过去一天的 cross-domain events;按 source 分两堆:
- `source.startsWith('health')` → Health 信号 (sleep / hrv / steps / ...)
- `source != 'agent_run' && !startsWith('agent:')` → Finance 信号 (trade_opened / closed / ...)

**Compose** (deterministic, 在 `morning_briefing_agent.dart::synthesize`):
- Sleep: 取最近一条 `sleep_session_ended` event,换算成 hours,如果 indexer 标了 `short_sleep` / `long_sleep` entity 就追加 `(short)` / `(long)`
- HRV: 取最近一条 `hrv_recorded` event 的 ms 值
- Finance: 按 type 计数 ("2 trade opened, 1 trade closed")
- 三段用 ` · ` 拼成 summary

**Write**:
- 一条 `episodic MemoryRecord` (id `agent:morning_briefing:<dayKey>`,upsert 幂等)。`scope='*'` (跨域可被 build_context 召回),entities `{morning_briefing, briefing, <dayKey>}`
- 一条 `EventRecord` (id `agent_run:morning_briefing:<startedAtIso>`) 经 agent_runner 自动写,供"显示最近 agent 运行"surface

**Skip 条件**:
- 24h 内无任何 health event → `AgentRunResult.skipped(reason: 'no health signals')`
- 有 health event 但都是 unknown kind → skipped

**D-2.5b 已落地** (2026-05-27):
- ✅ LLM-driven 合成(`LlmBriefingSynthesizer` 调 `DeviceLlmClient.complete`,system prompt 限制只能用结构化输入数字,失败自动 fallback programmatic;`memory.outcome.synthesis_source` 区分两种来源)
- ✅ Push notification(`package:flutter_local_notifications`,channel `lifeos.health.briefing`,id 按日去重;agent 完成后 `MorningBriefingAgent._maybeNotify`)
- ✅ Background fetch / WorkManager(`package:workmanager`,顶层 `lifeosBackgroundCallback` 设 `kMorningBriefingDueAtKey` flag + 占位通知;前台 cold-start 读 flag 跑完整 agent → 写终态通知替换)

**未做**:
- 跨域 agent 编排框架(单个 Briefing 暂够用,多 agent 时再抽)
- iOS sleep segment→session 合并(同晚 3-7 行 caveat)

**已落地** (2026-05-27, D-2 wrap-up 批次):
- ✅ Today 顶部卡片 UI(`features/health/ui/health_today_page.dart`):读 `latestMorningBriefingProvider`(`recall(source: kMorningBriefingMemorySource)`)渲染最新 briefing summary + 相对时间 + LLM/auto 来源 pill;空态时显示 "Run briefing now" 按钮直接调 `manualMorningBriefingRunProvider`。
- ✅ 用户可配通知时段(`features/health/data/morning_briefing_preferences.dart`):`morningBriefingHourProvider` (0–23,SharedPreferences `lifeos.health.briefing.hourLocal`,默认 7);`MorningBriefingAgent` 接 `hourLocal` 参数,bootstrap override 注入;Settings → HealthOS 加 "Briefing 时间" 行(`showTimePicker` 24h 模式选小时)。背景 workmanager 仍按 OS 窗口触发,hour 主要影响 `AgentSchedule.preferredHourLocal`(in-process tick)+ 用户意图记录。

**架构**: `core/ai/agents/` 通用框架 + `features/health/agents/morning_briefing_agent.dart` 具名 impl。Bootstrap 在 Health opt-in 时 `agentRegistryProvider` append `morningBriefingAgentProvider`。Manual trigger 经 `AgentRunner.runOnce(agent, ctx)`,可从 Settings 触发(follow-up UI)。

---

## 9. 完工标准 (D-2)

- HealthOS 在 dev 自己设备上日常可用 ≥ 4 周
- Morning Briefing 每日自动运行 ≥ 2 周稳定(无 false alarm)
- Memory Layer 跨域查询返回可解释结果(非 noise)
- HealthOS 关闭后 Finance 体验 100% 不变(域级 opt-in 验证)

---

## 10. 反目标

- ❌ 训练计划自动 dispatch(只做建议,不自动改日程)
- ❌ 社交 / 排行榜 / 成就墙(northstar §6.2)
- ❌ 健康数据写回 HealthKit / Health Connect
- ❌ 大数据 ML pipeline(单人维护负担)
- ❌ 医疗诊断 / 用药管理
- ❌ Health 域上 web(MVP 永远不做)
- ❌ 第三方健康设备 SDK 集成(Garmin / Oura / Whoop 等)— 触发性,需用户实际请求

---

## 11. 与 shell 的依赖

| 上游 | 必须先落地 |
|---|---|
| Sync v2 row family namespace (shell §8) | D-1.4 |
| Memory Layer 通电 (shell §6) | D-1.7 |
| Multi-domain IA shell (shell §3) | D-1.8 |
| AI tool 分层 (shell §7.1) | D-1.2 |
| Intent / Trace domain 字段 (shell §7.2) | D-1.3 |
| Auth domain scopes (shell §5) | D-1.5 |
| Cross-feature composition uplift (shell §4) | D-1.6 |

D-1 任何一项未完成,HealthOS 不开始。
