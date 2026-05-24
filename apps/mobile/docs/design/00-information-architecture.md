# 00 · 信息架构 / IA Contract

> **状态（2026-05-24）**: 当前代码处于过渡态 `Home / Activity / Accounts / Settings`；
> 目标 IA 是 `Today / Activity / Wealth / Plan` + 全局 `Search` / `Settings`。
> 任何新功能在写代码前必须先用 §3 边界规则判定归位。
>
> **怎么读这篇**: §1 是目标蓝图，§2 是过渡现状，§3 是合同核心（必读），
> §7 是迁移计划。审 PR 时引用 §3 的允许/禁止条目作为归位依据。

---

## 1. 目标 IA（合同蓝图）

```
NaviWealth
├── /                       Today      今天要知道什么
├── /activity               Activity   发生了什么
│   ├── /activity/expenses
│   ├── /activity/trade
│   ├── /activity/transfer
│   ├── /activity/journal
│   ├── /activity/ingest
│   └── /activity/dividends         （事件流：已收股息）
├── /wealth                 Wealth     我拥有什么
│   ├── /wealth/accounts
│   ├── /wealth/portfolio
│   ├── /wealth/watchlist
│   ├── /wealth/liabilities
│   ├── /wealth/income-projection   （由资产推导的收入展望）
│   └── /wealth/assets/:id
├── /plan                   Plan       我要去哪 / 怎么调
│   ├── /plan/fire
│   ├── /plan/goals
│   ├── /plan/rebalance
│   ├── /plan/income                （options income 策略）
│   ├── /plan/dca
│   ├── /plan/scenarios
│   └── /plan/projection            （FIRE projection / scenario analytics）
└── /settings               全局偏好（不是主导航场景）
    ├── /settings/devices, /fx-rates, /backup, /sync, /logs
    ├── /settings/ai-history, /ai-privacy, /ai-llm, /ai-transparency
    └── /settings/risk-thresholds, /stress-test, /monthly-expense
```

主导航四个一级目的地（所有断点共享）：

```
Today      /
Activity   /activity
Wealth     /wealth
Plan       /plan
```

**Search / 命令面板**和 **Settings** 不占主导航：

| 元素 | 移动端位置 | 桌面位置 | 承载 |
|------|-----------|----------|------|
| Search / Command | 底栏中槽（现有 `commandIndex = 2`） | 侧栏底部固定 | 跳转 / 命令 / AI 触发 |
| Settings | Today 顶栏右上 avatar/⚙（唯一入口） | 侧栏底部固定 | 偏好 / 数据源 / AI 隐私 / sync |

**AI 不做 tab**：继续以命令面板（Layer 1）+ 行内胶囊（Layer 2）+ `/settings/ai-history`（只读历史）三种形态存在，详见 [`docs/ai-architecture.md`](../../../docs/ai-architecture.md) §5。

---

## 2. 当前状态 vs 目标状态

`apps/mobile/lib/app/route_paths.dart` 当前 (`kPrimaryTabPaths`):

```
Home  /          Activity  /activity   Accounts  /accounts   Settings  /settings
```

主要偏离：

| 偏离 | 现状 | 目标 |
|------|------|------|
| 缺 Plan tab | FIRE / Rebalance / Income / DCA / Analytics 全挂在 `/accounts/*` | 独立 `/plan/*` |
| Accounts 是混合桶 | 账户列表 + Liabilities + 9 个规划/分析子页 | 拆为 Wealth（对象）和 Plan（决策） |
| Settings 是 tab | 占一级槽位 | 降级为全局 meta，从 Today 顶栏访问 |
| 命名 | `Accounts`、`Analytics` | `Wealth`，`Analytics` 拆分到所属对象（见 §4） |

迁移按 §7 分 Phase A / B / C 推进。

---

## 3. 边界规则（合同核心）

每个一级 tab 都有明确的允许/禁止列表。审 PR 时如果一个新功能违反禁止条款，应当被打回重新归位，不允许"先放着以后再说"——那是当前 Accounts 桶的成因。

### Today — 只读运营驾驶舱

- **允许**: 净值、今日/MTD/YTD 变化、到期账单、alert、FIRE 进度 *teaser*、再平衡 *警告 teaser*、AI insight feed、单一 CTA 链出的卡片。
- **禁止**: 编辑目标、改假设、调参数、复杂筛选、模拟器、原始账户/交易列表。
- **规则**: Today 上每张卡片都是"只读 + 一个 CTA 跳真正的家"。永远不在 Today 改参数。

### Activity — 不可变事件历史 + 录入

- **允许**: expense / trade / transfer / convert / journal / ingest / dividends received（已发生的事件）。
- **禁止**: 组合分析、FIRE、再平衡决策、把时间线聚合成"建议"的 UI。
- **规则**: Activity 只回答"过去发生了什么"，所有"未来该怎么办"都属于 Plan。

### Wealth — 拥有的对象 + 当前状态

- **允许**: accounts / assets / holdings / portfolio / watchlist / liabilities / income projection（按持仓推导的收益展望）。
- **禁止**: 目标路径、退休模拟、参数调优、决策 UI。
- **规则**: Wealth 只回答"我现在有什么、值多少"。

### Plan — 决策 + 未来状态

- **允许**: FIRE / goals / rebalance / income strategy / DCA / scenarios / stress test entry / scenario analytics / FIRE projection。
- **禁止**: 原始账户列表、全量事件流、通用偏好页。
- **规则**: Plan 是所有"调参 → 看结果"循环的家。每个决策都有自己的 hub 落地页（hero + sections）。

### Settings — 全局偏好，不是导航场景

- 所有偏好统一在 `/settings/*`，这是唯一家。
- Plan / Wealth hub **可以** deep-link 进 `/settings/<thing>` 提供上下文偏好（例如 Plan FIRE 页右上角 ⚙ 跳 `/settings/stress-test`）。
- **不可以**新建 `/plan/settings` 或 `/wealth/settings` 这种第二套偏好空间。

---

## 4. 命名规则

### "Analytics" 不能做一级菜单名

它在任何信息架构里都会腐烂成新桶。按服务对象拆分：

| 旧 | 新 |
|----|----|
| `/accounts/analytics` | `/wealth/portfolio` 下的 "Portfolio Analytics" section |
| FIRE 投影 | `/plan/projection` 下的 "Scenario Analytics / FIRE Projection" |

### Dividends 歧义消解

两边都出现，但语义不同，命名要区分：

| 位置 | 命名 | 语义 |
|------|------|------|
| Wealth | **Income Projection** | 按持仓推导的预期收益（资产属性） |
| Activity | **Dividends Received** | 已收股息事件流（事件历史） |

### 命名一致性

- 一级 tab 命名是用户心智模型，不是后端模型。所以 `Wealth` 比 `Accounts` 好（涵盖账户 + 持仓 + 负债），`Plan` 比 `Analytics` 好（涵盖目标 + 模拟）。
- 子路由保持英文 kebab-case，路径段反映对象/动作而不是 UI 形态（不要 `list` / `detail` 之类后缀）。

---

## 5. 全局元素

| 元素 | 位置 | 承载 |
|------|------|------|
| AppBar | 页面顶部 | 页面标题、局部操作（局部 ⚙ deep-link） |
| 命令面板 | 底栏中槽（移动） / 侧栏底部（桌面）/ 全局快捷键 | 跳转、主题、语言、AI 触发 |
| `+` 动作面板 | Activity / Wealth 页顶部右侧 | 按场景分桶（事件录入 vs 对象创建） |
| AI 入口 | Search 命令面板 / 页面内 inline capsule | 不做独立 tab |
| Snackbar | 屏幕底部 | 写操作反馈、撤销 |
| Settings | Today 顶栏右上（移动） / 侧栏底部（桌面） | 全局偏好唯一入口 |

`+` 动作面板按场景分桶（已实现）：

- **Activity `+`** = 记录已发生事件：expense / trade / transfer / convert（`activity_action_panel.dart`）
- **Wealth `+`** = 创建拥有的对象：account / cash / deposit / wealth / 实物资产 / liability（`accounts_action_panel.dart`，迁移后改 Wealth）

---

## 6. 路由原则

- 所有业务导航通过 `lib/app/route_paths.dart` 中的常量或 helper，不允许字面量字符串散落在 UI。
- 详情 ID 使用不透明字符串；展示前按路由 helper 编码 (`Uri.encodeComponent`)。
- 列表选择状态使用 query string，例如 `/wealth/accounts?selected=<id>`。
- **过渡期路径必须 redirect，不能 404**（与 §7 之前的旧版本 IA 文档相反——那条"旧路径应 404"的原则已废除）。Phase A 期间 `/accounts/fire` 等旧路径必须 redirect 到 `/plan/fire`，并由测试保护。

---

## 7. 迁移计划

**严格按 Phase 顺序，不要短路 Phase A。**

### Phase A — additive, 零破坏

1. 新增 Plan tab + `/plan` hub 占位页（hub 用 section 列表即可，不写 hero）。
2. 新增 canonical 路由：`/plan/fire`、`/plan/rebalance`、`/plan/income`、`/plan/dca`、`/plan/scenarios`、`/plan/projection`。
3. 新增 `/wealth` 与子路由占位。
4. **保留**旧路径 `/accounts/fire`、`/accounts/rebalance`、`/accounts/analytics`、`/accounts/income`、`/accounts/dca`、`/accounts/dividends` 作为 redirect 到新路径；不删除。
5. 命令面板候选项 + Today 的 FIRE / Rebalance 卡 CTA 改指向 `/plan/*`。
6. 加 redirect 测试（保护 deep link 不断）。
7. 改 `kPrimaryTabPaths` 与 4 个 nav label：`navHome → navToday`、`navAccounts → navWealth`，新增 `navPlan`。`navSettings` 退出 nav，新增 Today 顶栏 ⚙ 入口。

### Phase B — 让 Plan 站稳

- Plan hub 加真正的 hero（例如"距离 FIRE 还有 8 年"）+ section grid 链入 FIRE / Rebalance / Income / DCA / Scenarios。
- Today 的 FIRE 卡降级为纯摘要 + CTA → `/plan/fire`，决策都在 Plan 完成。
- Plan 各子页之间的内部导航打通（FIRE → Scenarios → Rebalance 一条决策链）。

### Phase C — Wealth hub 重写（最重，放最后）

- 现在 `accounts_master.dart` 只是裸 ListView (`lib/features/accounts/ui/accounts_master.dart`)。Phase C 给 Wealth 一个 Net Worth Hero + Accounts / Holdings / Portfolio / Watchlist / Liabilities / Income Projection sections，对齐 Today 的"hero + cards"模板。
- 只在 Plan 边界在真实使用中观察到稳定后再启动 Phase C。

### Phase D — 清理（可选，未来）

- Phase C 上线 + 至少 1 个版本后，再考虑删除 `/accounts/*` redirect。命令面板 / Today 卡 / 测试无任何引用之后才能删。

---

## 8. 新功能归位流程

加任何新功能前，按下表自查：

| 问题 | 答案决定归位 |
|------|-------------|
| 这是状态展示还是决策 UI？ | 状态展示 → Today / Wealth；决策 UI → Plan |
| 它操作的对象是已发生事件还是当前持有物？ | 事件 → Activity；持有物 → Wealth |
| 它需要用户调参数 / 跑模拟吗？ | 是 → Plan；否 → Today / Wealth / Activity |
| 它是全局偏好还是某个对象的配置？ | 全局偏好 → `/settings/*`；对象配置仍走 `/settings/<thing>` + 从 hub deep-link |
| 用户每天都会用 vs 偶尔配置一次？ | 高频 → 一级 tab；低频 → Settings 或子路由 |

如果功能"哪里都能放"，说明边界没想清楚——不要图省事塞进 Plan / Wealth，先和负责 IA 的人对齐。

---

## 9. 此文件与代码的关系

- `lib/app/route_paths.dart` 顶部注释引用本文件作为 IA 权威；如二者冲突，**本文件赢**，请回头改 `route_paths.dart`。
- `lib/app/app_shell.dart` 的 `_navDestinations` 必须与 §1 的四个 tab 一致。
- `lib/core/ai/` 任何新 AI 入口必须满足 §5 的"不做 tab"约束。
- 改本文件应在 PR 描述里说明哪条规则变了，并 ping 任何当前在做导航相关工作的人。
