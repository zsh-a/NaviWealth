# NaviWealth AI Chat Event Contract

Status: active wire-contract reference.

## Document Contract

Owns provider-neutral AI event names, payload shapes, stop reasons, and tool
continuation semantics. It does not own UI presentation or domain tool
behavior. Dart/Rust serializers and `docs/fixtures/ai_contract_wire_enums.json`
are authoritative for exact wire values.

The interactive chat path is device-only and runs through the FRB/native
streaming runtime. NaviWealth backend is not part of this path:

```text
ChatRepository
  -> RuntimeRoutingAiChatApiClient
  -> FrbChatRunner
  -> AgentRuntimeLlmStreamBridge (ChatTurn stream/resume) + AgentRuntimeToolHost
  -> agent-chat / agent-llm native provider + Dart device-tool dispatch
```

The Flutter bridge and TUI now share the ChatTurn request/message/tool shape.
TUI executes the shared Rust `agent-chat` continuation loop directly; Flutter
maps primitive ChatTurn-style FRB stream frames into the existing
`AiChatEvent` vocabulary, dispatches device tools in Dart, then resumes the
Rust-owned loop with `chat_state` and `tool_results`.

The repository/UI contract uses `AiChatEvent` for chat history, stream
rendering, cancellation, and trace capture. Events are in-process Dart stream
events mapped from FRB primitive JSON frames, not backend SSE frames.

Production domain agents, profile-turn business seams, Settings connectivity
probing, Vision ingest, and interactive AI Chat use the FRB/native runtime path described in
[`ai-architecture.md`](./ai-architecture.md) and
[`../architecture/agent-runtime-current.md`](../architecture/agent-runtime-current.md).
This file defines the interactive AI Chat streaming event vocabulary exposed by
that FRB runner.

## Events

| event class | payload |
| --- | --- |
| `TextEvent` | visible assistant text delta |
| `ThinkingDeltaEvent` | provider reasoning delta shown in the folded reasoning panel |
| `ToolCallStartEvent` | `{ id, name }` when the model starts a tool call |
| `ToolCallDeltaEvent` | `{ id, partialInputJson }` while tool JSON is still incomplete |
| `ToolCallEvent` | `{ id, name, input }` once final tool input is available |
| `ToolResultEvent` | `{ id, name, output }` after the device dispatcher returns |
| `UsageEvent` | token accounting for the current provider round |
| `SpanEvent` | Opik-style trace span for turn / LLM round / tool execution |
| `ErrorEvent` | `{ message, code? }` for runtime or provider failures |
| `DoneEvent` | `{ stopReason, rounds }` terminal marker |

`ToolCallDeltaEvent.partialInputJson` may not parse until the matching
`ToolCallEvent` arrives. Consumers that need stable input should use
`ToolCallEvent.input`.

### Round boundaries

`round_finished` closes one native provider round; it is not by itself the end
of the user turn. For a completed, refused, or otherwise terminal round, the
native stream must emit a following `done` frame. If that frame is missing,
Flutter fails the turn with `frb_chat_terminal_done_missing` instead of
showing a premature `end_turn`. A round with
`status: "requires_tool_results"` must not emit `done`; Flutter dispatches the
validated calls and resumes the native loop with their results.

## Stop Reasons

`DoneEvent.stopReason` follows provider stop names where available:

| reason | meaning |
| --- | --- |
| `end_turn` | The assistant completed the turn normally. |
| `max_tokens` | The provider stopped because the output token limit was reached. |
| `tool_use` | The provider requested more tool execution than the loop allows. |
| `requires_interaction` | The turn is paused until the user answers a structured decision. |
| `refusal` | The provider refused the request. |
| `error` | The runtime stopped after an error. An `ErrorEvent` should also be present. |

## Device Availability

Web and native installs without an active user LLM profile do not fall back to
cloud. `RuntimeRoutingAiChatApiClient` emits:

```text
ErrorEvent(code: "device_unavailable")
DoneEvent(stopReason: "error", rounds: 0)
```

The UI should guide the user to configure a provider profile in Settings.
Settings profile tests use `FrbLlmConnectivityProbe`; the `device_unavailable`
events above are specific to the interactive chat client.

## Tool Catalog

The active tool catalog is mobile-local. Internal agents receive the full
catalog from active `DomainPack`s. Interactive Assistant dispatch receives a
route-scoped catalog: shell tools plus the current domain, or all active
user-visible domain tools in the global `/assistant` workspace. Advanced
Finance tools are added only on their owning Plan routes. Composition is wired
by `lifeOsDomainCompositionOverrides`; the full production diagnostic catalog
lives in `apps/mobile/lib/app/production_ai_catalog.dart`. Each domain
co-locates tool registrations, Assistant visibility, and `ToolDescriptor`
metadata with its own tool barrel. Dispatch authorization follows descriptor
access/side-effect metadata, never a tool-name prefix.

Run from the repository root:

```bash
./tool/check-ai-contract-wire-enums.sh
cd apps/mobile
flutter test test/core/ai/contracts/contracts_roundtrip_test.dart \
  test/core/ai/runtime/device/device_degradation_test.dart
```

The manifest check pins wire enum strings. The Dart tests pin descriptor
roundtrips and the bidirectional production registry. The retired backend
`tool_descriptor_dump` and Rust enum mirror no longer exist.

## Decision Points (`ask_user`)

High-impact / ambiguous forks are modelled as a **structured action**, not
free-text the Host has to parse (Claude-Code / Codex style). When the model
hits such a fork it calls the shell tool **`ask_user`** with a typed
`decision_request`:

```jsonc
{
  "type": "decision_request",
  "title": "状态管理方案选择",
  "context": "本地优先 + 可同步 + AI 可读写。",
  "options": [
    { "id": "riverpod", "label": "Riverpod + Drift",
      "description": "…", "pros": ["…"], "cons": ["…"], "recommended": true },
    { "id": "bloc", "label": "BLoC + Repository", "pros": ["可测试性强"] }
  ],
  "allow_custom": true
}
```

Flow:

1. `AskUserTool.invoke` validates + normalises and echoes the request as the
   `tool_result` (2–4 options, each with a non-empty `label`).
2. The agent loop treats `ask_user` as **terminal**: it records the result and
   **pauses** with `requires_interaction` instead of re-invoking the model —
   the model never answers its own question.
3. The Host renders `DecisionCard` (`features/ai_chat/ui/decision_card.dart`)
   from the parsed `decision_request`; only the trailing turn's decision is
   interactive.
4. The user's pick is written back as the next user turn
   (`我选择「…」。请在此方案下继续。`) and the agent continues under that
   constraint.

The Host must also make the decision visible to the next model turn. Flutter
persists the selected option on the original `ToolInvocation` as
`decision_selection` and `buildContextWindow` serializes completed `ask_user`
tool calls into a compact assistant transcript:

```text
Decision requested: <title>
Context: <context>
Options:
- <id>: <label> — <description> (recommended)
Selected option: <id> (<label>)
User reply: <reply>
```

This prevents a follow-up such as "我选择 A" from losing the original option
set when the prior assistant turn had no visible text body.

Turn-scoped metadata is typed in Flutter as `ChatTurnMetadata`. It is converted
to runtime JSON only at the `AiChatApiClient` boundary:

| field | runtime metadata |
| --- | --- |
| `decision.selection` | `decision` |
| `decision.messageId` | `decision_message_id` |
| `decision.toolInvocationId` | `decision_tool_invocation_id` |
| `invocationTrace` | `invocation` |

The TUI consumes the same `ChatTurnEvent` stream. When it sees a
`tool_result` from `ask_user` with `type: "decision_request"`, it renders a
numbered terminal decision list instead of raw JSON, then waits for the user's
next natural-language input. The shared fixture is
`docs/fixtures/agent_chat_ask_user_turn_events.json`.

Policy for *when* to ask lives in `kDeviceSystemPromptBase` (clauses 12–14).
This supersedes the earlier markdown-menu string parsing.
