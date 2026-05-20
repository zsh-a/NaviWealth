# NaviWealth FIRE OS 计划文档

> 文档版本：2026-05-20
> 关联：[`docs/roadmap.md`](./roadmap.md)、[`docs/ai-architecture.md`](./ai-architecture.md)、[`apps/mobile/docs/design/07-fire.md`](../apps/mobile/docs/design/07-fire.md)
> 定位：把 NaviWealth 从“资产/账本工具”升级为“财务自由状态操作系统”。
>
> 状态（2026-05-20）：Phase 0–5 全部落地；Phase 6（同步）按 §7.1 + 风险表的约束**主动延后**，见 §8 末尾的 FIRE-OS-6.1 决策注。

---

## 0. 一句话目标

FIRE OS 不是帮用户预测资产会不会涨，也不是把 NaviWealth 做成更复杂的记账软件。

它持续回答一个核心问题：

> 我现在的资产、支出、现金桶、健康风险、家庭责任和市场波动，是否还能支撑我想要的自由生活？

产品结果应当从“记录发生了什么”升级到“判断是否安全，并给出下一步行动”。

---

## 1. 产品边界

### 1.1 做什么

FIRE OS 负责：

- 判断当前 FIRE 状态：安全 / 谨慎 / 危险。
- 计算当前提取率、现金桶覆盖月数、FIRE ETA。
- 把账户和资产解释成“现金桶 / 防御桶 / 增长桶 / 风险桶 / 梦想桶”。
- 做压力测试：熊市、支出上升、医疗支出、汇率冲击、现金桶耗尽。
- 生成周期性 Review：每日状态、每周 check-in、每月自由状态报告、季度风险复盘、年度 FIRE Review。
- 通过 AI 解释状态、模拟方案、生成建议、提出需用户确认的结构化修改。

### 1.2 不做什么

第一阶段明确不做：

- 不做全能记账软件。记账是底层能力，不是产品差异化。
- 不做投资预测软件。不预测 QQQ、VOO、A 股或加密资产会不会涨。
- 不做自动交易、自动转账、自动调仓。
- 不过早接入所有银行、券商、保险和健康数据。
- 不把 AI 做成自主理财代理。AI 只做解释、建议、模拟和确认型写入。

### 1.3 产品原则

| 原则 | 含义 |
|------|------|
| 自由度优先 | 资产金额只是输入，自由状态才是输出。 |
| 韧性规划 | 重点回答“跌了怎么办”，不是“会不会跌”。 |
| 行动导向 | 每条 insight 都应能落到保持、调整、补桶、降支出、复盘等行动。 |
| Local-first | FIRE 计算、压力测试、AI context 优先在端侧完成。 |
| AI confirm-only | 所有写入动作必须经过用户确认；外部副作用永不自动执行。 |
| 渐进增强 | 先支持手动录入、CSV、价格手动刷新和简单持仓，再接外部数据。 |

---

## 2. 当前架构承接点

NaviWealth 已具备 FIRE OS 的底层条件：

| 能力 | 当前承接点 |
|------|------------|
| 本地账本 | `journal_entries` + `postings` + `prices` |
| 资产与账户 | `assets`、`accounts`、`liabilities` |
| 经常性交易 | `recurring_transactions` |
| FIRE 雏形 | `apps/mobile/lib/features/fire/` |
| 仪表盘状态 | `features/home/data/dashboard_providers.dart` |
| 现金流聚合 | `features/cashflow/` |
| 投资持仓 | `features/investment/data/providers.dart` |
| 本地 AI runtime | `core/ai/runtime/device/` |
| AI 工具注册 | `device_tool_registry.dart` |
| 同步 | Sync Protocol v1.0，HLC + OpLog + 行级 LWW |

结论：

FIRE OS 应作为现有账本和资产系统之上的解释层实现，不应另起一套事实源。

---

## 3. 目标架构

```text
Drift 本地事实源
  journal_entries / postings / prices / accounts / assets / liabilities
        ↓
Actuals 聚合层
  net worth / holdings / cashflow / recurring / liabilities / prices
        ↓
FIRE State Engine
  FireState / Buckets / StressTests / Reviews / Actions
        ↓
Insight Engine
  daily status / weekly check-in / monthly report / quarterly review
        ↓
AI Copilot
  Explain / Suggest / Simulate / Confirm
        ↓
UI
  FIRE OS page / Home insights / contextual AI bottom sheet
```

### 3.1 核心 read model

新增 `FireState` 作为 FIRE OS 的核心输出。

```dart
class FireState {
  final Money netWorth;
  final Money investableAssets;
  final Money liquidAssets;
  final Money annualSpend;
  final double withdrawalRate;
  final int cashBucketMonths;
  final FireSafetyLevel safetyLevel;
  final List<FireBucketState> buckets;
  final List<FireStressResult> stressTests;
  final List<FireAction> suggestedActions;
}
```

`FireState` 不应直接手工编辑。它由账本、资产、现金流、FIRE 计划和桶规则计算得出。

### 3.2 计划输入

当前 `FireGoal` 只覆盖目标金额、月支出、月结余和通胀率。FIRE OS 需要升级为 `FirePlan`。

```dart
class FirePlan {
  final String id;
  final String baseCurrency;
  final Money annualExpense;
  final double safeWithdrawalRate;
  final double inflationRate;
  final Money targetNetWorth;
  final int targetCashBucketMonths;
  final FireLifestyleMode lifestyleMode;
  final List<FireReserve> reserves;
  final FireRiskSettings riskSettings;
}
```

MVP 可继续使用本地偏好存储；进入多设备同步阶段后，应迁移到 `goals(type=fire)` 或新增 `fire_plans` 同步表。

---

## 4. 领域模块设计

新增或扩展以下模块：

```text
apps/mobile/lib/features/fire/domain/
  fire_state.dart
  fire_state_service.dart
  fire_plan.dart
  fire_bucket.dart
  fire_bucket_allocator.dart
  fire_stress_test.dart
  fire_review.dart
  fire_action.dart
```

### 4.1 FireStateService

职责：

- 读取 dashboard snapshot，得到净值与可投资资产。
- 读取 cashflow summary，估算年化支出。
- 读取 holdings，区分现金、防御、增长资产。
- 读取 recurring transactions，识别未来固定支出。
- 读取 liabilities，计算债务压力。
- 读取 `FirePlan`，计算提取率、现金桶覆盖和安全等级。

### 4.2 Bucket Allocator

桶是解释层，不是账户层。

```dart
enum FireBucketRole {
  cash,
  defensive,
  growth,
  riskReserve,
  dream,
}
```

第一阶段规则可以本地存储：

```dart
class FireBucketRule {
  final String id;
  final FireBucketRole role;
  final String targetTable; // accounts / assets
  final String targetId;
  final double? allocationPct;
}
```

桶输出：

```dart
class FireBucketState {
  final FireBucketRole role;
  final Money currentValue;
  final Money targetValue;
  final double coverageRatio;
  final FireBucketStatus status;
}
```

### 4.3 Stress Test Engine

MVP 压力测试：

| 测试 | 目的 |
|------|------|
| 市场下跌 -20% / -35% / -50% | 判断增长桶回撤后是否仍可维持计划。 |
| 支出 +20% | 判断生活成本上升后的提取率变化。 |
| 医疗/家庭支援一次性支出 | 判断风险桶是否足够。 |
| 汇率冲击 ±10% | 判断跨币种资产对 FIRE 状态的影响。 |
| 现金桶耗尽 | 判断未来几个月是否需要补现金桶。 |

压力测试不预测未来，只检验韧性。

### 4.4 Review Engine

按周期生成结构化 review：

| 周期 | 输出 |
|------|------|
| 每日 | FIRE 状态、现金桶、支出节奏异常。 |
| 每周 | FIRE Check-in、下周支出建议、固定支出提醒。 |
| 每月 | 自由状态报告、提取率、桶偏差、支出偏差、行动建议。 |
| 每季度 | 压力测试、风险登记簿、保险/医疗/家庭支援复盘。 |
| 每年 | 年度 FIRE Review、下一年支出计划、生活模式调整建议。 |

Review 应是 deterministic summary + optional AI explanation，而不是纯 LLM 生成文本。

---

## 5. AI Agent 设计

AI 继续沿用 device-only 架构。后端不新增 `/ai` 路由，不做云端 AI 代理。

### 5.1 AI 能力边界

允许：

- Explain：解释当前 FIRE 状态。
- Suggest：建议补现金桶、降支出、延后旅行、调整目标等。
- Simulate：模拟不同支出、收益率、回撤、半退休收入。
- Confirm：用户确认后写入 FIRE 计划或桶规则。

禁止：

- Predict：预测某资产会涨跌。
- Execute：自动交易、转账、下单。
- Mutate：未经确认自动修改预算、FIRE 计划、桶规则。
- Optimize：黑箱替用户决定生活方式。

### 5.2 新增端侧工具

新增 device tools：

```text
get_fire_state
get_fire_plan
get_fire_buckets
get_fire_stress_tests
get_fire_review
simulate_fire_plan
propose_fire_plan_update
propose_fire_bucket_rule
```

落点：

```text
apps/mobile/lib/core/ai/runtime/device/tools/
apps/mobile/lib/core/ai/contracts/tool_descriptor.dart
apps/mobile/lib/core/ai/runtime/device/tools/device_tool_registry.dart
```

所有 `propose_*` 必须返回 `ProposalEnvelope`，由现有确认通道处理。

### 5.3 Intent 入口

新增 AI intents：

```text
explain_fire_state
review_cash_bucket
simulate_fire_change
explain_stress_test
suggest_fire_actions
```

入口必须经过 `AiIntentInvocation`，默认 bottom sheet，不新增 AI tab。

---

## 6. UI 信息架构

FIRE 页面升级为 FIRE OS 页面。

```text
FIRE OS
├── Hero：自由状态
│   ├── 安全等级
│   ├── 当前提取率
│   ├── 现金桶覆盖月数
│   ├── FIRE ETA
│   └── AI 解释入口
├── Buckets：桶视图
│   ├── 现金桶
│   ├── 防御桶
│   ├── 增长桶
│   ├── 风险桶
│   └── 梦想桶
├── Stress Tests：压力测试
│   ├── 熊市 -35%
│   ├── 支出 +20%
│   ├── 医疗支出
│   └── 汇率冲击
├── Simulations：情景模拟
│   ├── 支出变化
│   ├── 收益率变化
│   ├── 半退休收入
│   └── 旅行预算
└── Reviews：周期复盘
    ├── 月度 Review
    ├── 季度风险复盘
    └── 年度 FIRE Review
```

Home 只展示高信号 insight：

- 当前提取率超过目标。
- 现金桶低于目标月份。
- 熊市测试从安全变为谨慎。
- 本月支出使 FIRE ETA 明显推迟。
- 固定支出上升，年度支出基线被抬高。

---

## 7. 数据与同步策略

### 7.1 MVP：端侧本地计算

MVP 不改 Sync Protocol v1.0。

- `FireState` 动态计算，不落库。
- `FirePlan` 继续用本地偏好存储。
- `FireBucketRule` 本地存储。
- Review 可本地缓存，先不同步。

### 7.2 同步阶段：协议 v1.1

当 FIRE OS 进入多设备正式使用后，再新增同步表。

候选表：

```sql
fire_plans (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  base_currency TEXT NOT NULL,
  annual_expense TEXT NOT NULL,
  safe_withdrawal_rate REAL NOT NULL,
  inflation_rate REAL NOT NULL,
  target_net_worth TEXT NOT NULL,
  target_cash_bucket_months INTEGER NOT NULL,
  lifestyle_mode TEXT NOT NULL,
  risk_settings_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  updated_by_device TEXT NOT NULL,
  hlc TEXT NOT NULL,
  deleted_at TEXT
);

fire_bucket_rules (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  role TEXT NOT NULL,
  target_table TEXT NOT NULL,
  target_id TEXT NOT NULL,
  allocation_pct REAL,
  note TEXT,
  updated_at TEXT NOT NULL,
  updated_by_device TEXT NOT NULL,
  hlc TEXT NOT NULL,
  deleted_at TEXT
);
```

同步接入需要：

- 更新 `docs/sync-protocol.md` 表枚举。
- 新增 backend D1 migrations。
- 新增 Flutter Drift tables。
- 新增 op applier。
- 增加双设备 LWW 测试。

---

## 8. 阶段路线

### Phase 0：设计冻结与现状对齐  ✅ Shipped

目标：不写复杂代码前，先冻结边界。

| ID | 任务 | DoD |
|----|------|-----|
| FIRE-OS-0.1 | 确认 FIRE OS 产品边界 | 本文档合入并在 roadmap 引用。 |
| FIRE-OS-0.2 | 审视现有 FIRE 页面与 provider | 标出可复用 provider 与需替换的模型。 |
| FIRE-OS-0.3 | 定义 `FireState` schema | `features/fire/domain/fire_state.dart` + `fire_state_service_test.dart`。 |

### Phase 1：FIRE State MVP  ✅ Shipped

目标：先让系统能回答“现在是否安全”。

| ID | 任务 | 主要文件 |
|----|------|----------|
| FIRE-OS-1.1 | 新增 `FireState` / `FireSafetyLevel` / `FireAction` | `features/fire/domain/` |
| FIRE-OS-1.2 | 新增 `FireStateService`，接 dashboard snapshot + cashflow | `features/fire/domain/`, `features/fire/data/` |
| FIRE-OS-1.3 | 计算提取率、年度支出、现金桶覆盖 | `features/fire/domain/fire_state_service.dart` |
| FIRE-OS-1.4 | FIRE 页面 Hero 从进度条升级为自由状态 | `features/fire/presentation/` |
| FIRE-OS-1.5 | Home insight 接入高提取率 / 现金桶不足 | `features/home/data/dashboard_insights_provider.dart` |

验收：

- 用户能看到安全等级、当前提取率、现金桶覆盖月数。
- 无 FIRE 计划时有清晰 onboarding。
- 只依赖本地数据，无网络和后端改动。

### Phase 2：桶模型  ✅ Shipped

目标：把“钱在哪里”升级为“钱承担什么角色”。

| ID | 任务 | 主要文件 |
|----|------|----------|
| FIRE-OS-2.1 | 新增 `FireBucketRole` / `FireBucketRule` / `FireBucketState` | `features/fire/domain/fire_bucket.dart` |
| FIRE-OS-2.2 | 默认桶分类规则：现金、短债、股票 ETF、风险储备 | `fire_bucket_allocator.dart` |
| FIRE-OS-2.3 | 桶映射编辑 UI | `features/fire/presentation/` |
| FIRE-OS-2.4 | 现金桶目标月份设置 | `fire_plan.dart`, UI form |
| FIRE-OS-2.5 | 桶偏差 insight | Home + FIRE page |

验收：

- 用户可以把账户/资产分配到桶。
- 现金桶覆盖计算可信。
- 未分配资产被明确标注，不静默忽略。

### Phase 3：压力测试  ✅ Shipped

目标：从“目标进度”升级到“韧性规划”。

| ID | 任务 | 主要文件 |
|----|------|----------|
| FIRE-OS-3.1 | 新增 `FireStressTestEngine` | `features/fire/domain/fire_stress_test.dart` |
| FIRE-OS-3.2 | 实现市场下跌场景 | 同上 |
| FIRE-OS-3.3 | 实现支出 +20% 场景 | 同上 |
| FIRE-OS-3.4 | 实现医疗/家庭支援一次性支出场景 | 同上 |
| FIRE-OS-3.5 | 实现汇率冲击场景 | 同上 |
| FIRE-OS-3.6 | FIRE 页面新增 Stress Tests section | `features/fire/presentation/` |

验收：

- 每个压力测试输出安全等级、影响解释和建议动作。
- 压力测试不调用 LLM。
- 单测覆盖极端输入：零资产、负债高于资产、无现金桶、多币种缺 FX。

### Phase 4：Review System  ✅ Shipped

目标：形成周期性自由状态报告。

| ID | 任务 | 主要文件 |
|----|------|----------|
| FIRE-OS-4.1 | 新增 `FireReview` 模型 | `features/fire/domain/fire_review.dart` |
| FIRE-OS-4.2 | 月度 Review：支出偏差、提取率、桶偏差、行动建议 | `fire_review_engine.dart` |
| FIRE-OS-4.3 | 季度 Review：压力测试与风险登记簿 | 同上 |
| FIRE-OS-4.4 | 年度 Review：下一年支出计划与生活模式 | 同上 |
| FIRE-OS-4.5 | Review 历史本地缓存 | Drift local-only table 或 SharedPreferences |

验收：

- Review 可重算，结果确定性。
- AI 只负责解释已计算出的 review，不直接编造指标。
- Review 中每条建议都有数据来源。

### Phase 5：AI Copilot  ✅ Shipped

目标：把 FIRE OS 变成可解释、可模拟、可确认修改的 AI-native 体验。

| ID | 任务 | 主要文件 |
|----|------|----------|
| FIRE-OS-5.1 | 新增 `get_fire_state` tool | `core/ai/runtime/device/tools/` |
| FIRE-OS-5.2 | 新增 `get_fire_buckets` / `get_fire_stress_tests` tools | 同上 |
| FIRE-OS-5.3 | 新增 `simulate_fire_plan` tool | 同上 |
| FIRE-OS-5.4 | 新增 `propose_fire_plan_update` | ProposalEnvelope |
| FIRE-OS-5.5 | 新增 `propose_fire_bucket_rule` | ProposalEnvelope |
| FIRE-OS-5.6 | 注册 FIRE intents | `core/ai/intent/intent_policy.dart` |
| FIRE-OS-5.7 | FIRE 页面接入 contextual AI bottom sheet | `features/fire/presentation/` |

验收：

- AI 能解释 FIRE 状态并引用工具结果。
- AI 能模拟“支出提高 / 降低 / 半退休收入 / 熊市”的结果。
- AI 写入 FIRE 计划或桶规则必须显示 diff 并由用户确认。
- Web 无 AI 时正常降级。

### Phase 6：同步与多设备  ⏸ Deferred (see FIRE-OS-6.1 decision note)

目标：让 FIRE OS 配置可在多设备一致。

| ID | 任务 | 主要文件 |
|----|------|----------|
| FIRE-OS-6.1 | 决策：复用 `goals` 还是新增 `fire_plans` | design note |
| FIRE-OS-6.2 | Sync Protocol v1.1 草案 | `docs/sync-protocol.md` |
| FIRE-OS-6.3 | Flutter Drift 表和 migration | `data/db/` |
| FIRE-OS-6.4 | Backend D1 migration + materialise | `apps/backend/migrations/`, `apps/backend/src/sync/` |
| FIRE-OS-6.5 | 双设备 LWW 测试 | mobile + backend tests |

验收：

- 两台设备修改 FIRE plan 后按 HLC LWW 一致。
- 桶规则删除使用 tombstone，不硬删。
- 本地旧偏好可一次性迁移到同步表。

#### FIRE-OS-6.1 决策注（2026-05-20）：MVP 阶段不开 Phase 6

**结论：** 新增独立的 `fire_plans` 与 `fire_bucket_rules` 同步表 —— 但**不**在 MVP 阶段落地。

**为什么不复用 `goals(type=fire)`：** `goals` 表为单字段 KV 设计，FIRE 计划已演化为含
`safe_withdrawal_rate / target_cash_bucket_months / lifestyle_mode / reserves[] /
risk_settings{}` 的多字段聚合体。挤进 KV 会把 schema 演化挪到 JSON 解码层，丢失 D1
端 schema-aware 索引和 materialise 检查的好处。

**为什么 MVP 阶段不落地（即使决策已定）：**

- **§7.1 明确：MVP 不改 Sync Protocol v1.0。** Phase 1–5 已完全跑在本地偏好之上，
  无任何协议变更；Phase 0–5 的所有承接点（fire_goal_preferences /
  fire_plan_preferences / fire_bucket_rules_preferences /
  fire_review_cache）都使用 SharedPreferences，没有任何同步路径上的 dirty。
- **§10 风险表第六行：** 「同步协议过早复杂化｜MVP 不改协议，等本地模型稳定后再
  进入 Phase 6」。在多设备实际触发不一致体验前推送协议变更，会无谓抬升 v1.1 的
  设计代价并冒着 backend op-applier 漂移的风险。
- **§3 / §7.2 已草拟的表结构** （`fire_plans`、`fire_bucket_rules`）保留为未来一次性
  迁移的目标 schema —— MVP 没有写入与之冲突的状态。
- **触发条件**：当用户开始在多设备使用 FIRE OS 并报告“计划在另一台设备上是旧版”时，
  按 FIRE-OS-6.2 → 6.5 的顺序执行：先冻结 v1.1 草案，再加 Drift 表 + backend
  migration，再加 op-applier 与双设备 LWW 测试，最后一次性把本地 prefs 迁移过去。

**今天可以做的事**（已完成，不阻塞延后）：

- 所有 Phase 5 `propose_fire_plan_update` / `propose_fire_bucket_rule` 走 device
  applier（`features/ai_chat/data/proposal_applier.dart`），写入路径已抽象成
  注入式 writer —— 切换到同步表只需替换 provider 实现，AI 工具与 ProposeCard
  无需改动。

---

## 9. 指标与验收标准

### 9.1 产品指标

| 指标 | 目标 |
|------|------|
| 首次配置 FIRE OS 时间 | < 3 分钟 |
| 用户每周打开 FIRE 页面次数 | >= 2 |
| 用户点击 Home FIRE insight 的比例 | >= 20% |
| 月度 Review 完读率 | >= 50% |
| AI 模拟请求中产生确认动作的比例 | >= 10% |

### 9.2 工程指标

| 指标 | 目标 |
|------|------|
| `FireState` 计算耗时 | 10k journal entries 下 < 500ms |
| 压力测试计算耗时 | < 100ms |
| FIRE 页面首屏 | profile 模式 p95 frame <= 16ms |
| 单元测试覆盖 | Fire domain 核心路径 >= 80% |
| AI tool contract | `./tool/check-tool-descriptors.sh` 通过 |

---

## 10. 主要风险

| 风险 | 对策 |
|------|------|
| FIRE OS 变成复杂记账 | UI 默认展示状态与行动，不把账本细节放首屏。 |
| 用户误以为 AI 在预测市场 | 文案与工具命名只使用 stress / simulate / resilience，不使用 predict。 |
| FIRE 参数过多导致配置困难 | 默认用 3 个必填：年度支出、SWR、现金桶月份；其他高级折叠。 |
| 多币种资产导致错误结论 | 缺 FX 时明确显示 mismatch，不纳入静默计算。 |
| AI 建议过度自信 | 工具结果带来源和假设，AI 输出必须说明假设。 |
| 同步协议过早复杂化 | MVP 不改协议，等本地模型稳定后再进入 Phase 6。 |

---

## 11. 最终形态

最终 FIRE OS 的节奏应是：

每天：

- 更新 FIRE 状态。
- 检查支出节奏。
- 检查现金桶。
- 检查风险事件。

每周：

- 生成 FIRE Check-in。
- 给出下周支出建议。
- 检查固定支出和生活节奏偏离。

每月：

- 生成自由状态报告。
- 更新提取率。
- 检查资产配置和桶偏差。
- 建议是否补现金桶或再平衡。

每季度：

- 跑压力测试。
- 复盘风险登记簿。
- 检查保险、医疗、家庭支援风险。

每年：

- 年度 FIRE Review。
- 生成下一年支出计划。
- 建议是否进入更自由或更防御的生活模式。

最终判断标准：

> NaviWealth FIRE OS 不只是帮用户变得更有钱，而是帮助用户长期保持自由。
