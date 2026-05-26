# HealthOS 域 SSOT

> Phase D 第一个第二域。**本文档在 Phase D-1 shell 落地后正式填充**;当前为骨架 + scope 锁定。
>
> 上位文档:`lifeos-shell.md` (跨域基础设施) + `lifeos-decision-2026-05-24.md` (启动 ADR)。

---

## 0. 状态

**当前阶段**: D-2.1 已落地 (2026-05-26)。D-1 shell foundation 7 项全部完工 (D-1.6/D-1.6b 同日合并),D-1.8 的 UI dock 等 D-2 第二域真正运行后激活。

D-2 子阶段进度:

- ✅ **D-2.1 域骨架 + Drift tables** (2026-05-26) — `health_metrics` 表 (schema v18) + `HealthMetric` Freezed 实体 + `HealthMetricKind` 枚举 + `HealthMetricRepository` (upsert / listByKind / watchRecent / findById) + 7 个仓库测试通过
- ⏳ D-2.2 HealthKit / Health Connect 适配
- ⏳ D-2.3 IA 接入(shell §3 决定的 domain shell 形态)
- ⏳ D-2.4 AI tools (read-only) + Memory Layer 第二个 caller
- ⏳ D-2.5 第一个 cross-domain agent (Morning Briefing)

---

## 1. Scope

**包含**:

- 睡眠 (sessions / 阶段 / 时长)
- HRV / RHR / 静息心率趋势
- 步数 / 活动卡路里 / 训练负荷
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
| iOS | HealthKit | read-only;按日 / 按 session 聚合 |
| Android | Health Connect | 同上 |
| Web | — | **不支持**(local-first;Health 不上 web) |

**不主动上传到 backend**。默认本地。用户在 Settings 显式开启 Health domain opt-in 后,走 `health:*` row family 同步。

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
- 域实体 `HealthMetric` (Freezed) 在 `features/health/domain/health_metric.dart`,内嵌 `SyncMeta` (跨域 sync 信封,northstar §2.4 已知例外:`SyncMeta` 当前住在 `features/finance/data/domain/`,待 D-1.x 后迁到 `core/sync/`)

---

## 4. AI tools (D-2.4 落地)

**Read tool 优先,无 write tool**(健康数据隐私敏感,不让 AI 改):

- `get_recent_sleep_summary` — 最近 N 天睡眠时长 / 阶段分布
- `get_hrv_trend` — 30 / 90 天 HRV 趋势
- `get_activity_summary` — 步数 / 卡路里 / 训练负荷
- `get_recovery_signal` — 综合恢复评分(基于 HRV + 睡眠 + RHR)

位置:`features/health/ai_tools/`。注册到 `DeviceToolRegistry` (shell §7.1)。

**不做** (MVP):

- AI 写健康数据
- AI 自动训练计划生成(超出 MVP scope)
- 真实时检测(MVP 是日级聚合)

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

## 7. Memory Layer 接入

Health 域作为 Memory Layer 第二个 caller(shell §6):

- 每日 sleep summary / HRV 趋势作为 `MemoryEntry` (sourceTable=`'health:summary_daily'`) 写入
- AI Chat 跨域检索时拉历史相似时段

Shell §6 contract 保持中立,无 health-specific 字段。

---

## 8. 第一个 cross-domain agent: Morning Briefing (D-2.5)

每日凌晨 / 早晨 autonomous run:

- **读**: 隔夜市场(Finance)+ 昨日睡眠 + 今日 HRV(Health)
- **产**: 一条 push notification + Today 顶部卡片
- 架构: `core/ai/agents/scheduled_agent.dart` + 各域 `DomainContextProvider`
- 这是 roadmap §4 M-2 BatchProposal + long-task progress 的真实首个 use case

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
