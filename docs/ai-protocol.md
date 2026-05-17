# NaviWealth AI Runtime Event Contract

W-D7 removed the cloud AI backend and the `/ai/chat` SSE endpoint. The active
chat path is device-only:

```text
ChatRepository
  -> RuntimeRoutingAiChatApiClient
  -> DeviceLlmRuntime
  -> AnthropicClient + DriftDeviceToolDispatcher
```

The repository/UI contract still uses the old event vocabulary so chat history,
stream rendering, cancellation, and trace capture did not need a rewrite. These
events are now in-process Dart stream events, not backend SSE frames.

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

## Tool Catalog

The active tool catalog is mobile-local. `kDeviceTools` in
`apps/mobile/lib/core/ai/runtime/device/tools/device_tool_registry.dart` is the
dispatch allow-list, and
`apps/mobile/lib/core/ai/contracts/tool_descriptor.dart` carries metadata for
exactly that advertised set.

Run from the repository root:

```bash
./tool/check-tool-descriptors.sh
./tool/check-enum-mirror.sh
```

Both scripts now run the Dart contract tests; the retired backend
`tool_descriptor_dump` and Rust enum mirror no longer exist.
