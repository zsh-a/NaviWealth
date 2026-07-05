# Agent 使用体验统一计划

Status: proposed cross-domain implementation plan.

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
| Agent 运行 | `apps/mobile/lib/core/ai/agents/agent_runner.dart` | 可 `runOnce` / `tick`，但 last-run 只在内存 |
| Agent 注册 | `apps/mobile/lib/app/domain_composition.dart` + `DomainPack.agentBuilder` | active domain scoped |
| Native runtime | `apps/mobile/lib/app/agent_runtime/` | FRB step runner、tool host、trace recorder 已接入 |
| AI 入口 | `apps/mobile/lib/core/ai/composition/ask_ai.dart` | UI 调用已收敛到 `askAi()` |
| Intent envelope | `apps/mobile/lib/core/ai/intent/ai_intent_invocation.dart` | 有 source / intent / object / domain |
| Proposal 应用 | `apps/mobile/lib/core/ai/composition/` + domain appliers | 已按 active `DomainPack` 聚合 |
| Memory / event | `apps/mobile/lib/core/ai/local/memory/` | Agent 可写 event 和 memory |

主要缺口：

- Agent run 状态未持久化，重启后 `_lastRunAt` 丢失。
- Agent 结果没有统一的 UI artifact 契约，领域页面各自读取 memory / event。
- HealthOS 的后台 due flag 模式没有沉淀为跨域通用 scheduler。
- Settings 缺少统一 agent 管理面。
- FinanceOS 作为 always-on seed domain 还没有 agent 结果体验。

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

建议首批：

| Agent | 触发 | 输出 |
|---|---|---|
| Weekly Wealth Review | weekly | net worth delta, account changes, evidence |
| Cashflow Anomaly Review | daily / after import | unusual spend / income changes |
| FIRE Plan Drift Monitor | weekly | gap to plan, assumptions changed |
| Options Income Risk Review | weekly / after scan | concentration, earnings, quote quality warnings |

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
