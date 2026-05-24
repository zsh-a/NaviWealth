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

1. **作用域**:只做 FinanceOS。本文档不包含 LifeOS / 多域 shell / HealthOS / TimeOS / LivingOS 的任何 phase。
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
- **Sync**: v1 OpLog + HLC,30s 轮询(v2 row-state 协议已设计,见 `sync-v2.md`)
- **IA**: Today / Activity / Wealth / Plan 已迁移完成(commits aacded4 / 3e37cfc)
- **AI 边界审计**: 2026-05-24 完成,清理 ~4.4k 行 phantom infrastructure

---

## 2. 进行中(Now,~v0.5.3–v0.5.5,2–3 周)

> Phase 1 大部分条目实际上已经完成,仅剩两件事。完成后 v0.5.x 收尾,重心移到 §3。

| ID | 轨道 | 说明 | 来源 |
|---|---|---|---|
| N-1 | AI runtime polish | ✅ 已落地 (2026-05-24):`ToolDescriptor` 4 个新回归测试 + LLM profile model hint 引用 `kDefaultDeviceModel` 常量 | recent commits db1d472 / a5fc6e3 |
| N-2 | E2E sync 5 case 补齐 | ✅ 已落地 (2026-05-24):补足 phase1 P1-G 缺的 E2E-3 / E2E-4 / E2E-5 | `apps/mobile/test/e2e/sync_e2e_test.dart` |
| N-3 | 测试覆盖率提升 | 项目 60% / patch 70%(codecov 目标)。当前主要空白:home widget tests、activity widget tests | [phase1 P1-H](./roadmap-phase1.md) |
| N-4 | Wealth tab "多视角聚合" 重设计 | IA migration 后 Portfolio→Wealth,原 P1-D 多视角(按账户/币种/类别)需要在 Wealth 上重做 | [phase1 P1-D 注记](./roadmap-phase1.md#状态注记2026-05-24) |

> 注 — 以下 phase1 条目在最近的工作中已完成或作废,不再开放:
> - ✅ **P1-A** (`me/`/`more/` 清理) — IA contract migration (commits aacded4 / 3e37cfc)
> - ✅ **P1-B** (Dashboard Insights 4 类) — `InsightKind` 已含全部 4 类
> - ✅ **P1-C** (Activity feed 分页) — `activity_feed_provider.dart` 已支持
> - ❌ **P1-E** (后端 AI 工具补全) — W-D7 删除后端 AI relay 后作废
> - ✅ **P1-F** (Web 备份/恢复) — `features/settings/backup/` 已实现 web/native split
> - ✅ **P1-G** (E2E sync 5 case) — 已在本批落地
>
> 已完成项的详细状态见 [phase1.md 顶部 status 注记](./roadmap-phase1.md#状态注记2026-05-24)。

**Definition of done**: N-3 / N-4 落地或显式 defer 后,Phase 1 关闭,工作完全转入 §3。

---

## 3. 下一程(Next,v0.6.x,8–14 周)

> 必须在 §2 完成或并行启动。**优先级**按下表从上到下。

### 3.1 多币种双显示组件(M1)

> 是 Phase 2 报表的**前置条件**。先做,后面所有金额展示统一基于它。

- ✅ **M1.1 widget 落地** (2026-05-24): `DualMoneyText` 在 `design_system/widgets/money_text.dart`,支持 inline / stacked 两种 layout;同币种自动隐藏 caption;a11y label 整合两个金额。5 个 widget test 覆盖。
- ⏳ M1.2 全量替换调用点 — 当前 codebase 约 118 处裸 `.toStringAsFixed` 显示金额。**作为单独 PR 系列**按 feature 分批迁移,不在本次范围
- ⏳ M1.3 Lint 脚本禁止裸金额显示 — **依赖 M1.2 完成**(否则 CI 直接红)
- 详: [midterm 2.3 M1](./roadmap-midterm-execution.md)

### 3.2 Budget & Cashflow MVP(M1)

> 当前产品最大空白。无 budget 是 FIRE 路径上 cashflow 端的硬伤。

- 月度预算数据模型(`budgets` 表 + repository)
- 现金流预测视图(归位 **Plan tab**)
- 与 FIRE engine 的接口:预算偏差影响 safety level(松耦合 — Budget 写 read-model,FIRE 订阅)
- 详: [midterm 2.1 M1](./roadmap-midterm-execution.md)

### 3.3 Income Planner P4(Wheel/收益周期)

> P0–P3 已完成。P4 是 state machine,纯设备端,**不**触碰后端。

- Wheel 状态机:cash-secured put → 被 assigned → covered call → 被 called → 回到 cash
- 单仓 lifecycle 视图(归位 **Plan tab**)
- AI tool `get_wheel_lifecycle` 只读
- 详: [options-income P4](./options-income.md)

### 3.4 AI Copilot M1: user profile + evidence

> 让 AI 回答时引用本地 trace 证据,而不是凭空生成数字。

- `UserProfile` device tool(读)
- 回复中带 evidence anchor(链到 trace span)
- 详: [midterm 2.5 M1](./roadmap-midterm-execution.md)

### 3.5 Watchlist + Event timeline(M1/M2)

- 投资 tab 的 watchlist 持久化
- Earnings / Ex-div / 财报事件时间线(从 yfinance 抓,缓存)
- 详: [midterm 2.2 M1/M2](./roadmap-midterm-execution.md)

### 3.6 Crash reporting opt-in(M1)

> Phase 2 后续 observability 工作的依赖项。**必须 opt-in**,默认关闭。

- 详: [midterm 2.6 M1](./roadmap-midterm-execution.md)

---

## 4. 中期(Mid,v0.7.x,14–28 周)

> 不预排时间。完成 §3 的 5/6 条目后才启动。

| ID | 轨道 | 说明 |
|---|---|---|
| M-1 | Desktop shell master-detail | 三联 master-detail 完成(macOS / Windows / Linux)。**不**改 IA |
| M-2 | AI Copilot M2 | Batch proposals + undo + 长任务进度条 |
| M-3 | Income Planner P5 | Tradier OAuth + 真 greeks。**Backend proxy 必须 schema-agnostic**,走 `sync_rows`,不在 Worker 里写业务逻辑 |
| M-4 | Investment advanced M2/M3 | Event timeline 完整、tax export(选项见决策门)、DCA simulator |
| M-5 | Performance traces | 观测性 M2 |
| M-6 | Command palette + 快捷键 | Desktop shell M1 + M3 |

---

## 5. 触发性(Triggered,不预排,不写时间)

> 这些**有设计**但**不进开发计划**。只有"触发条件"成立时才动。
> 在触发之前出现"顺手做一点"的 PR,**拒绝**。

| 轨道 | 触发条件 | 设计参考 |
|---|---|---|
| **FIRE OS Phase 6 sync** | 出现 ≥1 例用户报告的跨端 FIRE plan 不一致 | [roadmap-fire-os.md Phase 6](./roadmap-fire-os.md),memory `fire_os_design.md` |
| **Sync v2 切换** | v1 polling 在生产中出现可测量的延迟痛点(>10s 中位数);**或**多设备用户达到 ≥3 个 | [sync-v2.md](./sync-v2.md) |
| **Sync v2 E2EE** | v2 切换完成 ≥1 个月稳定后 | [sync-v2.md](./sync-v2.md) §安全 |
| **Memory Layer 落地** | 至少出现 1 个具名 Finance caller(例如 AI Copilot 需要长期偏好检索) | 北极星 §2.6 |
| **数据导入生态(支付宝/微信/券商对账单)** | 用户实际反馈现有手工录入瓶颈 | [roadmap.md Phase 3](./roadmap.md) |
| **i18n 扩展(ja/zh-Hant/ko)** | 出现非中文用户群 | [roadmap.md Phase 3](./roadmap.md) |
| **多用户/家庭账本** | 用户实际请求 + 设计审 | [roadmap.md Phase 3](./roadmap.md) |

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
- ❌ 写"LifeOS Phase 0–N"路线图(包括本文档不允许的形态)

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

> 不是阻塞,但拖延会让下一程模糊。每条都关联到一个 §3 任务。

| Gate | 关联 | 必须在何时之前决定 |
|---|---|---|
| `me/` 与 `more/` 的最终去留 | §2 N-3 | v0.5.5 发版前 |
| Plan tab 内 FIRE / Budget / Cashflow / Income 的二级 IA(平铺还是分组) | §3.2 / §3.3 | Budget MVP 进入实现前 |
| Tax export 格式优先级(IRS Schedule D / 中国个税 / 通用 CSV) | §4 M-4 | M-4 启动前 |
| Crash reporter 后端(自托管 Sentry / Cloudflare D1 自存 / 第三方 SaaS) | §3.6 | crash reporting opt-in 启用前 |
| Tradier OAuth 的 backend proxy 是否单独 Worker | §4 M-3 | P5 启动前 |

---

## 9. 使用方式

- 排期周会:看 §2(必做)+ §3(优先级);**不**在会上讨论 §5(触发性,无法预排)
- PR review: 触及 `core/` 或新建跨 feature import 时,把 PR 对照 §6 + 北极星 §2 走一遍
- 改本文档前自问:是 §2/§3/§4 的事实推进?还是 §5 的触发条件成立?
  - 都不是 → 不应该改本文档。先去 detail 文档动手
- 本文档目标长度: **< 350 行**(当前在限内)。超出意味着在写 detail,应该回流到 detail 文档
