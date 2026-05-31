# `core/ai/` 边界审计（2026-05-24）

> **状态：已落地（2026-05-24，四轮）**。
> - **第一轮（A0 / A / B / C）**：删 freshness/router/RuntimeRegistry/AiRuntime 抽象等
> - **第二轮（F + CloudProposal + Backend fossil + AnalyticalUpload doc + ai-architecture.md 校准）**
> - **第三轮（G / H / I+J / K / L）**：删 disclosure 全链（DisclosureSummary/`usedRawLedger`/`disclosures`/
>   addDisclosure/LedgerField/DisclosureRequest/DisclosureResponse/UserConsent）、TaskContext 的
>   `retrieved`/`aggregates`/ScopedAggregate、ToolDescriptor.readModelLayer + ReadModelLayer enum、
>   AnonymizationLevel enum + amountAnonymization getter、3 个 l10n orphan keys
> - **第四轮（M / N / D-partial）**：删 ToolDescriptor.`allowedRuntimes` + `AllowedRuntime` enum、
>   `AiTrace.usedCloud`（持久化但零读取）、`TaskContext.analyticalUploads` 预注入 + `deviceHlc` +
>   `_buildAnalyticalUploads` 链（保留 `AnalyticalUpload` class，6 个 device tool 仍作输出 shape 用）
>
> 累计 stats（四轮合计）：~4 400 行净删除，约 55 个文件触及。
> 当前架构 SSOT 见 `docs/ai-architecture.md`。
>
> 保留本文档作历史参考，解释这轮清理"删了什么 / 留了什么 / 为什么"。
>
> ---
>
> **下面是 2026-05-24 落地前的审计原文**。审计期的建议措辞（"应删 / 推荐删除"）
> 与今天的事实可能不一致——以代码现状为准，以本节为故事背景。

> **一次性文档**。目的是把删除后端 AI 之后 `apps/mobile/lib/core/ai/` 里
> "代码已转向但抽象/注释未收敛" 的状态摊开，给出**留/删/改**三类清单。
> 不是路线图、不是重构 PR、不是新设计。审计落地完成后可删除。
>
> **范围**：`runtime/` · `router/` · `freshness/` · `local/embedding/` · `contracts/`
> · `trace/`（注释层）· `features/ai_chat/data/`（与 runtime 边界紧耦合的部分）。
> **不在范围**：`intent/` · `visual/` · `write/` · `llm_credentials/` · `local/skills/`
> （这些是当前真实在用的契约层，无明显历史残留）。

---

## 0. 三句话结论

1. **生产执行只有两种结果路径**：当 `deviceLlmAvailableProvider == true`，turn 走
   `ChatRepository → RuntimeRoutingAiChatApiClient → DeviceLlmRuntime`；否则 turn 立即
   yield `device_unavailable`。`RuntimeRegistry` 在两条路径上都不参与；`AiRouter`
   在 device 可用时**结果会被覆盖**，在 device 不可用时**留下污染 trace**（trace seed
   保留 `analyze_hybrid`，但 runtime 实际返回 `device_unavailable`——这是 router
   作为残留应当删除的更具体理由）；`FreshnessGate` 在当前唯一 production runtime
   下不可达（`DeviceAgentLoop` 不构造 `ToolResultEvent.freshness`），但 `ChatRepository`
   的 staleness 分支本身是 runtime-agnostic 的，未来若有 runtime 设置 `freshness`
   字段它仍会触发。
2. **没有"历史兼容"需要保留**。这是 local-first 单 App，没有 wire 协议向后兼容义务，
   没有外部 client 依赖 `RuntimeId.cloudAnthropic` 这个枚举值。把抽象留着只是
   "看起来还可能用上"——实际是 phantom infrastructure，新人读代码会被误导。
3. **唯一应该作为"未来保留"留下的是 `local/embedding/`**：是真正的 stub（StubEmbedder
   + InMemoryVectorStore），是 Memory Layer 的起点。但 docstring 还在引用"the cloud
   planner can receive"等已删除的概念，要改写。

---

## 1. 当前事实（current truth）

落到代码的真实运行路径：

```text
ChatRepository.sendMessage()
  → _tracePrep(ref, requestId)                      ← providers.dart:159
      · 构造 ContextPack（含 FreshnessHint / AnalyticalUploads — 都是 phantom payload）
      · 调用 router.decide(RoutingInputs(online:true)) ← 结果立即被覆盖
      · 调用 router.seedTrace(...)                   ← 同上
      · 若 deviceLlmAvailableProvider → effectiveSeed.copyWith(backend:device, ...)
  → RuntimeRoutingAiChatApiClient.chat(...)         ← providers.dart:87
      · 若 _device == null → ErrorEvent(device_unavailable) + DoneEvent
      · 否则 → DeviceLlmRuntime.run(...)
  → DeviceLlmRuntime → DeviceAgentLoop
      → AnthropicClient | OpenAiClient（用户 key 直发 provider；每轮 LLM round
        都是真实网络调用，只有 tool dispatch 是本地）
      → DriftDeviceToolDispatcher（当前 **34 个** kDeviceTools：22 基础 + 8 FIRE +
        4 Options。架构文档里的 "22 个" 是旧的数字，需要同步更新）
  → 端侧产生 LlmStreamEvent，UI 渲染，AiTraceBuilder 写 Drift `ai_traces`

替代分支（同样是"生产路径"）：
  ChatRepository → RuntimeRoutingAiChatApiClient → _unavailable()
                    （ErrorEvent(device_unavailable) + DoneEvent）
```

`RuntimeRegistry` 在两条路径上都**不参与**。`AiRouter` 在 device 可用时**结果被
覆盖**（`providers.dart:256`），在 device 不可用时**保留 router 的 `analyze_hybrid`
决策进 trace**——结果是 trace 显示 hybrid 但 runtime 实际 yield unavailable，
trace 与执行**矛盾**。这是"router 应删"的最具体证据，不是"router 不可达"。
`FreshnessGate` 在 `DeviceLlmRuntime` 下不可达，但 `ChatRepository` 的 staleness
分支与 runtime 类型无关，是真正的"幽灵"——见 §2.6。

---

## 2. 历史兼容（应删，无 caller / 永远不命中）

### 2.1 `core/ai/runtime/ai_runtime.dart`

| 行 | 内容 | 状态 |
|---|---|---|
| L1–L18 | library docstring "Today every chat goes to the cloud Anthropic relay" | **错**：与 §1 当前事实直接矛盾 |
| L36–L50 | `enum RuntimeId { cloudAnthropic, rulesDevice, deviceLlm }` 的 `cloudAnthropic` | 零生产 caller；只在 `ai_runtime_test.dart` 出现 |
| L42–L49 | `rulesDevice` enum + 整个 `RulesDeviceRuntime` (L145–L161) | 在 `providers.dart:101` 注册，但 `chat()` 永远 yield 一条 `ErrorEvent` 后立刻 done。没有任何代码 lookup 它 |
| L91–L115 | `RuntimeRegistry.pickFor(decision)` 把 `Backend.cloud/hybrid → cloudAnthropic` | 只在 `ai_runtime_test.dart` 调用，prod 完全不经过 |
| L120–L139 | `class CloudAnthropicRuntime implements AiRuntime` | **codegraph: 零 caller**。包装的 `AiChatApiClient` 也不再有 Dio 实现（`DioAiChatApiClient` 已删，docstring 在 `ai_chat_api_client.dart:2` 自己承认） |
| L165–L174 | `abstract class DeviceChatRunner` | **保留**——是 `RuntimeRoutingAiChatApiClient` 与 `DeviceLlmRuntime` 之间真实的 production seam |
| L48 | docstring "(native × key × opt-in)" | **错**：opt-in 开关已删除（架构文档 §2.2） |
| L102–L103 | docstring "Phase 1 maps... Phase 5 may insert a real device-LLM" | Phase 5 已经是唯一的 runtime，这句话谈的是已经发生的过去 |

**建议动作**：保留 `AiRuntime` / `AiRuntimeRequest` / `RuntimeId.deviceLlm` /
`DeviceLlmRuntime` / `DeviceChatRunner`。其余全删，包括 `cloudAnthropic` 枚举值、
`rulesDevice` 枚举值、`CloudAnthropicRuntime` 类、`RulesDeviceRuntime` 类、
`RuntimeRegistry.pickFor()`（保留 `lookup()` / 构造器以备 `RuntimeId.deviceLlm` trace label 用，
但更干净的做法是连 Registry 一起删——见 §4.1）。同时删 `ai_runtime_test.dart` 中
针对 dead 类的测试 case。

### 2.2 `core/ai/router/routing_policy.dart`

整个文件描述的是 "online → cloud / offline → device" 的双后端策略，**生产唯一调用方
`_prepareChatTrace` 拿到结果后立刻用 `effectiveSeed.copyWith(backend: device)` 覆盖**
（`providers.dart:256`）。

| 块 | 状态 |
|---|---|
| `_decidePlan` → `'plan_cloud'` / `Backend.hybrid` | 不可达 |
| `_decideWrite._hybrid('write_cross_cutting_cloud')` / `'write_external_typed'` | 不可达 |
| `_decideAnalyze._hybrid('analyze_hybrid')` | 不可达 |
| `_decideSummarize`（基本只 `Backend.device`） | 实际不影响最终 trace（被覆盖） |
| `RoutingDecision.backend` 字段 | 在 chat 路径上总是被强制设为 device |

**建议动作**：两个选项，选一个：
- **(a) 删 router 整模块**：`router/` 目录连同 `routing_policy.dart` / `ai_router.dart` /
  `routing_inputs.dart` / `routing_decision.dart` / `aiRouterProvider` 全删。
  `_prepareChatTrace` 直接构造 device-bound trace seed 即可。
- **(b) 收缩成"device intent 分类器"**：去掉 `Backend.hybrid` / `'plan_cloud'` 等分支，
  让 router 真的承担"端侧能不能答这个 intent / 该用 LLM 还是 template"的职责
  （和 §5 的 `intent_policy` 配合）。这是有正向价值的，但属于**重设计**，不在审计范围。

**默认推荐 (a)**，把 (b) 留作 LifeOS 北极星文档里"是否需要 router"的开放问题。

### 2.3 `core/ai/freshness/freshness_gate.dart`

整个文件存在的意义是：云端 read model 返回 `Freshness.sourceHlcWatermark`，端侧检查
"我的 op_log 是不是云端还没消费"。**没有云端 read model**。**在当前唯一
production runtime `DeviceLlmRuntime` 下**，`DeviceAgentLoop._runInner` 构造的
`ToolResultEvent` 不设 `freshness` 字段（`device_agent_loop.dart:268`），所以
staleness 分支不命中。

注意区分：`isStale()` 的**调用点**`chat_repository.dart:362` 与 runtime 无关——它会在
任何提供 `ToolResultEvent.freshness` 的 runtime 下触发。今天没人提供，不等于这条路径
是语言级 dead code。这是它属于 §4（phantom）而不是 §2（hard dead）的原因。

| 符号 | 状态 |
|---|---|
| `bool isStale({cloud, localHlcText})` | 在当前 production runtime 下不可达；但 chat_repository 仍保留调用点 |
| `class FreshnessVerdict` | grep 全仓零 caller |
| `localHlcStringProvider` | 全仓只在本文件定义，零 caller |

**建议动作**：删除整个 `freshness/` 目录 + `chat_repository.dart` 的 staleness 块 +
`providers.dart` 的 freshness 桥——前提是承诺"未来 runtime 不会复活 read-model freshness 语义"。
这个承诺在 device-only 大方向下成立；如果不愿意承诺，则降级到批 E（只改 docstring，
保留代码），但那样 `freshness/` 就该被显式标成"deliberate dormant module"。**默认推荐删**。

### 2.4 `core/ai/contracts/task_context.dart`

`FreshnessHint` 与 `AnalyticalUpload` 是为云端协作设计的 payload。当前 `_prepareChatTrace`
仍然构造它们并序列化进 `ContextPack` → 喂给端侧 LLM。Device LLM 拿到这些 JSON
**没有专门的语义处理**——它们最多作为 generic context 影响模型生成，但不再触发任何
"force_refresh_read_models" / 重投影行为。

| 符号 | 状态 |
|---|---|
| `class FreshnessHint` + `toJson()` | 序列化路径还在（喂给 LLM），但消费者已删 |
| `class AnalyticalUpload` + `toJson()` | 同上。`_buildAnalyticalUploads` 仍跑端侧 detector，但已有专门的 device tools（`get_anomaly_flags` / `get_recurring_patterns` 等）做同样的事 |
| `ContextPack.{freshnessHint, analyticalUploads}` 字段 | LLM 收到但无定向语义 |

**建议动作**：分两步，不必一次做完。
- **必做**：删 `FreshnessHint`。它的唯一"消费者"`force_refresh_read_models` 字段在
  LLM prompt 里语义模糊。同步删 `providers.dart:184–203` 构造 `FreshnessHint` 的块、
  `_prepareChatTrace` 的相关分支、`ai_trace_builder.dart:94` 的过期注释、`task_context.dart`
  里所有对 `force_refresh_read_models` 的引用。
- **可议（需测量后决策）**：`AnalyticalUpload` 同时被 device tool 暴露和 ContextPack
  pre-load。**注意：每轮 LLM 都是真实网络调用**——`DeviceAgentLoop` 每轮调
  `_streamFn(request)` 流式拿用户配置的 Anthropic/OpenAI 端点
  （`device_agent_loop.dart:189`），多一次 tool round 仍有网络延迟、token 成本和
  provider 错误风险。先前审计的"端侧 round-trip 免费"判断是错的。所以这个权衡变成：
  **预注入 context 的 token 成本 + 噪声 vs 多一次 LLM round 的延迟/成本/失败率**。
  决策应该基于实测（典型 turn 里 anomaly summary 用到的频率、平均 turn 数变化），
  而不是基于"端侧免费"的直觉。建议**先保留**，到批 D 之前补一次实测。

### 2.5 `features/ai_chat/data/providers.dart`

| 行 | 内容 | 状态 |
|---|---|---|
| L98–L104 | `runtimeRegistryProvider` 注册 `rulesDevice` + `deviceLlm` | 如果接受 §2.1 的删除建议，整个 provider 删 |
| L129–L139 | `onTraceFinalized` freshness 桥（`pendingFreshnessHintProvider` 写入）| 删（连同 §2.3） |
| L149–L151 | `pendingFreshnessHintProvider` | 删 |
| L184–L203 | `_prepareChatTrace` 里 `FreshnessHint` 构造、`pendingNames` 消费、`localHlc` 取值用于 freshness | 删；`localHlc` 在新世界里没用 |
| L246–L262 | `router.decide() → seedTrace() → effectiveSeed.copyWith(backend:device)` 三步 | 改成直接构造 device trace seed |
| L213–L241 | `compressor.compress(...)` 传入 `freshnessHint` / `analyticalUploads` / `deviceHlc` 字段 | 随 §2.4 一起精简 |
| L486–L490 | `chatSyncGateProvider` docstring "AI backend reads the user's data from D1" | docstring 错；语义上 `ChatSyncGate` 仍被 `chat_controller.dart:112` 用，但它现在等的是"OpLog flush"，跟 AI 完全无关——见 §3.1 |

### 2.6 `features/ai_chat/data/chat_repository.dart`

| 行 | 内容 | 状态 |
|---|---|---|
| L7 | `import freshness/freshness_gate.dart` | 删 |
| L351–L366 | `ToolResultEvent.freshness != null` → `traceBuilder.markStaleReadModel(...)` | 整块删（不可达） |
| `AiTraceBuilder.markStaleReadModel` / `staleReadModelNames` | 一并审计删除（注释级残留） |

---

## 3. 未来保留（deliberate stub — 改 docstring，不删）

### 3.1 `core/ai/local/embedding/`

唯一一个真正"为未来留位"的子系统：

| 文件 | 当前状态 | 应该的状态 |
|---|---|---|
| `embedder.dart` (`StubEmbedder`) | 哈希假向量，全仓 prod 无 caller，只测试用 | **保留**。docstring 引用"Phase 4 / Phase 5"语义已经混乱（Phase 5=LLM 已发），改写 |
| `vector_store.dart` (`InMemoryVectorStore`) | 线性扫描，内存内 | **保留**。docstring 提到 "sqlite-vec or HNSW 可以替换"——OK，但要明确说"等 Memory Layer contract 锁定再选" |
| `semantic_memory.dart` (`SemanticMemory`) | **codegraph: 零 caller** | **保留**，docstring 必改——L6 还在说 "the cloud planner can receive (at most top-K)"，云端 planner 不存在了 |

**这是 LifeOS Memory Layer 的天然起点**——零 prod 依赖，可以独立设计 contract
（`MemoryEntry / Chunk / EmbeddingModel / SearchQuery / SearchHit`），实现再后定。
但**当前审计不动它**，只改 docstring；contract 设计是第 3 步任务。

### 3.2 `core/ai/contracts/`（除 §2.4 提到的字段外）

`ContextPack` / `BaseContext` / `TaskContext` / `ToolDescriptor` / `ProposalEnvelope` /
`AiSpan` / `AiTrace` / `IntentHint` / `PrivacyBudget` 等是当前在用的契约，
**保留**。但 `task_context.dart` 顶部的 §4.1 / §4.2 / §4.3 等编号引用要确认每条是否
仍指向有效 §——架构文档自己已经把 §4.1–§4.5 标"已删除"，那么 contracts 文件里的引用
应该相应说明"仅作类型保留，无运行时语义"。

### 3.3 `core/ai/runtime/ai_runtime.dart` 残留部分

如 §2.1 末尾所列：`AiRuntime` / `AiRuntimeRequest` / `RuntimeId.deviceLlm` /
`DeviceLlmRuntime` / `DeviceChatRunner`。docstring 改成"device-only runtime contract;
the historical multi-backend registry has been removed."

---

## 4. Phantom infrastructure（看起来活、其实绕过——需明确决定）

### 4.1 `RuntimeRegistry`

定义在 `ai_runtime.dart:93`，注册在 `providers.dart:98`，但生产路径
`RuntimeRoutingAiChatApiClient` 直接拿 `DeviceLlmRuntime`，**完全不查 Registry**。

Registry 的唯一现存意义是 docstring 说的 "the canonical id→runtime map for trace
labelling"——但 trace 的 backend label 是在 `_prepareChatTrace` 里直接写死的
（L256–L262），也不查 Registry。

**决定**：删。如果未来真有"多 runtime 注册 + 选择"的需求（rules runtime / 本地小模型 /
云端 fallback），那是 LifeOS 北极星范围的新设计，不应该靠当前这个 dead Registry 撑着。

### 4.2 `ChatSyncGate`

虽然 docstring 说"AI backend reads user's data from D1"是错的，但 `ChatSyncGate.awaitFlush()`
实际做的是"等本地 OpLog push 到云端"——这个语义在后端 AI 删除后**是否还有意义**取决于：
device tool 直接读本地 Drift，本地写入对端侧立即可见，根本不需要等任何 flush。

唯一可能还有用的场景：用户在 A 设备录入交易，立刻在 A 设备问 AI——这是 trivially OK，
不需要 gate。**多设备场景**才需要 sync，但那时该等的是 pull 而不是 push。

**决定**：审计应该 flag "ChatSyncGate 在 device-only 世界的语义需要重新论证或删除"。
但**不在本次审计范围内自动删**——它的语义涉及 sync 与 AI 的边界，应该到 §4.4 单独处理。

### 4.3 `AiRouter` / `aiRouterProvider` 与 §2.2 重复

见 §2.2，建议删整个 router 模块。

### 4.4 `pendingFreshnessHintProvider` / `localHlc` 在 ContextPack 里

如 §2.4 / §2.5 所述，phantom payload。喂给 LLM 但没有定向语义。

---

## 5. 外部契约面（who imports `core/ai/`）

外部消费者（除 `features/ai_chat/` 和 `features/ingest/`）主要落在四类导入：

| 子系统 | 被谁用 | 性质 |
|---|---|---|
| `intent/` | `features/{home,fire,assets,expense,investment,liabilities,activity,accounts}/...` | **真实公共契约**——AI 入口协议 |
| `visual/` | 同上 | **真实公共契约**——AI 视觉原语 |
| `trace/` | `features/settings/ui/{ai_trace_waterfall,ai_transparency_page}.dart` | **真实公共契约**——透明度页 |
| `contracts/` | `risk_appetite_preferences.dart`（risk wire enum） | 局部使用 |
| `llm_credentials/` | `features/settings/ui/ai_llm_credentials_page.dart` | **真实公共契约**——Profile 管理 |

**没有任何外部 feature 直接 import `runtime/` / `router/` / `freshness/` / `local/embedding/`。**
这意味着 §2 / §3 的所有删/改在外部 surface 上是**零破坏**，影响完全局限在 `core/ai/`
和 `features/ai_chat/data/`。

---

## 6. 推荐执行顺序（不是路线图——只是分批的建议）

按"独立可合 + 影响最小"优先（注意：批 A0 必须先做，避免 A/B/C 期间读者继续被旧注释误导）：

0. **批 A0（最小成本的注释纠错，先做）**
   只改 docstring，不删任何符号：
   - `ai_runtime.dart` 顶部 library docstring（"Today every chat goes to the cloud
     Anthropic relay" / "(native × key × opt-in)" / "Phase 5 may insert..." 都要改）
   - `providers.dart` 里旧的 freshness/opt-in/no-key 文案 + `chatSyncGateProvider`
     的 "AI backend reads user's data from D1"
   - `local/embedding/semantic_memory.dart` 的 "cloud planner can receive (at most top-K)"
   - `task_context.dart` 顶部 §4.x 引用（确认每个编号是否仍指向有效 §）
   1–2 小时工作量，零行为变化，能立刻让 A/B/C 的 reviewer 看到正确语义。
1. **批 A（纯 dead code 删除，零行为变化）**
   `CloudAnthropicRuntime`、`RulesDeviceRuntime`、`RuntimeId.{cloudAnthropic,rulesDevice}`、
   `RuntimeRegistry.pickFor`、`runtimeRegistryProvider`、配套测试。
2. **批 B（freshness 整条链）**
   `freshness/` 目录、`chat_repository.dart` 的 staleness 块、`providers.dart` 的
   `pendingFreshnessHintProvider` / `onTraceFinalized` 桥、`ai_trace_builder` 的 stale
   名册字段、`FreshnessHint` contract。
3. **批 C（router 收缩或删除）**
   选 §2.2 (a)（默认推荐）或 (b)。如选 (b)，先在 LifeOS 北极星文档定位 router 的
   新职责，再动代码。
4. **批 D（ContextPack 精简——需先测量）**
   见 §2.4 修订：决策应基于"预注入 context 成本 vs 多一次 LLM round 成本"的实测，
   不能凭"端侧免费"的直觉删。建议在批 A–C 落地后再排。
5. **批 E（剩余 docstring 收敛）**
   A0 没覆盖的零散注释：`runtime/device/*.dart` 里 "phase 5 will / cloud relay 中转"
   等过期注释、删除批 A/B/C 之后留下的孤立引用。
6. **批 F（ChatSyncGate 单独论证）**
   决定是否在 device-only 世界保留 AI 触发的 sync gate；若不保留则一起删。

每批应当对应一个独立 PR，每批合并前跑：
- `flutter analyze --fatal-infos`
- `flutter test`
- `tool/check-tool-descriptors.sh` / `check-enum-mirror.sh` / `check-l10n-parity.sh`

---

## 7. 审计反目标（什么本次**不**做）

- 不重写 `docs/ai-architecture.md`。审计落地后那篇文档的 §4.1–§4.5 "兼容 / 历史"
  段落里大半应该可以删，但属于第二阶段。
- 不设计 LifeOS 北极星文档。
- 不动 `intent/` / `visual/` / `write/` / `llm_credentials/` / `local/skills/`。
- 不设计 Memory Layer contract（这是第 3 步任务）。
- 不引入 Rust。

---

**审计完成。** 落地决定由人定。
