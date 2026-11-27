# Navi Assistant

Host-independent, bounded agent execution for NaviWealth. The crate embeds
`rpi-agent` and `rpi-ai` from pi-rust v0.29.0, pinned to commit
`6d697126b4149fd1fd69d4c741c6103b37ddc615`. It installs no coding tools, plugins,
CLI, server or SQLite backend.

Call `run` on a Tokio runtime with an owner-configured provider, serialized
history, a new submitted prompt and explicit host tools. `ToolHandler` performs
only the operations the application registers. The application owns consent,
draft confirmation, business transactions and persistence. Tool failures use
safe machine-readable codes; raw upstream diagnostics are not exposed.

`Event::Checkpoint` contains the complete transcript, retaining native message,
tool-call and reasoning identities. Persist it on the host. Restoring history
does not execute anything; a new submitted turn is required. Interrupted calls
receive error results indicating an unknown outcome, rather than being replayed.
The host must still make proposed mutations idempotent and confirm them before
writing business data; persisted conversation is not an exactly-once transaction.

Defaults are eight provider requests, 150 seconds total, 4096 output tokens and
a 120,000-byte serialized context window. When a submitted turn would exceed
that window, the same configured model may summarize earlier complete turns.
At most two summary requests, each with a bounded input, share the run's request
budget, deadline and cancellation; no tools are supplied to these requests.
Recent turns and their tool-call/result groups remain intact. A failed or
impossible summary falls back to complete-turn trimming with `ContextTrimmed`;
the original history remains available to the host in either case.

Pass a saved `ContextSummary` in `Config.context_summary` to reuse it. Its
message boundary and SHA-256 digest bind it to a complete native history prefix.
`validate_context_summary` rejects stale or malformed pairs. `SummaryStarted`
is a progress event; `SummaryUpdated` carries the summary and full history for
one atomic host save. The result also carries the latest summary. Summaries are
quoted untrusted conversation data in model input, never system instructions,
owner approval or cross-session memory. Generating, restoring or replaying a
summary never executes a historical tool call. Cross-session memory remains an
explicit host tool.

HTTP adapters use the owner's explicit credentials and never fall back to
environment credentials or follow redirects. HTTP endpoints remain supported
for an explicitly configured local model service; endpoint consent belongs to
the application. Keyless Chat Completions sends no authentication header.
The pinned Responses adapter requires an authentication header name, so a
keyless Responses profile sends an explicitly empty `Authorization` header.
It sends no credential and never inherits an environment key; servers that
reject empty headers need an explicit key or a later upstream anonymous-mode
adapter. Anthropic profiles still require their configured key.

Validation:

```sh
rtk cargo fmt --manifest-path crates/navi-assistant/Cargo.toml --all -- --check
rtk cargo clippy --manifest-path crates/navi-assistant/Cargo.toml --all-targets --locked -- -D warnings
rtk cargo test --manifest-path crates/navi-assistant/Cargo.toml --locked
```

Tests include real local SSE protocol fixtures for Anthropic Messages, OpenAI
Chat Completions and OpenAI Responses; deterministic multi-step runs and
continuation; cancellation; bounded execution and context; and error redaction.
