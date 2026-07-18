# NaviWealth AI 架构

NaviWealth 的 AI 是 device-only。原生端通过 flutter_rust_bridge（FRB）进入
Rust agent runtime，再使用用户自己的 `LlmProfile` 直连 Anthropic 或
OpenAI-compatible provider。Backend 不持有模型密钥、不转发 AI 请求；Web 不加载
AI runtime。

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

### 2.3 凭证与平台

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

### 3.3 Trace

唯一执行记录是 Opik 风格 `AiSpan` 树：`turn` / `llm` / `tool`、父子关系、耗时、
token、model、stop reason、状态和可选 I/O。`ai_traces`、`ai_undo_stack` 与
`ai_touched_entities` 均为 local-only。

## 4. Device LLM Runtime 契约

- **§4.1 ContextPack**：由 BaseContext、TaskContext（`route` / `intent` /
  `signals`）和 PrivacyBudget 组成，只在端侧构造和消费。
- **§4.2 本地真值**：工具直接读取 Drift 或端侧 provider。
- **§4.3 写入边界**：所有写入和外部动作遵循 §3.2。
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
  llm_credentials/ profiles and secure credential seams
  local/           embedding, memory, deterministic skills
  runtime/         host-neutral runtime seams and device tool contracts
  trace/           local trace storage and providers
  visual/          shared AI visual primitives
  write/           proposal application, interaction mode, undo/touched state

apps/mobile/lib/app/agent_runtime/
  bridges/         stable Dart APIs over generated FRB bindings
  chat/            ChatTurn frame mapping and device-tool continuation
  catalog/         DomainPack -> runtime catalog
  persistence/     checkpoint/effect journal
  runner/          profile turn and embedded runtime composition
  tools/           production device-tool host
  trace/           runtime result -> AiTraceStore
```

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
