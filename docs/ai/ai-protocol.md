# NaviWealth AI Chat Event Contract

The cloud AI backend and the `/ai/chat` SSE endpoint were removed. The active
interactive chat path is device-only and runs through the FRB/native streaming
runtime:

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

The repository/UI contract still uses the old event vocabulary so chat history,
stream rendering, cancellation, and trace capture did not need a rewrite. These
events are now in-process Dart stream events mapped from FRB primitive JSON
stream frames, not backend SSE frames.

Production domain agents, profile-turn business seams, Settings connectivity
probing, Vision ingest, and interactive AI Chat use the FRB/native runtime path described in
[`ai-architecture.md`](./ai-architecture.md) and
[`../architecture/rust-agent-runtime-mvp.md`](../architecture/rust-agent-runtime-mvp.md).
This file defines the interactive AI Chat streaming event vocabulary retained by
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

## Stop Reasons

`DoneEvent.stopReason` follows provider stop names where available:

| reason | meaning |
| --- | --- |
| `end_turn` | The assistant completed the turn normally. |
| `max_tokens` | The provider stopped because the output token limit was reached. |
| `tool_use` | The provider requested more tool execution than the loop allows. |
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

The active tool catalog is mobile-local. Runtime dispatch is assembled from
active `DomainPack`s via `lifeOsDomainCompositionOverrides`; the full production
diagnostic catalog lives in `apps/mobile/lib/app/production_ai_catalog.dart`.
Each domain co-locates tool registrations and `ToolDescriptor` metadata with
its own tool barrel.

Run from the repository root:

```bash
./tool/check-tool-descriptors.sh
./tool/check-enum-mirror.sh
```

Both scripts now run the Dart contract tests; the retired backend
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
   **pauses** (ends the turn on `end_turn`) instead of re-invoking the model —
   the model never answers its own question.
3. The Host renders `DecisionCard` (`features/ai_chat/ui/decision_card.dart`)
   from the parsed `decision_request`; only the trailing turn's decision is
   interactive.
4. The user's pick is written back as the next user turn
   (`我选择「…」。请在此方案下继续。`) and the agent continues under that
   constraint.

Policy for *when* to ask lives in `kDeviceSystemPromptBase` (clauses 12–14).
This supersedes the earlier markdown-menu string parsing.
