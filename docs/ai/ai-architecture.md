# NaviWealth AI 架构

NaviWealth 的 AI 是 device-only。原生端通过 flutter_rust_bridge（FRB）进入
Rust agent runtime，再使用用户自己的 `LlmProfile` 直连 Anthropic 或
OpenAI-compatible provider。Backend 不持有模型密钥、不转发 AI 请求；Web 不加载
AI runtime。

## Document Contract

本文拥有设备端 AI 的产品边界、Host/Runtime 分工、工具治理、Memory 上下文和写入
确认原则；不拥有具体领域业务规则或精确事件字段。字段与枚举以
[`ai-protocol.md`](./ai-protocol.md) 和可执行 contract tests 为准，Rust 实现布局以
[`agent-runtime-current.md`](../architecture/agent-runtime-current.md) 为准。

运行时事件契约见 [`ai-protocol.md`](./ai-protocol.md)，Rust runtime 的代码地图与
维护约束见
[`agent-runtime-current.md`](../architecture/agent-runtime-current.md)。

## 1. 边界

1. 本机 Drift 和端侧 provider 是业务数据真值，AI 工具不依赖云端 read model。
2. `ToolDescriptor` 与 dispatcher 在代码层限制访问、风险、确认和副作用。
3. 写入通过 `ProposalEnvelope` 分级；转账、下单等外部副作用不能由模型自动执行。
4. `AiTrace` 仅存本机且不参与同步，记录 turn、LLM 和 tool spans。
5. `core/ai/` 保持域中立；具体工具、agent 和业务策略由各 `DomainPack` 提供。

## 2. Runtime

### 2.1 业务 Agent 与非流式调用

```text
Domain agent / business AI seam
  -> AgentRuntimeProfileTurnRunner | AgentRuntimeLlmBridge
  -> FRB generated API
  -> lifeos_native::agent_runtime / agent-llm
  -> Anthropic | OpenAI-compatible provider
  -> Dart AgentRuntimeToolHost / proposal confirmation seam
```

### 2.2 交互式 AI Chat

```text
ChatRepository
  -> RuntimeRoutingAiChatApiClient
  -> FrbChatRunner
  -> AgentRuntimeLlmStreamBridge
  -> agent-chat / agent-llm
  -> AgentRuntimeToolHost
```

Rust 拥有 ChatTurn 状态、provider stream 解析、续轮和 tool-round budget。Dart 将
FRB primitive frames 映射为 `AiChatEvent`，执行 active `DomainPack` 暴露的设备工具，
再以 `chat_state` 和 `tool_results` 恢复 Rust loop。

每轮发送前，`ChatRepository` 调用 app-level Context Assembler：

```text
active DomainPacks.memorySourcePrefixes
  -> MemoryAccessPolicy
PersonalProfileStore -> PersonalProfileSnapshot
MemoryRuntime / EventStore -> role-classified memory + recent events
  -> untrusted ContextBlock(kind=profile|memory)
persisted chat prefix omitted by ContextWindow
  -> source-fingerprinted structured conversation checkpoint
  -> untrusted ContextBlock(kind=compaction_summary)
  -> agent-chat ContextPolicy / ContextSnapshot
  -> provider request
```

Host 负责 Drift、embedding、Personal Profile、当前 route/entity 和领域启用策略；Rust
负责 block/evidence 校验、时间与 supersede 过滤、token 预算、优先级选择、BLAKE3 hash、
渲染、压缩记录和恢复快照。Memory、Profile 与 Resource 都只是不可信证据，不能携带
指令权限；`user_confirmed` 只是最高数据可信度，不是 instruction。Host context 只进入
当前轮，不写入持久 transcript。关闭领域后，其本地数据仍保留，但同一个
`MemoryAccessPolicy` 会在自动 assembly、主动工具 recall、proposal target lookup 和
apply 四处阻止访问。

长会话 checkpoint 存于 local-only `conversation_checkpoints`，记录摘要截止消息、
源指纹、消息数量以及 topic / verified tool evidence / decisions / rejected options /
open loops / entities / time anchors / turn digest。它不是长期 Memory，不同步，也不写回
transcript；编辑或删除已摘要的源消息会使 checkpoint 失效。当前默认摘要器是确定性的
引用式 fallback，后续可通过 `ConversationCheckpointSummarizer` seam 接入端侧 LLM，
但来源校验、持久化和 instruction 权限仍由 Host/Runtime 控制。

### 2.3 人机交互与恢复

`InteractionEnvelope` / `InteractionResponse` 是 Chat 和 Proposal 共用的人机交互
协议，支持 `input` / `choice` / `approval`、one-tap / diff / typed confirmation、
subject、expiry、response schema 与 resume target。typed confirmation 的必填文本由
Runtime 校验，不由 UI 自行判断后绕过。

```text
ask_user tool result
  -> InteractionEnvelope(status=pending, resume=chat_turn)
  -> apply tool_results + suspend_interaction
  -> ChatTurn status=requires_interaction（不调用 LLM）
  -> local agent_runtime_chat_snapshots
  -> user InteractionResponse
  -> original turn_id + interaction_response
  -> interaction_result block
  -> next model round
```

ChatTurn 中 pending tools 与 pending interaction 强制互斥，恢复时也只能提交
`tool_results` 或 `interaction_response` 之一。缺少快照、ID 不匹配、过期、重复响应或
typed token 不匹配都 fail closed。`ask_user` 选择、Proposal approve/reject/cancel 和
typed confirmation 均持久化同一 response contract；旧 `DecisionSelection` 与
`applyState` 暂时保留作为兼容字段。

### 2.4 凭证与平台

- `LlmCredentials` 管理多个 `LlmProfile` 与 `activeId`。
- API key 存入 `SecureKeyStore`，不进入同步、日志或明文备份。
- 连通性测试由 `FrbLlmConnectivityProbe` 走同一 native provider path。
- `!kIsWeb` 是运行时边界；Web、无可用 profile 或 provider 错误均 fail closed，
  返回 `device_unavailable` 或对应 provider error，不回落到 backend。

## 3. 工具、写入与 Trace

### 3.1 工具聚合

`apps/mobile/lib/app/domain_packs.dart` 是生产域清单。Active packs 的工具在 app
composition root 聚合，再由 `AgentRuntimeToolHost` 形成实际 dispatch allow-list。

| 域 | 工具入口 |
|---|---|
| Shell | `core/ai/runtime/device/tools/` |
| FinanceOS | `features/finance/finance_ai_tools.dart` |
| HealthOS | `features/health/health_ai_tools.dart` |
| KnowledgeOS | `features/knowledge/knowledge_ai_tools.dart` |
| ExecutionOS | `features/execution/execution_ai_tools.dart` |

`ToolDescriptor` 的治理轴为 `name`、`access`、`risk`、
`requires_confirmation`、`allowed_context_tier` 与 `side_effect`。
生产工具目录与 descriptor 的双向一致性由
`device_degradation_test.dart` 直接守护。

### 3.2 ProposalEnvelope

| 类型 | 行为 | 确认方式 |
|---|---|---|
| `LocalImmediateWrite` | 本地立即应用并提供 undo | 无 |
| `LocalProposal` | 本地 staged，展示变更 | one-tap / diff / typed，按风险派生 |
| `ExternalSideEffect` | 触达 broker、bank 等外部系统 | typed |

确认模式必须由 `deriveInteractionMode(ProposalEnvelope)` 派生，feature 不得硬编码降级。
所有 `readyPlan()` 同时返回标准 approval interaction，UI 从该 interaction 的 mode 与
confirmation 派生交互强度。

### 3.3 用户审批后的长期 Memory

`propose_memory` 只能写 local-only `memory_candidates`，不能直接写 `memories` 或
`personal_profile_facts`。Candidate 通过 `target_type=memory|profile_fact` 区分目标；
用户确认后，`MemoryProposalApplier` 才执行 `create` / `supersede` / `forget`；reject、
cancel 与 undo 也走同一 proposal/interaction seam。

Apply 时重新校验 owner、candidate 终态、active-domain policy、目标记录、operation 与
模型提供的 id，禁止重复确认、跨用户覆盖或篡改目标。确认后的 AI Memory/Profile 使用
`authority=user_confirmed`、provenance source `user_confirmed_ai`；Memory confidence 为
`0.95`。应用失败保留 retry 能力，终态 candidate 按 owner 隔离并在 90 天后清理。
Settings 直接维护的 Profile 同样是 user-confirmed，但不经过模型。Conversation
checkpoint 不会自动升级为长期 Memory。

### 3.4 Trace

唯一执行记录是 Opik 风格 `AiSpan` 树：`turn` / `llm` / `tool`、父子关系、耗时、
token、model、stop reason、状态和可选 I/O。`ai_traces`、`ai_undo_stack` 与
`ai_touched_entities` 均为 local-only。

## 4. Device LLM Runtime 契约

- **§4.1 ContextPack**：由 BaseContext、TaskContext（`route` / `intent` /
  `signals`）和 PrivacyBudget 组成，只在端侧构造和消费。
- **§4.1a ContextBlock**：通用 runtime 上下文单位。Host 可提供 Profile、Memory、
  Resource、CompactionSummary 等数据块；数据块可携带 `ContextEvidence`（authority、
  provenance、validity、supersedes）。Runtime 重算 token/hash，过滤无效 evidence，
  按 `ContextPolicy` 选择并保存含 omission reason 的 `ContextSnapshot`。
  Runtime/Agent/Command instruction blocks 始终保留且与数据块分权。
- **§4.2 本地真值**：工具直接读取 Drift 或端侧 provider。
- **§4.3 写入边界**：所有写入和外部动作遵循 §3.2。
- **§4.4 Interaction**：问题、审批和 typed confirmation 使用
  `InteractionEnvelope`；ChatTurn 快照中的 pending tool 与 pending interaction
  不得共存。
- **§4.6 生产入口**：Chat、domain agents、profile turns、连通性探测、Vision ingest
  与 classifier/synthesizer 都通过 FRB/native runtime。Vision content blocks 使用
  用户 profile 直连 provider，原始文件不经过 NaviWealth backend。

## 5. Interaction Grammar

AI 以系统能力进入当前任务，不作为独立目的地。默认 surface 是 inline bottom
sheet；viewport 小于 500px 时可升级为 fullscreen dialog。

### 5.1 入口

所有 capsule、insight、command 和 voice 入口都必须构造
`AiIntentInvocation{source, intent, object?, context, suggestedPrompt?, capabilities}`。
Intent 先注册到 `intent_policy.dart`，禁止 feature 自建 `openAiChat` 导航。

| 层 | 形态 |
|---|---|
| Global | 命令栏 overlay |
| Contextual | 对象 capsule -> inline bottom sheet |
| Ambient | Agent result / artifact follow-up |
| Ingest | 文件、截图、粘贴和分享的隐形解析链 |

### 5.1a InteractionSession 与 Voice Turn

Voice 是输入/输出 capability，不是第二套 Agent loop。长期边界固定为：

```text
Interaction owns timing and delivery
Agent Runtime owns semantics and execution
Domain owns truth and side effects
Capability owns modality
```

一个 `AiIntentInvocation` 负责启动或标定一个 `InteractionSession`；同一
session 后续的每个输入都是新的 Turn，并携带 `inputOrigin`（`voice`、
`touch`、`keyboard` 等）。`AiIntentInvocation.source` 继续表示入口位置，
例如 `finance_home` 或 `command_palette`，不能被改作输入媒介字段。

`InteractionSession` 的初始实现位于 Host：纯
`InteractionState reduce(InteractionState, InteractionEvent)` reducer 负责
三个并行 lane、`SessionId` / `TurnId` / `ResponseEpoch`、pending
`InteractionEnvelope`、delivery projection 和 interruption policy；薄
Coordinator 在 reducer 外调用 ChatRepository、SpeechInput、SpeechOutput
等副作用。全局事件序号由 Coordinator 分配，Tool / Proposal / 外部副作用
才附加 `OperationId`。

Voice barge-in 必须分两阶段：

```text
speech_started → BargeInCandidate → duck/pause output
                 → sustained speech or valid ASR text
                 → BargeInCommitted → epoch++ / stale output discarded
```

噪声、咳嗽和扬声器残余回声可以成为 `false_interruption`，恢复原 epoch。
`ResponseEpoch` 只让旧的 LLM/TTS/UI 结果失效，不回滚已提交的业务副作用。
Pending `InteractionEnvelope` 优先于普通新 Turn；语音不能绕过 approval 或
typed confirmation。

Assistant 的完整生成文本、用户实际听到的内容、下一轮模型看到的内容必须
分开管理：

```text
GeneratedText → 本地 trace/debug
DeliveryLedger → 每个输出 channel 已完成的 segment id
ContextProjection → 已交付前缀 + interrupted 标记
```

第一版只记录 segment id，不使用未定义的跨 Dart/Rust `usize` 偏移。

### 5.2 Calm 视觉

AI 元素使用 surface tone、细线图标、克制的 cursor 动效和 outline reply chip。
禁止 glow、neon gradient、机器人头像、悬浮聊天气泡和独立 AI tab。视觉原语位于
`core/ai/visual/`。

### 5.3 Review Gate

- [ ] 入口经过 `AiIntentInvocation`，intent 已注册
- [ ] 默认在当前页面打开 bottom sheet
- [ ] 文案描述对象动作，不使用泛化的“Ask AI”
- [ ] 交互模式由 proposal 风险和副作用派生
- [ ] 新 surface 写入完整 invocation trace
- [ ] UI 遵循 Calm 视觉约束
- [ ] 摄取草稿在用户确认前不进入 journal 或同步表
- [ ] Voice turn 携带 `inputOrigin`，而不是重新创建一套 Agent loop
- [ ] Barge-in 区分 candidate 与 committed interruption
- [ ] Undelivered assistant output 不进入下一轮 voice context

### 5.10.7 反模式

- 悬浮聊天气泡、独立 AI tab、随处散落的 sparkle 或魔法棒
- 打开应用先展示 chat，而不是用户数据和任务
- 让 LLM 直接计算业务金额或绕开工具给出交易指令
- 把转账、下单等外部副作用做成一句话自动执行

## 6. 当前代码地图

```text
apps/mobile/lib/core/ai/
  agents/          domain-neutral agent framework and UI primitives
  contracts/       context, tool, proposal, trace contracts
  intent/          AiIntentInvocation and policy
  session/         InteractionSession ids, events, reducer, delivery, interruption policy
  llm_credentials/ profiles and secure credential seams
  local/           embedding, memory, deterministic skills
  runtime/         host-neutral runtime seams and device tool contracts
  trace/           local trace storage and providers
  visual/          shared AI visual primitives
  write/           proposal application, interaction mode, undo/touched state

apps/mobile/lib/app/agent_runtime/
  bridges/         stable Dart APIs over generated FRB bindings
  chat/            ChatTurn frame mapping and device-tool continuation
  context/         active-domain Memory -> untrusted ContextBlocks
  catalog/         DomainPack -> runtime catalog
  persistence/     checkpoint/effect journal
  runner/          profile turn and embedded runtime composition
  tools/           production device-tool host
  trace/           runtime result -> AiTraceStore

apps/mobile/lib/app/interaction/
  interaction_session_coordinator.dart  thin side-effect coordinator
  interaction_chat_session.dart         ChatRepository-backed host composition
  speech_output_bridge.dart              serialized output and delivery bridge
  agent_event_adapter.dart               Chat event -> session projection
  turn_arbiter.dart                     interruption and turn policy
  voice_interaction_adapter.dart        Speech/Chat/HITL adapters

apps/mobile/lib/core/speech/
  speech input/output capabilities, the existing SpeechRecognizer seam, and
  the Android-only native AudioRecord capture seam

apps/mobile/android/app/src/main/kotlin/com/naviwealth/naviwealth/
  AndroidSpeechBridge.kt  Android API 31+ on-device semantic speech bridge
  AndroidAudioCaptureBridge.kt  Android native capture, VAD and ASR lifecycle
  NativeSherpaStreamingRecognizer.kt  Kotlin semantic handle for JNI ASR
  NativePcmRingBuffer.kt  bounded native-only PCM buffer

apps/mobile/android/app/src/main/cpp/
  sherpa_streaming_jni.cpp  JNI bridge to the packaged sherpa-onnx C API

apps/mobile/lib/features/ai_chat/
  data/            context window, structured checkpoint summarizer/store use
  domain/          conversation checkpoint payload
```

Android still selects the platform on-device recognizer by default. The system
provider owns its own recorder through `AndroidSpeechBridge`; this remains the
production-safe first choice and does not require a downloaded model. The
opt-in `localZipformer` provider reuses the existing `SpeechRecognizer` seam,
checks the shared model installer for
`streaming-zipformer-large-ctc-zh-int8-2025-06-30`, and passes the installed
directory to the native bridge. A missing local model is reported as
`modelNotInstalled`; it never triggers a cloud fallback.

When `localZipformer` is selected, the Android hot path is:

```text
AudioRecord (VOICE_COMMUNICATION, 16 kHz mono PCM16)
  -> platform AEC / NS / AGC (best effort)
  -> one native capture thread
       ├─> NativeEnergyVad (semantic speech boundaries)
       ├─> JNI -> packaged sherpa-onnx C API
       │       └─> Streaming Zipformer Large CTC (INT8)
       └─> NativePcmRingBuffer (2 second bounded diagnostics buffer)
```

`AndroidAudioCaptureBridge` owns the app-owned `AudioRecord` lifecycle,
`VOICE_COMMUNICATION` mode, permission handling, best-effort platform audio
effects, native VAD, and the optional native Zipformer handle. Both Android
speech bridges use the same process-local microphone lease and stop on Activity
background/destroy. The bridge emits only format/effect/VAD capabilities,
lifecycle events, semantic `speech_started` / `speech_stopped` boundaries,
partial/final transcript events, and aggregate captured/buffered/dropped-byte
counters. PCM is never sent over Flutter, FRB, logs, or persisted storage.

The JNI bridge loads the C API and C++ support libraries already supplied by
the existing `sherpa_onnx` Android FFI dependency; it does not add a second
model runtime or copy the model into the APK. Dart only resolves the existing
`<app_support>/ai-models/` bundle and receives semantic events. The shared
`SpeechRecognizer` contract therefore remains provider-neutral:

```text
SpeechRecognizer
  ├─ systemOnDevice -> Android system on-device SpeechRecognizer (default)
  └─ localZipformer -> AudioRecord -> JNI -> sherpa Streaming Zipformer
```

The first native VAD implementation is a deterministic energy gate with
hysteresis, adaptive quiet-floor tracking, and minimum speech/silence frame
durations. It is intentionally a replaceable bootstrap for a future native
Silero/Sherpa VAD; it does not become a second interaction or agent loop and
does not send confidence or audio frames across the capability boundary.

Native segment finalization feeds the trailing PCM frame to ASR before the VAD
stop boundary is emitted, and finalization is idempotent across VAD stop,
explicit stop, and Activity teardown. The semantic event order is therefore
`speech_started -> transcript updates -> final transcript -> speech_stopped ->
capture_stopped` where the corresponding signal exists.

Finance ingest 的 `FrbVisionIngestClient` 与 `UnavailableVisionIngestClient` 位于
`features/finance/ingest/`；是否允许 provider Vision 由隐私 gate 决定。Backend
路由仅负责 health、auth、me 与 sync，不存在 AI relay。

## 7. 发布检查

- `flutter analyze --fatal-infos`
- 非 golden `flutter test`
- `tool/check-ai-contract-wire-enums.sh`
- `tool/lint-frb-llm-entrypoints.sh`

Apple 平台发布前，Runner 与 Share Extension 必须使用同一个 App Group
`group.com.naviwealth.naviwealth`，并以真实 provisioning profile 验证签名归档。
