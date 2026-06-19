# NaviWealth AI 架构

> **现状一句话**: AI 是 **device-only**。端侧 agent runtime 用**用户自带的 LLM key**
> 直连用户选定的 provider（Anthropic 或 OpenAI 兼容端点），后端**完全不参与 AI**。
> `apps/backend/src/ai/` 与 `/ai/chat`、`/ingest/parse` 路由已删除；backend 只剩
> auth / sync / D1。Web 无 AI。
>
> **怎么读这篇**: §1–§3 是当前架构（device-only），改 `lib/core/ai/` 前读这三节。
> §4 是契约细节，其中 §4.6 是 device runtime 的落地决策（代码注释大量引用其编号，编号保持稳定）。
> §5 是 AI 的 UI/UX 契约——**任何新 AI 入口/渲染/确认面必须满足 §5.8 + §5.10.7 硬约束**。
> §4.2 freshness gate / §4.3 cloud read models / §6.2 backend AI / §8 等
> **描述的是已删除的云端协作架构**，仅为历史/编号锚点保留。
>
> **2026-05-24 boundary audit** 之后，下列结构**全部已物理删除**：
> - freshness gate (`core/ai/freshness/` + 契约 + `staleReadModelNames`)
> - router (`core/ai/router/`)
> - `RuntimeRegistry` / `RuntimeId` / `AiRuntime` 抽象 / `CloudAnthropicRuntime` / `RulesDeviceRuntime`
> - `CloudProposal` 类、`ChatSyncGate`、ChatTurnPhase.flushing
> - disclosure 全链：`DisclosureRequest`/`DisclosureResponse`/`LedgerField`/`UserConsent`/
>   `DisclosureSummary`/`AiTrace.disclosures`/`AiTrace.usedRawLedger`/`addDisclosure`
> - `TaskContext.retrieved`/`TaskContext.aggregates`/`ScopedAggregate`
> - `TaskContext.analyticalUploads` 字段 + `deviceHlc`（`AnalyticalUpload` class 保留作 6 个 device tool 的输出 shape）
> - `ToolDescriptor.readModelLayer`/`ReadModelLayer`/`AllowedRuntime`/`allowedRuntimes`
> - `AnonymizationLevel`/`amountAnonymization` getter
> - `AiTrace.usedCloud`（持久化但零读取的 wire fossil）
> - 3 个 l10n orphan keys
>
> 累计净删约 4 400 行（四轮）。详见 [`docs/ai-boundary-audit.md`](./ai-boundary-audit.md)。
>
> 适用范围: `lib/core/ai/` 与 `lib/features/ai_chat/`、`lib/features/ingest/`（Flutter）。
> 运行时事件契约见 [`docs/ai-protocol.md`](./ai-protocol.md)。

---

## 1. 设计哲学（device-only）

```text
端侧 agent = 大脑 + 执行器（不再有云端 brain）
用户自带 key = 唯一的模型访问凭证
后端 = 与 AI 无关（auth / sync / D1）
```

四条原则：

1. **端侧即真值**: 工具直接读本机 Drift。没有 D1 read model、没有 freshness gate、
   没有 ScopedDisclosure 脱敏——本就 local-first，原始数据不出设备。
2. **代码强制 > Prompt 强制**: `ToolDescriptor` 元数据 + dispatcher 在调用层拦截违规
   工具调用；不靠 system prompt 的口头约束。
3. **副作用分级 > 读写之分**: `ProposalEnvelope` sealed 类按副作用分级；高风险写入一律
   走确认通道，LLM 不能自动触发外部副作用（下单/转账）。
4. **透明可见**: 每次应答生成 `AiTrace`（本地存储，不同步），用户可见徽章
   「端侧直连模型 · 未经我方服务器」。

## 2. Runtime（`lib/core/ai/runtime/`）

### 2.1 调用链

```text
ChatRepository
  → RuntimeRoutingAiChatApiClient   (features/ai_chat/data/)
  → DeviceLlmRuntime                (runtime/ai_runtime.dart + runtime/device/)
  → AnthropicClient | OpenAiClient  (runtime/device/{anthropic,openai}/)
  → DriftDeviceToolDispatcher       (runtime/device/device_tool_dispatcher.dart)
```

- `DeviceAgentLoop`（`runtime/device/device_agent_loop.dart`）= 端侧 agent loop：
  prompt 组装 / provider 调用 / tool dispatch / proposal 全在端侧，对 provider 无感。
- provider 客户端统一翻译为 provider-neutral `LlmStreamEvent`（含 `tool_use`），
  由 active `LlmProfile.provider` 决定走哪个 client。
- 事件词表（`TextEvent` / `ToolCall*` / `SpanEvent` / `DoneEvent` …）见
  [`docs/ai-protocol.md`](./ai-protocol.md)——repository/UI 仍用旧事件词表，故 chat 历史 /
  流式渲染 / 取消 / trace 捕获无需重写，只是事件改为进程内 Dart stream。

### 2.2 凭证（`lib/core/ai/llm_credentials/`）

- `LlmCredentials` = 容器 `{ profiles: List<LlmProfile>, activeId }`；
  `LlmProfile{ id, name, provider, apiKey, baseUrl?, model? }`。
- 存 `SecureKeyStore`（Keychain / Keystore / 凭据库 / libsecret），与 SQLCipher key
  同等对待——**绝不**进 OpLog / 云同步 / 明文备份。
- **无 opt-in 开关**（`enabled` 已删除）：无云回落，active profile 即意图
  （`isUsable = active?.hasKey`）。设置页是 profile 卡片列表（切换/编辑/删除 + 连通性测试）。
- `LlmConnectivityProbe`（`llm_connectivity.dart`）走与真实 chat 同一路径发 1-token ping，
  `classifyLlmProbeException` 把结果分为 ok / 鉴权失败 / 端点不存在 / 限流 / 被拒 / 网络不可达。

### 2.3 平台门控与降级

- **门控 = `!kIsWeb`**：所有原生平台（iOS / Android / macOS / Windows / Linux）都有
  系统级安全存储 + 原生 HTTP，安全前提相同 → 全部支持端侧 agent。**只有 Web 无 AI。**
- **无 cloud 回落**（已删除）：web / 无可用 active profile / provider 报错
  → `RuntimeRoutingAiChatApiClient` 直接产 `ErrorEvent(code:"device_unavailable")`
  + `DoneEvent(stopReason:"error", rounds:0)`，UI 引导用户去设置加 API key。
  provider 自身报错按其 `ErrorEvent`/`DoneEvent` 原样透传。降级仍写 `AiTrace`。

## 3. 工具与契约（`lib/core/ai/contracts/` + domain `ai_tools/`）

### 3.1 工具目录（DomainPack 聚合）

端侧工具目录由 active `DomainPack`s 聚合：Shell core tools 来自
`core/ai/runtime/device/tools/device_tool_registry.dart`，Finance / Health /
Knowledge 工具分别由各自 `features/<domain>_ai_tools.dart` 和 domain-local
`ai_tools/` 暴露。完整生产诊断合集在
`apps/mobile/lib/app/production_ai_catalog.dart`：
`productionDeviceTools` 是 dispatch allow-list，
`productionToolDescriptors` 是对应元数据。`./tool/check-tool-descriptors.sh`
（跑 Dart 契约测试）CI 守护两者一一对应。

| 域 | 工具来源 |
|----|----------|
| Shell | Memory Layer tools: `query_memory` · `build_context` · `ask_user` |
| FinanceOS | `features/finance_ai_tools.dart`，含基础财务、FIRE、Options Income、scoped read / propose 工具 |
| HealthOS | `features/health_ai_tools.dart` |
| KnowledgeOS | `features/knowledge_ai_tools.dart` |

数据源全部是**本机 Drift / 既有端侧 provider**（net worth / currency service /
`holdingsSnapshotProvider` / `DriftQueryPlanExecutor` / 端侧 detector）。Scoped Detail
（`read_*_window`）端侧不出设备 → 不再 HMAC 脱敏，但仍保留 `purpose` 必填 + 写 AiTrace。

### 3.2 ToolDescriptor 元数据轴

`name` · `access` · `risk` · `requires_confirmation` · `allowed_context_tier` ·
`side_effect`（boundary audit 删除了 `allowed_runtimes` / `read_model_layer`——
device 是唯一 runtime，read-model 分层概念也已弃）。invariant 测试保证：proposals
必有 `DeviceLocalWrite` side effect、reads 必无 side effect。

### 3.3 ProposalEnvelope（确认通道，按副作用分级）

`contracts/proposal_envelope.dart` — sealed，3 子类（2026-05-24 boundary audit 中
`CloudProposal` 因零生产 producer 已删除；device propose 工具
直接进 `LocalProposal` 或 `ExternalSideEffect`）：

| 子类 | 应用层 | 确认 |
|------|--------|------|
| `LocalImmediateWrite` | 端侧立即应用 + undo | 无 |
| `LocalProposal` | 端侧 staged，用户 review | one-tap |
| `ExternalSideEffect` | 触达外部（broker/bank） | typed（**永不**由 LLM 自动触发） |

确认 gate 由 `(risk, side_effect)` 派生（见 §5.5）；不受任何 source / backend
label 影响。**Privacy policy 永远优先于 source。**

### 3.4 Trace（`lib/core/ai/trace/` + `contracts/ai_span.dart`）

- 唯一执行记录是 **Opik 风格 `AiSpan`** 层级树（`turn`/`llm`/`tool` × `parentId`
  × 偏移/时长 × tokens/model/stop/status/IO）。旧 flat `toolCalls`/timeline 已删（不向后兼容）。
- 持久化在 Drift `ai_traces`（local-only，不同步）；30 天清理由 caller 调度。
- UI：`ai_trace_waterfall.dart` 瀑布树 + span 详情 + 聚合头（p50/p95/token/¥估算）；
  透明度页 `/settings/ai-transparency`。
- `capturePayloads` 默认 metadata-only；verbose 经 `aiTraceVerboseProvider`（SharedPreferences）。
- 配套写表：`ai_undo_stack`（`DriftUndoStack`，原子 take）+ `ai_touched_entities`
  （`DriftAiTouchedStore`，`AiSourceMark`/`AiTouchMark` 在被 AI 修改字段旁显示 sparkle）。

## 4. 契约细节（编号稳定——代码注释引用）

> §4.1–§4.5 描述已删除的端云协作设计。**编号保留**让代码注释里 `§4.2`/`§4.3`
> 仍能落到正确概念，但**所述结构在 2026-05-24 boundary audit 之后已删除**——见每条
> 状态。`ContextPack` 仍在仓库内（device runtime 喂 prompt 用）；`ScopedDisclosure`
> 只剩 `DisclosurePurpose` enum（device window tool 参数校验用），其余协议类型
> （`DisclosureRequest`/`DisclosureResponse`/`LedgerField`/`UserConsent`）已物理删除。

- **§4.1 ContextPack**（`contracts/context_pack.dart`）：runtime-neutral 输入契约
  （BaseContext 偏好层 + TaskContext 任务层 + PrivacyBudget）。device runtime 仍构造
  ContextPack 喂端侧 prompt；不再上传后端。`FreshnessHint` / `analyticalUploads` /
  `deviceHlc` / `retrieved` / `aggregates` 字段均已删除；TaskContext 当前只剩
  `route` / `intent` / `signals`。
- **§4.2 Freshness gate**（曾在 `freshness/freshness_gate.dart`）：**整模块物理删除**
  （类型 + 调用点 + `AiTrace.staleReadModelNames` + `FreshnessHint`）。端侧是 local-first
  真值源，无 read model stale 问题。
- **§4.3 Cloud Read Models 三层访问模型**（Snapshot / Analytical / Scoped Detail）：
  **云端表已弃用**（backend `migrations/0006_ai_read_models.sql` 等仅作 schema 历史保留，
  不再投影/查询）。`ToolDescriptor.read_model_layer` 字段及 `ReadModelLayer` enum
  **已删除**（boundary audit 批 K）；device 工具直接读 Drift，无分层概念。
- **§4.5 ProposalEnvelope**：见 §3.3（`CloudProposal` 子类已在 2026-05-24 audit 中删除）。
- **§4.6 Device LLM Runtime（当前架构的落地决策——代码大量引用 §4.6.N）**：
  1. **用户自带 key** — `SecureKeyStore`，绝不进 OpLog/同步/明文备份。
  2. **`DeviceLlmRuntime` 直连 provider** — 多 provider 客户端，统一 `LlmStreamEvent`；
     provider 由 active `LlmProfile.provider` 决定。
  3. **工具读 Drift 本地真源** — §4.2 freshness gate 已物理删除；`ScopedDisclosure`
     协议（DisclosureRequest/Response/LedgerField/UserConsent）也已删除，只保留
     `DisclosurePurpose` enum 用作 window tool 参数校验。
  4. **Vision 端侧直发** — 图像 base64 → content block，用户 key 直发 provider，
     原图不出设备（比已删除的 Worker 中转更私密）。
  5. **平台边界 = 全部原生平台，仅排除 Web**（门控 `!kIsWeb`，见 §2.3）。
  - 无 device→cloud 失效转移（见 §2.3 降级）。

## 5. Interaction Grammar — AI 进入页面，而非用户进入 AI

> 这是 UI/UX 层的契约，与 §1–§4 wire 契约平级。所有 AI 入口 / Bottom Sheet /
> Capsule / Reply Chip / Proposal 确认面**必须**遵守。PR review 按 §5.8 + §5.10.7 逐条对照。

### 5.1 设计哲学（三句话）

1. **Invisible but Omnipresent** — AI 像系统服务，不像功能模块。
2. **AI 进入用户的页面** — inline bottom sheet 原位展开，禁止把用户踢到 AI 目的地。
3. **Calm Intelligence** — typography-first，克制动效，极少 sparkle；禁止 chatbot 气泡 /
   glow / neon 渐变 / 机器人头像。参考 Apple Intelligence / Linear / Notion AI。

### 5.2 三层入口模型（必须共存）

| 层级 | 触发者 | 形态 | 落地 |
|------|--------|------|------|
| **Ambient** | 系统/端侧 detector | Insight 卡片（展开/问一下/忽略）| `features/home/ui/ai_insight_feed.dart` |
| **Contextual** | 用户在某对象上 | Capsule → inline bottom sheet | `AiObjectCapsule` + `showAiBottomSheet` |
| **Global** | 跨领域复杂任务 | 命令栏 overlay（**非** `/ai` tab）| `core/command_palette/` |

### 5.3 `AiIntentInvocation` — 唯一入口协议

所有调起 AI 的地方（capsule / insight tap / command / 未来 voice）**必须**经过
`AiIntentInvocation{ source, intent, object?, context, suggestedPrompt?, capabilities }`
（`lib/core/ai/intent/`）。禁止散落的 `openAiChat(...)` 风格 API。`intent` 必须在
`intent_policy.dart` 注册（`labelZh` / `allowedObjectTypes` / `promptTemplate`）；
未注册 dev 模式 `assert(false)`，prod 回落 `suggestedPrompt`。

### 5.4 默认 surface = Inline Bottom Sheet

`AiIntentInvocation` 默认渲染为覆盖当前页的 modal bottom sheet；**禁止**跳转 AI 目的地。
viewport < 500px → 自动升级 fullscreen Dialog。「展开对话」是二级动作，才转 session。

### 5.5 风险分层 × 交互模式（代码引用 §5.5）

`InteractionMode`（`core/ai/write/interaction_mode.dart`）由
`deriveInteractionMode(ProposalEnvelope)` **派生，禁止 feature 硬编码/降级**：

| risk × side_effect | mode |
|---|---|
| `ExternalSideEffect`（任意）| `typed`（输入确认词二次）|
| `info` | `oneTap` |
| `suggest` + `deviceLocalWrite` | `swipe`（+ persistent undo）|
| `propose` | `confirmDiff`（必须看 diff preview）|
| `commit` | `typed` |
| 未知 | `confirmDiff`（安全默认）|

要降级先改 `risk`，不能为「流畅」把 `confirmDiff` 降 `oneTap`。Undo 是全局 persistent
banner（`PersistentUndoBanner` 挂 AppShell footer，接 `DriftUndoStack`），非 60s toast。

### 5.6 Calm 视觉

AI 元素默认 surface tone（非 accent）；单色细线 sparkle（字号 ≤ 正文）；流式光标单
`█` 脉冲；reply chip outline button；来源 badge 小灰字。原语在 `lib/core/ai/visual/`
（`AiSparkle`/`AiPill`/`AiTone`/`AiType`/`AiMotion`）——禁止 `colorScheme.tertiary`、
禁止散落 `Icons.auto_awesome`（实心）。

### 5.7 Intent 治理

`intent_policy.dart` 集中注册 intent（仿 tool policy）。新加 capsule 前先注册；
`intent × object_type` 不匹配则 capsule 不渲染。

### 5.8 实施硬约束（PR review 逐条勾选，漏一条不过）

- [ ] **唯一入口**：无新的 `openAiChat(...)` / `Navigator.push(ChatPage(...))`；都经 `AiIntentInvocation`
- [ ] **默认 surface**：默认 bottom sheet；route push 仅作 expand / 窄屏 fallback
- [ ] **Object-semantic label**：文案不出现「Ask AI」/「AI 分析」，用对象语义动作
- [ ] **Intent 注册**：新 intent 在 `intent_policy.dart` 注册（`labelZh`/`allowedObjectTypes`/`promptTemplate`）
- [ ] **风险分层**：`interaction_mode` 经 `deriveInteractionMode` 派生，不硬编码、不降级
- [ ] **Calm 视觉**：无渐变/glow/巨型 AI icon；sparkle ≤ 正文；默认 surface tone
- [ ] **Trace**：新 surface 必填 `AiTrace.invocation`（source / intent / object）
- [ ] **Three-tier 平衡**：单独加 ambient/contextual/global 任一层前确认另两层覆盖

### 5.9 四层入口拓扑（§5.10 的落地形态，已实现）

§5.2 三层 + 「录入隐形 AI」归并为四层；**没有 `/ai` tab、没有悬浮气泡、没有散落 ✨**：

| Layer | 名称 | 形态 | 落地 |
|-------|------|------|------|
| 1 | 统一命令栏 | Cmd-K overlay / 移动端顶栏 pill | `core/command_palette/`（就地出结构化答案，不留对话历史）|
| 2 | 内联上下文 Capsule | 图表 ⋯ / 卡片长按 → bottom sheet | §5.4 不变 |
| 3 | 环境式洞察 | 主屏卡片三动作（展开/问一下/忽略）+ 偏好学习 | `ai_insight_feed.dart` |
| 4 | 录入链路隐形 AI | 截图/文件/粘贴/分享自动解析 | `features/ingest/`（见 §5.10）|

拓扑结果：`/ai` tab 下线（4-tab：Home/Activity/Accounts/Settings）；chat 迁
`/settings/ai-history`（只读回放）；FIRE/Rebalance/Analytics 迁 `/accounts/{fire,rebalance,analytics}`。

#### 5.10 反模式清单（代码引用 §5.10.7；PR review 一票否决，与 §5.8 累加）

- 右下角悬浮聊天气泡 · 底部多一个「AI」tab（含 5-tab 复活）· ✨/魔法棒/glow 撒在每个面板旁
- 一打开 app 先看到 chat 而非数据 · AI 直接给「该买/该卖 XX」投资建议
- LLM 直接计算金额并显示（必须经 ToolDescriptor 工具路径）· 把转账/下单做成 AI 一句话触发
- 紫色渐变 / 彩虹色 / 机器人头像
- **摄取草稿在用户确认前不得出现在 `journal_entries` / OpLog / 任何持久层**

#### 5.10.x Layer 4 录入管道（`features/ingest/`）

无入口的隐形 AI：粘贴/拖拽/分享/截图 → 解析 → 复用端侧 `merchant_key`/`txn_classifier`
归一 → 对 **Drift 真源**模糊去重 → 落本地 `ingest_drafts`/`ingest_attachments`
（schema 表，**不进 OpLog、不同步**）→ 以 Layer 3 洞察卡静默冒泡（`/activity/ingest`）→
确认走现有 `ProposalApplier`（永不自动 commit）。

- 端侧解析（CSV / paste）零联网，落地可用。
- **后端 Vision relay 已删除**：原 `POST /ingest/parse` 与
  `apps/backend/src/ai/ingest/` 随后端 AI 一并删除。图片/PDF 的 Vision 解析改为
  **端侧直发**（`DeviceVisionIngestClient` + `core/ai/runtime/device/device_vision_parse.dart`，
  用户 key，§4.6 决策 4，原图不出设备）；无可用端侧 runtime 时 `CloudIngestClient`
  槽位降级为 `UnavailableCloudIngestClient` stub，回「去设置加 key」而非打死端点。
- 隐私门 `ingest_privacy_gate.dart` 仍在：`amountsLocal` 拒云端摄取。

## 6. 模块映射

### 6.1 Mobile（`lib/core/ai/`，当前）

```
contracts/   intent · privacy_budget · task_context(route/intent/signals) ·
             base_context · context_pack · scoped_disclosure(DisclosurePurpose only) ·
             tool_descriptor(no allowed_runtimes/read_model_layer) ·
             proposal_envelope(3 subclasses, no CloudProposal) ·
             ai_span · ai_trace(no usedCloud/usedRawLedger/disclosures/staleReadModelNames) ·
             privacy_mode_provider(no amountAnonymization) ·
             AnalyticalUpload(tool 输出 shape, not pre-injected)
runtime/
  ai_runtime.dart                DeviceLlmRuntime + DeviceChatRunner
                                 （boundary audit 删 RuntimeRegistry / RuntimeId /
                                 AiRuntime / CloudAnthropicRuntime / RulesDeviceRuntime）
  device/
    device_agent_loop.dart       端侧 agent loop
    device_session.dart          per-turn session
    device_system_prompt.dart    端侧 system prompt + 硬限额
    device_tool_dispatcher.dart  只广告 active DomainPack 聚合出的工具
    device_vision_parse.dart     端侧 Vision 抽取
    llm_stream_event.dart        provider-neutral 事件
    anthropic/                   AnthropicClient + SSE decoder + wire
    openai/                      OpenAiClient + SSE decoder
    tools/                       Shell core tools + DeviceToolRegistry
llm_credentials/                 LlmCredentials/LlmProfile + SecureKeyStore +
                                 连通性探测 + providers   (§2.2)
trace/                           AiTraceStore / DriftAiTraceStore / builder /
                                 capture preference / providers
write/                           ProposalEnvelope 应用（3 子类）· InteractionMode ·
                                 DriftUndoStack · DriftAiTouchedStore ·
                                 AiSourceMark · PersistentUndoBanner
intent/                          AiIntentInvocation · intent_policy · chip scope
visual/                          AiSparkle/Pill/Tone/Type/Motion · ai_json_view
local/skills · local/embedding   端侧 detector（merchant_key / txn_classifier /
                                 recurring / transfer / refund / subscription /
                                 nl_to_query_plan / DriftQueryPlanExecutor）+
                                 SemanticMemory（StubEmbedder——LifeOS Memory Layer
                                 的预留 stub，零生产 caller）
regression/                      regression_corpus（静态契约测试）

(已删除子目录: freshness/ · router/  —— 2026-05-24 boundary audit)
```

`lib/features/ai_chat/`：`runtime_routing_api_client.dart`（→ DeviceLlmRuntime，无回落）·
`chat_repository.dart` · `proposal_applier.dart` · ui/（`ai_chat_page` 现为
`/settings/ai-history` 只读 · `propose_card`（mode 三分支）· `tool_invocation_*`
domain renderer · `ai_object_capsule` · `reply_chips` · `ai_transparency_badge`）。

`lib/features/ingest/`：见 §5.10.x。

### 6.2 Backend — **已删除**

`apps/backend/src/ai/` 整目录删除：无 `/ai/chat`、`/ingest/parse`、guardrails、
read model projection、ContextPack ingest。backend router（`lib.rs`）只剩
`/` · `/health` · `/health/db` · `/auth/*` · `/me` · `/sync/push` · `/sync/pull`。
`migrations/` 内 `0003_ai_rate_limit` / `0006_ai_read_models` / `0007_holdings_snapshot`
等仅作 schema 历史保留，不再写入/查询。`ANTHROPIC_API_KEY` 不再是后端 secret。

## 7. 数据流（device runtime）

```
Chat → providers.dart _prepareChatTrace(ref, requestId)
  → ContextCompressor.compress() 编 ContextPack（端侧派生信号 + 偏好）
  → RuntimeRoutingAiChatApiClient → DeviceLlmRuntime
     - Anthropic/OpenAiClient 直连用户 provider（用户 key）
     - DriftDeviceToolDispatcher 仅广告 active DomainPack 聚合出的工具
     - 每个 tool_call 直接读本机 Drift / 端侧 provider，数据不经我方服务器
  → Dart stream events 回流，端侧渲染
  → AiTraceBuilder 记录 turn / llm / tool spans
  → AiTraceStore.append(trace.finalize())
  → 徽章：「端侧直连模型 · 未经我方服务器 · N 工具 · 1.4s」
无可用 active profile / web → device_unavailable（§2.3）
```

## 8. 实现状态

| 范围 | 状态 |
|------|------|
| 端侧 contracts / trace / skills / NL→QueryPlan / SemanticMemory(stub) | ✅ |
| §5 Interaction Grammar（§5.1–5.9 契约 + 四层拓扑 + 命令栏主入口 + Layer 2/3）| ✅ |
| §5.10 Layer 4 录入：CSV/paste 端侧解析 + 草稿队列 + 确认链 + 隐私门 + 文件/相机/拖拽/分享捕获 | ✅（iOS Share Extension Xcode target 待做）|
| 端侧 Vision 直发（图片/PDF 摄取，`DeviceVisionIngestClient`，替代已删除的 Worker 中转）| ✅ |
| AiTrace span 可观测性（Opik 瀑布树，取代旧 flat 格式，不向后兼容）| ✅ |
| 多 provider profile + 切换 + 连通性测试（无 opt-in 开关）| ✅ |
| §4.6 Device LLM Runtime（用户自带 key · 直连 provider · 工具读 Drift · 全原生平台含桌面 · 删除 cloud relay）| ✅ |
| Boundary audit 2026-05-24（四轮）：删 freshness/router/RuntimeRegistry/CloudProposal/ChatSyncGate/disclosure 全链/TaskContext 死字段/readModelLayer/AllowedRuntime/AnonymizationLevel/usedCloud/analyticalUploads 字段/l10n orphans（累计净删 ~4 400 行）| ✅ |

**测试 gate**：`flutter analyze --fatal-infos` clean；`flutter test` 全绿（golden 按平台
skip，known-failing 钉基线）；`tool/check-tool-descriptors.sh` / `check-enum-mirror.sh` /
`check-l10n-parity.sh` 跑 Dart 契约测试。
> 已知失败基线：`ai_trace_waterfall_test.dart` 在干净 main 即 l10n-null 失败，
> 与功能无关，勿追（见 `known-failing-tests.txt`）。

### 历史：已删除的云端协作架构

AI 曾是「端侧 Copilot + 云端 Brain」分层协作：4 条通道（主通道 = Cloud AI
Read Models / 辅助 = ContextPack / 兜底 = ScopedDisclosure freshness·privacy·draft gate /
确认 = ProposalEnvelope）；Read Models 三层（Snapshot / Analytical / Scoped Detail）
在 D1 预计算 + HLC watermark freshness；`apps/backend/src/ai/`（anthropic / sse /
tools / proposals / guardrails / read_models / policy）。

落地历程概要：

| 范围 | 主题 | 当前状态 |
|------|------|------------|
| 早期 | Cloud Read Models 三层 + freshness gate + risk_policy enforce + AiRuntime/Registry + Trace/Undo Drift 持久化 + backend tools.rs 拆分 | 云端部分**已删除**；Drift 持久化、Registry、ToolDescriptor 扩展保留 |
| 中期 | AI 透明度审计页 + ContextPack→system prompt + Drift QueryPlanExecutor + TerminalReason + ProposalEnvelope.source + ContextPack 收缩 | 端侧部分保留 |
| §5 | AiIntentInvocation 入口框架 + domain renderer + InteractionMode + 视觉原语 + tool inline + AiTouchMark 全覆盖 | ✅ 当前 UI 契约 |
| 测试 | Red CI cleanup + schema-as-contract gates + AI 视觉回归 + 回归 corpus | ✅ |
| Trace | Opik 风格 span 可观测性（删旧 flat trace，不兼容）| ✅ |
| 多 provider | 多 provider profile + 切换 + 连通性测试（删 opt-in 开关）| ✅ |
| 修复 | 修复多轮 CancelToken 中毒（含 tool 调用的 round-2 误判 provider_error）| ✅ |
| Catalog | active catalog 对齐：移除未注册工具，descriptor 28→22；`ai-protocol.md` 改为设备事件契约 | ✅ |
| 端侧 LLM | 自带 key → 直连 provider → 工具读 Drift → 全原生平台含桌面 → **删除 cloud relay**（§4.6）| ✅ 当前架构 |

## 9. 剩余工作

- **iOS Share Extension**：`receive_sharing_intent` 需 Xcode 独立 native target
  （App Group + entitlements + 签名），仓内不可盲建。Android 分享已可用。
- 长历史 `subscription_changes`：跨会话比对需把 `recurring_patterns` 经 OpLog 持久化到 Drift。
- 测试准出 P1：A11y baseline / 性能预算。
- Prompt injection corpus：已加入静态 regression corpus 基线（finance / insight / FIRE
  probes，`kPromptInjectionRegressionTag`），由 nightly `ai-semantic` workflow 覆盖。
- expense_list 选区工具条（§5.4 Layer 2 的 `transactions.explainSelection`，基础设施已就绪）。
