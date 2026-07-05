# Agent 使用体验统一计划

Status: implementation in progress; core Phase 1-6 surfaces are implemented,
with remaining work tracked as hardening and broader eval coverage.

本文说明如何把现有 agent 架构落成简洁、统一、可解释的用户体验，并列出需要改动的模块。本文不改变现有架构边界：AI 仍然是 device-only，domain 仍通过 `DomainPack` 注册，用户默认不进入一个新的 AI 目的地。

## 目标

Agent 的产品体验应当是：

- 用户在领域页面看到及时、可操作的结果，而不是先打开聊天页。
- 每个 agent 都有一致的状态、运行历史、证据、操作和关闭方式。
- 结果可以追问，但追问通过现有 `askAi()` / `AiIntentInvocation` bottom sheet，而不是新增 `/ai` tab。
- 写入和高风险动作继续走 `ProposalEnvelope`、`deriveInteractionMode()`、undo 和 trace。
- 开发者新增 agent 时只需要在领域内实现逻辑，再通过 `DomainPack` 注册展示、设置和调度元数据。

## 当前基础

现有架构已经具备主要接入点：

| 能力 | 当前入口 | 现状 |
|---|---|---|
| Agent 抽象 | `apps/mobile/lib/core/ai/agents/agent.dart` | 有 `Agent`、`AgentRunResult`、schedule |
| Agent 运行 | `apps/mobile/lib/core/ai/agents/agent_runner.dart` + `agent_run_store.dart` | `runOnce` / `tick` 写入 `AgentRunStore`，调度读取 last non-failed run |
| Agent 注册 | `apps/mobile/lib/app/domain_composition.dart` + `DomainPack.agentBuilder` | active domain scoped |
| Agent 结果 | `apps/mobile/lib/core/ai/agents/agent_artifact.dart` + `agent_artifact_store.dart` | 统一 artifact contract，domain home/settings 可复用 |
| Agent 展示 | `AgentPresentationSpec` + `AgentResultCard` / `AgentRunStatusCard` | DomainPack 贡献展示元数据，UI 不理解 agent 私有 payload |
| Agent 管理 | `apps/mobile/lib/features/settings/ui/agents_settings_page.dart` | 可查看状态、手动运行、打开最近 artifact 和 run history |
| Native runtime | `apps/mobile/lib/app/agent_runtime/` | FRB step runner、tool host、trace recorder 已接入 |
| AI 入口 | `apps/mobile/lib/core/ai/composition/ask_ai.dart` | UI 调用已收敛到 `askAi()` |
| Intent envelope | `apps/mobile/lib/core/ai/intent/ai_intent_invocation.dart` | 有 source / intent / object / domain |
| Proposal 应用 | `apps/mobile/lib/core/ai/composition/` + domain appliers | 已按 active `DomainPack` 聚合 |
| Memory / event | `apps/mobile/lib/core/ai/local/memory/` | Agent 可写 event 和 memory |
| Regression | `apps/mobile/lib/core/ai/regression/agent_outcome_corpus.dart` | 有 agent outcome corpus contract test |

当前覆盖状态：

- `agent.explainResult` / `agent.showEvidence` / `agent.createPlanFromResult` 都已通过 `AgentArtifactDetailBody` 走统一 `askAi()` follow-up 入口，并有 widget test 覆盖 intent、object、context 和 proposal capability。
- Agent artifact 自定义 action 已覆盖通过 action intent / object / payload 进入统一 `askAi()`，防止 domain action 绕过 intent envelope。
- `showAgentArtifactSheet` 已有 compact viewport widget test 覆盖真实 sheet chrome、kind subtitle 和 detail body 渲染，防止领域页打开结果时绕过统一 bottom sheet 或在小屏溢出。
- l10n copy contract 已覆盖 `app_en.arb` / `app_zh.arb` 的可见 message key parity，并按 ARB metadata 验证占位符引用，防止 agent UI / settings 新文案只落单语或参数错位。
- `AgentRunStatusCard` 已覆盖 running / noFinding / ready / failed 四类统一状态，`AgentResultCard` 已覆盖 summary、preview insights、review open action。
- `AgentRunStore` 已有 focused SQLite store 测试覆盖 running row、completed/skipped/failed lifecycle 映射，以及 failed 不推进 last non-failed run。
- Intent policy 已覆盖 active-domain catalog、off-catalog debug assert、以及 asserts-off fallback prompt，确保 agent follow-up 不因未注册 intent 破坏生产兜底。
- Agent artifact detail 已提供 local transparency trace entry，点击后进入 `SettingsRoutes.aiTransparencyDetail(traceId)`；组件测试覆盖 route handoff。
- Agent result read tools 已按当前 domain opt-in 过滤 artifact，inactive domain 的 artifact 不会被 AI follow-up 工具读取或解释。
- Agent artifact store 已覆盖 deterministic artifact upsert 会保留本地 dismissed / snoozed visibility state，防止 agent 重跑把用户关闭的结果重新顶回页面。
- Agent run / artifact / preference 表保持 local-only；sync 和 backup registry 都有负向 contract 防止 agent lifecycle 表进入云同步或备份面。
- Agent settings page 已覆盖 active agent row、notification preference、enabled toggle、Run now manual run、latest artifact 和 run history，确保用户控制入口不与通知偏好混淆。
- Agent settings page 已覆盖 disabled agent 的 Run now 手动触发不可达，确保用户关闭 agent 后不会从设置页绕过偏好继续运行。
- Agent settings page 已覆盖 active registry 为空时的 empty state 和 domain-management CTA，确保 inactive domain 的 agent 不会以不可运行 row 泄漏到用户控制面，同时给用户启用 domain 的路径。
- Production DomainPack composition 已覆盖 active agent registry 与 `AgentPresentationSpec` 的一一对应关系，防止新增 agent 后缺失统一设置/展示元数据。
- Agent background catch-up binding 已声明所属 domain，core runner 会在消费 due flag 后统一拒绝 inactive domain，避免 stale background flag 越过 domain opt-in。
- Knowledge Routine Due 和 Execution Review 的 pending background providers 已覆盖 foreground catch-up 组合路径，验证 due flag 会被消费并以 `background_due` trigger 调用共享 AgentRunController。
- Knowledge Routine Due notification payload 已覆盖只 deep link 到 Knowledge Review 的 agent artifact route，拒绝 chat / external / non-review payload。
- Execution Review 页面已覆盖 latest agent artifact 以统一 `AgentResultCard` 出现在 Review tab 顶部，锁住 ExecutionOS 的 domainReview placement。
- Knowledge Review 页面已覆盖 latest domainReview artifacts 以统一 `AgentResultCard` 出现在 Review tab 顶部，锁住多 agent artifact list 的页面级展示。
- Health Today 页面已覆盖 Morning Briefing、Recovery Alert、Weekly Summary 三类 latest agent artifact 均以统一 `AgentResultCard` 展示，锁住 HealthOS 首页 agent surface。
- Finance Home 的 agent result panel 已有 widget 覆盖，确认 weekly finance artifact 会以统一 `AgentResultCard` 出现在 FinanceOS 首页 placement。
- Finance latest agent artifact provider 已覆盖多 agent 聚合时的 finance domain scope、created_at 排序和 4 条上限，防止其它 domain artifact 或过量历史进入 Finance Home。
- Regression corpus 已覆盖 FinanceOS 首批 agent，校验所有 corpus agent 都有 fixture 文件，并通过 domain-neutral evaluator 接入 Finance / Health / Execution / Knowledge 的真实 agent fixture；`knowledge_routine_due.domain_opt_out` 已接到生产 domain opt-in composition 层面的可执行 no-run eval，`execution.review.budget_exhausted` 已接到真实 runner failed-outcome eval。
- Regression evaluator 已覆盖 ready artifact 的统一 action kind，防止各 domain agent 产出无动作或私有动作模型。
- FinanceOS 首批 deterministic agents 均已接入 `no_llm_profile` corpus case，锁住 Finance agent 在无 LLM profile 时仍可产出本地计算结果的 fallback 契约。
- FinanceOS 首批 agent artifact action intents 已进入 regression evaluator，确保 agent 结果只暴露 review/follow-up action，不绕过 proposal confirmation surface。
- Health Morning Briefing 已接入 agent outcome corpus 和 evaluator，覆盖 briefing artifact 的 insight / evidence / severity contract。
- Health Weekly Summary ready outcome 已接入 agent outcome corpus 和 evaluator，覆盖 weekly review artifact 的 insight / evidence / severity contract；noFinding 仍覆盖 empty-week fixture。
- Knowledge Contradiction ready outcome 已接入 agent outcome corpus 和 evaluator，覆盖 invalidated-assumption alert artifact 的 insight / evidence / severity contract；prompt-injection guard 仍覆盖 noFinding eval。
- Knowledge Review ready outcome 已从 tool-failure fallback case 拆出独立 corpus fixture，正常 due-review 主路径与 FRB failure fallback 分别接入 evaluator。
- Knowledge Assumption 和 Routine Due ready outcomes 已接入 agent outcome corpus 和 evaluator，覆盖 stale assumption 与 due routine artifact contracts。

## 体验模型

### 统一状态

所有 agent 面向用户只暴露以下状态：

| 状态 | 含义 | UI 行为 |
|---|---|---|
| `idle` | 已启用，等待下次运行 | 显示下次运行时间，可手动运行 |
| `running` | 正在同步、读取、调用 runtime 或生成结果 | 显示进度文案，禁止重复运行 |
| `noFinding` | 已运行，但没有值得提醒的内容 | 显示轻量完成状态，可查看历史 |
| `ready` | 有新结果 | 在领域页面显示 Agent Result Card |
| `failed` | 运行失败 | 显示原因、修复动作和重试 |
| `disabled` | 用户关闭或领域未启用 | Settings 中可重新启用 |

### 统一动作

所有 agent 结果最多提供以下动作：

| 动作 | 说明 |
|---|---|
| `Run now` | 手动立即运行 |
| `Review` | 打开统一 Agent Detail Sheet |
| `Ask follow-up` | 通过 `askAi()` 打开当前对象语义的 bottom sheet |
| `Apply proposal` | 通过既有 proposal confirmation surface |
| `Open object` | 跳转到 evidence / affected entity |
| `Snooze` | 延后本次结果 |
| `Dismiss` | 关闭本次结果，不删除历史 |

## 新增核心契约

### AgentRunStore

新增 domain-neutral 持久化 store，记录运行状态和调度所需元数据。

归属边界：`AgentRunStore` 属于 `core/ai/agents` 的 agent framework，不属于
`app/agent_runtime` 或 native FRB runtime。Runtime 只负责执行 profile turn /
effect plan / tool dispatch 并产出 trace；`AgentRunner` 负责把运行生命周期写入
store。

建议路径：

- `apps/mobile/lib/core/ai/agents/agent_run_store.dart`
- `apps/mobile/lib/core/persistence/local_only_tables.dart`
- `apps/mobile/test/core/ai/agents/agent_run_store_test.dart`

建议字段：

| 字段 | 用途 |
|---|---|
| `agent_id` | stable agent id |
| `domain` | `finance` / `health` / `knowledge` / `execution` |
| `status` | `idle` / `running` / `no_finding` / `ready` / `failed` |
| `trigger` | `manual` / `schedule` / `background_due` / `catch_up` |
| `started_at` / `finished_at` | 运行时间 |
| `next_due_at` | 下次应运行时间 |
| `last_success_at` | 最近非失败运行 |
| `error_code` / `error_message` | 用户可解释失败 |
| `memory_id` | 关联 memory |
| `artifact_id` | 关联统一结果 |
| `trace_id` | 关联 AI trace |

`AgentRunner` 改为从 `AgentRunStore` 读取 last-run，而不是只用进程内 `_lastRunAt`。

### AgentArtifact

新增统一结果契约，让 UI 不直接理解每个 agent 的自由 `payload`。

建议路径：

- `apps/mobile/lib/core/ai/agents/agent_artifact.dart`
- `apps/mobile/lib/core/ai/agents/agent_artifact_store.dart`
- `apps/mobile/lib/core/persistence/local_only_tables.dart`
- `apps/mobile/test/core/ai/agents/agent_artifact_test.dart`

建议 shape：

```dart
class AgentArtifact {
  final String id;
  final String agentId;
  final String domain;
  final AgentArtifactKind kind;
  final AgentSeverity severity;
  final String title;
  final String summary;
  final List<AgentInsight> insights;
  final List<AgentEvidenceRef> evidence;
  final List<AgentAction> actions;
  final String? memoryId;
  final String? traceId;
  final DateTime createdAt;
  final DateTime? expiresAt;
}
```

Artifact 是本地派生结果，默认 local-only；是否进入 backup 需要单独在 backup registry 中显式注册。

### AgentPresentationSpec

在 `DomainPack` 附近增加展示元数据，保持注册仍由 domain pack 收敛。

建议路径：

- `apps/mobile/lib/core/lifeos/domain_pack.dart`
- `apps/mobile/lib/core/ai/agents/agent_presentation.dart`
- `apps/mobile/lib/app/domain_composition.dart`

建议字段：

```dart
class AgentPresentationSpec {
  final String agentId;
  final DomainScope domain;
  final IconData icon;
  final String Function(AppLocalizations l10n) label;
  final String Function(AppLocalizations l10n) description;
  final bool userToggleable;
  final bool notificationsSupported;
  final AgentResultPlacement placement;
}
```

`DomainPack` 可贡献：

- `agentBuilder`
- `agentPresentationSpecs`
- `agentArtifactRendererBuilder`
- `agentSettingsBuilder`

## 需要改动的模块

### 1. Core Agent Framework

路径：

- `apps/mobile/lib/core/ai/agents/`

改动：

- 新增 `AgentRunStore`、`AgentArtifact`、`AgentArtifactStore`、`AgentPresentationSpec`。
- 扩展 `AgentRunResult`，增加 `artifactId`、`traceId`、`trigger`、`userVisibleStatus`。
- 修改 `AgentRunner`：
  - 运行前写入 `running`。
  - 成功后写入 `ready` 或 `noFinding`。
  - 失败后写入 `failed`。
  - schedule gate 从 store 读取 `last_success_at`。
- 修改 `AgentRunController`：
  - 支持 `runOnceById(agentId, trigger: ...)`。
  - 支持 catch-up tick。
  - 返回 run status + artifact reference。

测试：

- `AgentRunner` 持久化状态。
- 重启后不重复运行未到期 agent。
- 失败不推进 `last_success_at`。
- `noFinding` 仍记录 run history。

### 2. Persistence

路径：

- `apps/mobile/lib/core/persistence/local_only_tables.dart`
- `apps/mobile/lib/core/persistence/app_database.dart`
- generated Drift files

改动：

- 新增 local-only tables：
  - `agent_runs`
  - `agent_artifacts`
  - `agent_preferences`
- 这些表默认不同步。
- 如需要 backup，显式加入 `backup_table_registry.dart`，不要自动复用 sync registry。

测试：

- Drift repository tests。
- schema migration / generated code test。

### 3. DomainPack Composition

路径：

- `apps/mobile/lib/core/lifeos/domain_pack.dart`
- `apps/mobile/lib/app/domain_composition.dart`
- `apps/mobile/lib/app/domain_packs/*.dart`

改动：

- 在 `DomainPack` 增加 agent presentation / settings / artifact renderer 贡献点。
- 在 `domain_composition.dart` 聚合 active domain 的 agent presentation specs。
- optional domains 关闭时，不展示、不调度、不注册其 agent UI。

测试：

- `domain_composition_test.dart` 覆盖 active / inactive domain。
- 确认 inactive domain 的 agent artifact 不出现在全局列表。

### 4. Background Scheduling

路径：

- `apps/mobile/lib/core/background/`
- `apps/mobile/lib/core/ai/agents/`
- `apps/mobile/lib/features/health/agents/providers.dart`
- platform callbacks in iOS / Android as needed

改动：

- 把 HealthOS 现有 due flag 模式抽象成通用 `AgentBackgroundScheduler`。
- Workmanager callback 只写 due flag，不直接跑 heavy work。
- 前台启动后统一读取 due flags，调用 `AgentRunController.tick(trigger: background_due)`。
- 支持 domain opt-in、notification preference、agent preference。

测试：

- due flag 被消费一次。
- domain disabled 时取消或忽略 due run。
- foreground catch-up 不重复运行。

### 5. Agent Result UI

路径：

- `apps/mobile/lib/core/ai/agents/ui/` 或 `apps/mobile/lib/core/ai/visual/`
- `apps/mobile/lib/features/health/ui/`
- `apps/mobile/lib/features/knowledge/ui/`
- `apps/mobile/lib/features/execution/ui/`
- `apps/mobile/lib/features/finance/ui/`

改动：

- 新增可复用组件：
  - `AgentResultCard`
  - `AgentDetailSheet`
  - `AgentStatusBadge`
  - `AgentEvidenceList`
  - `AgentActionBar`
- 每个 domain 页面只负责选择 placement 和 domain-specific renderer。
- `Ask follow-up` 必须调用 `askAi()`，并传入 registered intent + `AiObjectRef`。
- UI 文案使用对象语义，不写泛化的 “Ask AI”。

测试：

- Widget tests for card states。
- Bottom sheet viewport behavior。
- l10n parity for new strings。

### 6. Settings Agent Management

路径：

- `apps/mobile/lib/features/settings/`
- `apps/mobile/lib/core/shell/settings_route_paths.dart`
- `apps/mobile/lib/app/router_builder.dart` or current settings route owner

改动：

- 新增 Agents settings page。
- 列出 active domain agents：
  - toggle
  - cadence
  - notification setting
  - last run
  - last status
  - run now
  - view history
- 对 inactive domain 显示 domain enable CTA，而不是展示不可运行的 agent。

测试：

- Settings page active domain filtering。
- Toggle persists to `agent_preferences`。
- `Run now` calls `AgentRunController`。

### 7. Existing Domain Agents

路径：

- `apps/mobile/lib/features/health/agents/`
- `apps/mobile/lib/features/knowledge/agents/`
- `apps/mobile/lib/features/execution/agents/`

改动：

- HealthOS：
  - Morning Briefing 输出 `AgentArtifact`。
  - Recovery Alert 输出 severity = warning / attention。
  - Weekly Summary 输出 review artifact。
- KnowledgeOS：
  - Review / Assumption / Contradiction / Inbox Triage / Routine Due 输出统一 artifact。
  - Routine due notification deep link 到 artifact detail，不进 chat。
- ExecutionOS：
  - Execution Review 输出 today actions / blocked / due evidence。

测试：

- 每个 agent 的 artifact contract test。
- runtime fallback 时仍可输出 programmatic artifact 或 failed status。

### 8. FinanceOS New Agents

路径：

- `apps/mobile/lib/features/finance/agents/`
- `apps/mobile/lib/app/domain_packs/finance_pack.dart`
- `apps/mobile/lib/features/finance/ui/`

首批状态：

| Agent | 触发 | 输出 | 状态 |
|---|---|---|---|
| Weekly Wealth Review | weekly | net worth delta, account changes, evidence | ✅ `weekly_wealth_review_agent.dart` |
| Cashflow Anomaly Review | daily / after import | unusual spend / income changes | ✅ `cashflow_anomaly_review_agent.dart` |
| FIRE Plan Drift Monitor | weekly | gap to plan, assumptions changed | ✅ `fire_plan_drift_monitor_agent.dart` |
| Options Income Risk Review | daily / after scan | concentration, quote quality, stale scan warnings | ✅ `options_income_risk_review_agent.dart` |

规则：

- Money math 和投资规则走 deterministic services / tools。
- LLM 只做摘要和解释。
- 不直接给买卖指令。
- 所有写入动作走 proposal。

测试：

- deterministic input snapshot to artifact。
- no LLM profile fallback。
- proposal risk mode。

### 9. AI Intent And Follow-Up

路径：

- `apps/mobile/lib/core/ai/intent/`
- domain intent registrations
- `apps/mobile/lib/core/ai/composition/ask_ai.dart`

改动：

- 新增 agent-result 相关 intent：
  - `agent.explainResult`
  - `agent.showEvidence`
  - `agent.createPlanFromResult`
  - domain-specific intents such as `health.explainRecoveryAlert`
- `AgentDetailSheet` 的 follow-up chips 必须使用 registered intent。
- Trace invocation 写入 source / intent / object / domain。

测试：

- intent catalog active domain coverage。
- off-catalog intent dev assert / prod fallback。

### 10. Trace, Diagnostics, And Evals

路径：

- `apps/mobile/lib/core/ai/trace/`
- `apps/mobile/lib/app/agent_runtime/trace/`
- `apps/mobile/test/`
- optional: `apps/mobile/lib/core/ai/regression/`

改动：

- Agent run 写入 trace id / step run reference。
- Agent artifact detail 提供 local transparency entry。
- 增加 agent outcome regression corpus：
  - fixed snapshot
  - expected status
  - expected top insights
  - expected evidence refs
  - expected proposal kind

测试：

- tool failure。
- budget exhausted。
- no LLM profile。
- prompt injection in retrieved content。
- domain opt-out。

## 分阶段计划

### Phase 1: Run State And Store

目标：agent 运行可靠，不因重启丢 schedule 状态。

改动模块：

- `core/ai/agents/`
- `core/persistence/`
- tests under `test/core/ai/agents/`

验收：

- `AgentRunner` 不再依赖内存 `_lastRunAt` 作为唯一真源。
- app 重启后不重复运行未到期 agent。
- failed run 可见、可重试、不推进 last success。

### Phase 2: Artifact Contract

目标：所有 agent 有统一结果 shape。

改动模块：

- `core/ai/agents/agent_artifact.dart`
- `core/ai/agents/agent_artifact_store.dart`
- existing Health / Knowledge / Execution agents

验收：

- Health Morning Briefing、Knowledge Review、Execution Review 至少各产出一个 `AgentArtifact`。
- artifact 可关联 memory / trace。
- artifact local-only，不进入 sync。

### Phase 3: Unified Result UI

目标：用户在领域页面用同一种方式查看 agent 结果。

改动模块：

- reusable agent UI components
- Health / Knowledge / Execution domain pages
- l10n ARB files

验收：

- 有 ready / noFinding / failed / running 四类 UI 状态。
- Detail Sheet 展示 summary、evidence、actions、trace entry。
- Follow-up 通过 `askAi()`，不新增 chat route。

### Phase 4: Settings And Preferences

目标：用户能控制 agent。

改动模块：

- `features/settings/`
- `core/ai/agents/agent_preferences`
- route / settings path

验收：

- 可开关每个 agent。
- 可运行一次。
- 可看 last status / last run。
- notification preference 与现有 notification setting 不冲突。

### Phase 5: Cross-Domain Scheduler

目标：HealthOS 的后台 due flag 模式变成跨域能力。

改动模块：

- `core/background/`
- `core/ai/agents/`
- Health providers cleanup
- platform task registration as needed

验收：

- due flag 被统一消费。
- Knowledge / Execution 可以声明 background capable agent。
- inactive domain 不调度。

### Phase 6: FinanceOS Agents

目标：always-on domain 拥有可见 agent 价值。

改动模块：

- `features/finance/agents/`
- `app/domain_packs/finance_pack.dart`
- finance home / activity / wealth / plan surfaces

验收：

- 至少一个 weekly finance artifact 在 Finance Home 或 Plan 出现。
- 数据计算 deterministic。
- proposal / evidence / trace 都走现有契约。

## 非目标

- 不新增 `/ai` tab。
- 不把 agent 结果默认写成 chat message。
- 不开放用户可见的 subagent 编排。
- 不让 LLM 自动执行高风险写入或外部副作用。
- 不把 domain business type 放进 `core/`。
- 不引入 backend AI relay。

## 推荐验证命令

修改实现后按触达范围运行：

```bash
cd apps/mobile
rtk dart format .
rtk flutter analyze --fatal-infos
rtk flutter test test/core/ai/agents
rtk flutter test test/app/domain_composition_test.dart
rtk flutter test test/features/health/agents
rtk flutter test test/features/knowledge/agents
rtk flutter test test/features/execution/agents
```

触达架构边界时补跑：

```bash
./tool/lint-no-finance-in-core.sh
./tool/lint-no-feature-in-shared.sh
./tool/lint-domain-neutral-contracts.sh
./tool/check-tool-descriptors.sh
```
