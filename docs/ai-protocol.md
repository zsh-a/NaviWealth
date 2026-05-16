# NaviWealth AI SSE Protocol

`POST /ai/chat` streams assistant output as Server-Sent Events. The endpoint
supports two wire protocols so existing mobile clients keep their current v1
behavior while newer clients can consume provider-neutral `AgentEvent` data.

## Version negotiation

Clients opt in to v2 by sending:

```http
X-Naviwealth-AI-Protocol: 2
```

Missing headers, `X-Naviwealth-AI-Protocol: 1`, and any other value use the v1
compatibility stream. This keeps old mobile builds working unchanged while v2
rolls out behind an explicit client header.

The existing `Sync-Protocol-Version` header is still validated separately for
sync-domain compatibility and does not select the AI SSE event shape.

## v2 events

Each frame uses the standard SSE shape:

```text
event: <event_name>
data: <json_payload>

```

The v2 stream maps each backend `AgentEvent` to one SSE frame.

| event | payload |
| --- | --- |
| `text_delta` | `{ "text": "..." }` |
| `thinking_delta` | `{ "text": "..." }` |
| `tool_call_start` | `{ "id": "...", "name": "..." }` |
| `tool_call_delta` | `{ "id": "...", "partial_input_json": "..." }` |
| `tool_call_end` | `{ "id": "...", "input": { ... } }` |
| `tool_result` | `{ "id": "...", "name": "...", "output": { ... } }` |
| `usage` | `{ "input": 0, "output": 0, "cache_read": 0, "cache_write": 0 }` |
| `stop` | `{ "reason": "...", "rounds": 0 }` |
| `error` | `{ "code": "...", "message": "..." }` |

`text_delta` and `thinking_delta` are incremental. Clients should append deltas
in arrival order rather than treating each frame as a complete message.

`tool_call_delta.partial_input_json` is a raw partial JSON string. It may not be
valid JSON until the matching `tool_call_end` arrives. Clients that need a
stable tool input should use `tool_call_end.input`.

`usage` values are token counts:

| field | meaning |
| --- | --- |
| `input` | Non-cache input tokens billed for the current provider message. |
| `output` | Output tokens emitted by the provider. |
| `cache_read` | Input tokens read from provider prompt cache. |
| `cache_write` | Input tokens written to provider prompt cache. |

## Stop reasons

`stop.reason` is one of:

| reason | meaning |
| --- | --- |
| `end_turn` | The assistant completed the turn normally. |
| `max_tokens` | The provider stopped because the output token limit was reached. |
| `tool_use` | The provider requested tool execution. The backend may continue with another round. |
| `refusal` | The provider refused the request. |
| `error` | The backend stopped after an error. An `error` event should also be present. |

`stop.rounds` is the number of agent loop rounds completed for the request.

## v1 compatibility

v1 remains the default. The backend keeps the existing compatibility sink:

| v1 event | behavior |
| --- | --- |
| `text` | Text deltas are accumulated and flushed as a single `{ "text": "..." }` payload before tool, error, or done frames. |
| `tool_call` | Emitted from completed tool calls with `{ "id", "name", "input" }`. |
| `tool_result` | Emitted with `{ "id", "name", "output" }`. |
| `done` | Emitted with `{ "stop_reason", "rounds" }`. |
| `error` | Emitted with `{ "message", "code" }`. |

Reasoning deltas, tool-call input deltas, and usage events are intentionally
hidden from v1 clients.

## Mobile parser notes

Mobile now opts in to v2 by default by sending
`X-Naviwealth-AI-Protocol: 2`. Build with `--dart-define=AI_PROTOCOL=v1` to
force the v1 compatibility stream for rollback. `AI_PROTOCOL=v2` is the default.

The mobile parser:

- Dispatch on the nine v2 event names above.
- Append `text_delta.text` into the visible assistant answer.
- Append `thinking_delta.text` into a separate reasoning buffer rendered in the
  assistant bubble's folded reasoning panel.
- Treat `tool_call_delta.partial_input_json` as an optional preview only.
- Use `tool_call_end.input` as the complete tool input.
- Persist and surface `usage` token counts on the assistant message debug line.
- Treat `stop` as the terminal event for a completed stream.

`apps/mobile/lib/core/ai/contracts/tool_descriptor.dart` mirrors the backend
tool descriptor dump. Run `tool/check-tool-descriptors.sh` from the repository
root to compare the Dart mirror against
`cargo run --bin tool_descriptor_dump`.
