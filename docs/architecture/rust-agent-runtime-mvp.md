# Rust Agent Runtime MVP

This is the first implementation slice of
`docs/architecture/rust-agent-runtime-design.md`.

## Scope

Implemented:

- schema-first wire contracts under `schemas/agent-runtime/`
- committed valid/invalid fixtures under `fixtures/agent-runtime/`
- Rust workspace crates:
  - `agent-core`: DTOs, traits, errors, trace contracts
  - `agent-llm`: provider-neutral LLM DTOs, provider trait, mock provider,
    OpenAI-compatible provider, Anthropic provider, Ollama-compatible local
    provider
  - `agent-runtime`: scheduler, runner, in-memory registry, trace capture,
    timeout policy, run concurrency limiting, per-agent/scope lease locking
  - `agent-store`: in-memory and file-backed run/state stores
  - `agent-cli`: `agent list`, `agent run`, `agent tick`, `agent replay`,
    `agent inspect`, `agent debug-bundle export`
- example registry and fixture under `examples/agent-runtime/`
- JSON Schema contract tests using `jsonschema`
- Flutter active-domain catalog export via `agentRuntimeCatalogProvider`
- headless JSONL stdio server via `agent serve --stdio`
- headless HTTP server via `agent serve --host 127.0.0.1 --port 8765`
- external process tool-host bridge via `--tool-host`
- deterministic mock tool overrides via `--mock-tool`
- declarative external tool-source manifests via `--tool-source`
- direct MCP stdio tool-source adapter via `protocol: "mcp_stdio"`
- direct HTTP JSON tool-source adapter via `protocol: "http_json"`
- direct tool debugging via `agent tool list` and `agent tool call`
- prompt/model/tool schema manifest via `agent catalog prompt-manifest`
- proposal / approval DTOs, apply/undo hooks, file store, and CLI commands
- provider-neutral LLM request/response contracts, deterministic mock provider,
  OpenAI-compatible `/chat/completions` provider, and Anthropic Messages
  provider, and Ollama-compatible local `/api/chat` provider
- Flutter/Dart `tool.call` adapter via `AgentRuntimeToolHost`
- Flutter/Dart headless provider-container adapter via
  `createAgentRuntimeHeadlessToolHost`
- pure Dart process-safe shell tool host via
  `dart run bin/agent_runtime_tool_host.dart --shell`
- deterministic catalog dry-run evals via `agent eval`
- eval expected tool call sequence checks via `expect.tool_calls`
- eval process scoring hooks via `scoring_hook.command` and `min_score`
- shared HookEvent schema and eval report hook invocation records
- traced `AgentServices` state read/write events
- eval YAML contract at `schemas/agent-runtime/eval-case.schema.json`
- eval generation from persisted runs via `agent eval create --from-run`
- markdown workflow command generation from persisted runs via
  `agent cmd create --from-run`
- reusable markdown workflow execution via `agent cmd run`
- session / thread / step DTOs with JSON Schema fixtures
- file-backed and in-memory session stores for session, thread, and step
  records
- CLI session workflow: `agent session create/list/show/fork`
- optional `agent run --session --thread` metadata and agent-run step capture
- HTTP session endpoints for server-first clients:
  `GET/POST /sessions`, `GET /sessions/{session_id}`,
  `POST /sessions/{session_id}/fork`
- HTTP run inspection endpoints for server-first clients:
  `GET /runs`, `GET /runs/{run_id}`, `GET /runs/{run_id}/trace`,
  `GET /runs/{run_id}/events`,
  `POST /runs/{run_id}/replay`
- store-backed observability metrics via `agent metrics summary` and
  `GET /metrics/summary`
- TOML runtime config and profile loading via top-level `--config` /
  `--profile`, plus `agent config show`
- stale `running` run recovery via `agent recover` and
  `agent_runtime::recover_stale_runs`
- persisted run idempotency keys derived from agent id, run scope, trigger kind,
  and `metadata.scheduled_for`
- traced tool call envelopes with `tool_call_id`, BLAKE3 input hash, duration,
  status, output/error payloads, and a JSON Schema fixture
- executable trace replay via `agent replay --execute`
- file-store trace persistence and debug bundle export for local reproduction
- minimal OpenAPI 3.1 contract at `openapi/agent-runtime-api.yaml`
- CLI JSON Schema validation gate via `agent validate`
- ratatui/crossterm terminal UI via `agent tui`
- FRB-facing native JSON contract bridge in
  `apps/mobile/native/lifeos_native/src/api/agent_runtime.rs`
- generated FRB bindings for the native agent-runtime bridge under
  `apps/mobile/lib/src/rust/api/agent_runtime.dart`
- Dart-side app provider wiring via `agentRuntimeNativeBridgeProvider` and
  `agentRuntimeNativeCatalogSummaryProvider`
- FRB-facing LLM request/response contract validation and deterministic mock
  LLM completion via `agentRuntimeValidateLlmRequest`,
  `agentRuntimeValidateLlmResponse`, and `agentRuntimeCompleteMockLlm`
- Dart-side `AgentRuntimeLlmBridge` that maps the active on-device
  `LlmProfile` into the provider-neutral `agent-llm` request shape for FRB
- FRB-facing profile-backed LLM completion via
  `agentRuntimeCompleteProfileLlm`, using device-local profile metadata for
  OpenAI-compatible and Anthropic-compatible HTTP providers
- FRB-first native run-step contract via `agentRuntimeStartRunStep`, which
  validates the active catalog/run request and returns either a completed
  dry-run step or a `tool_call_requested` step for Dart-side device dispatch
- FRB-first native continuation contract via `agentRuntimeContinueRunStep`,
  which accepts the previous native step plus the Dart-side tool response and
  returns a completed or failed native step
- Dart-side `AgentRuntimeNativeStepRunner` that performs a bounded embedded
  tool loop: FRB start step -> Dart `AgentRuntimeToolHost` dispatch -> FRB
  continuation step, repeated until a terminal native step or the tool-call
  budget is exhausted
- Dart-side `AgentRuntimeProposalBridge` that parses ready proposal envelopes
  from terminal FRB steps and, after an explicit caller confirmation, dispatches
  them through the existing cross-domain `ProposalApplier`
- Dart-side `AgentRuntimeConfirmedProposalRunner` that composes the bounded
  FRB step runner with the proposal bridge for explicit confirmed-proposal
  execution
- UI-callable `agentRuntimeConfirmedProposalRunProvider` FutureProvider entry
  point for running a confirmed FRB proposal request
- Active-catalog variant
  `agentRuntimeConfirmedProposalActiveCatalogRunProvider`, so UI callers can
  use the current domain composition without manually passing catalog JSON
- Dart-side `AgentRuntimeProfileTurnRunner` and
  `agentRuntimeProfileTurnRunnerProvider`, which compose active-profile FRB
  LLM completion with the bounded native FRB step/tool loop and return both the
  LLM response and terminal native step
- A user-facing FRB runtime check on Settings -> AI provider, which runs one
  active-profile turn through `AgentRuntimeProfileTurnRunner` and displays the
  terminal native step status
- A guarded confirmed-proposal surface on that runtime check: if the terminal
  FRB step carries a ready proposal, Settings shows the summary/warnings and
  applies it through `AgentRuntimeProposalBridge` only after explicit user
  confirmation

Deferred:

- complete embedded Rust runner loop over FRB beyond deterministic step
  contracts, promoting the current Dart composition seam into a fuller native
  runner as the Rust runtime grows
- standalone app-backed process entry for data-backed tools. The
  library adapter works under Flutter tests, but `dart run` over Drift native
  currently hits a Dart VM FFI compiler crash in `sqlite3 3.3.3`
  (`NativeCallable.isolateLocal`) on the local latest toolchain.
- first production agent migration onto the embedded Rust runner

## Commands

List available example agents:

```bash
rtk cargo run -p agent-cli -- list \
  --registry examples/agent-runtime/agents.yaml
```

Run the example echo agent and write a trace:

```bash
rtk cargo run -p agent-cli -- run echo_agent \
  --registry examples/agent-runtime/agents.yaml \
  --input examples/agent-runtime/fixtures/echo-input.json \
  --trace-out /private/tmp/agent-runtime-echo-trace.json \
  --store /private/tmp/agent-runtime-store
```

`agent run` also writes the run trace into the configured file store under
`traces/<run-id>.trace.json`. `--trace-out` is an additional export path for
scripts or ad-hoc debugging.

Replay a trace in view mode:

```bash
rtk cargo run -p agent-cli -- replay \
  /private/tmp/agent-runtime-echo-trace.json \
  --mode view
```

Run deterministic replay without invoking tools or writing a new run:

```bash
rtk cargo run -p agent-cli -- replay \
  /private/tmp/agent-runtime-echo-trace.json \
  --mode deterministic \
  --trace-out /private/tmp/agent-runtime-echo-deterministic-trace.json
```

Execute live replay from a trace:

```bash
rtk cargo run -p agent-cli -- replay \
  /private/tmp/agent-runtime-echo-trace.json \
  --mode live \
  --registry examples/agent-runtime/agents.yaml \
  --trace-out /private/tmp/agent-runtime-echo-replay-trace.json \
  --store /private/tmp/agent-runtime-store
```

`--execute` remains supported as a compatibility alias for `--mode live`.
Deterministic replay reuses the source trace output and timestamps. Live replay
reconstructs the original input from the trace, runs the same agent with
`trigger: replay`, writes a new run/trace, and reports whether the new output
matches the source trace output.

Inspect a persisted run record:

```bash
rtk cargo run -p agent-cli -- inspect run_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --store /private/tmp/agent-runtime-store
```

Open the terminal UI for catalog, trace, and file-store inspection:

```bash
rtk cargo run -p agent-cli -- tui \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --trace fixtures/agent-runtime/trace.valid.json
```

For CI and smoke tests, render one frame with ratatui's test backend:

```bash
rtk cargo run -p agent-cli -- tui \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --trace fixtures/agent-runtime/trace.valid.json \
  --once
```

Validate a JSON fixture against a runtime schema:

```bash
rtk cargo run -p agent-cli -- validate \
  schemas/agent-runtime/run-request.schema.json \
  fixtures/agent-runtime/run-request.valid.json
```

Invalid instances print a JSON report with schema errors, then exit non-zero.

Export a debug bundle for a persisted run:

```bash
rtk cargo run -p agent-cli -- debug-bundle export \
  run_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --store /private/tmp/agent-runtime-store \
  --out /private/tmp/agent-runtime-debug-bundle \
  --catalog fixtures/agent-runtime/catalog.valid.json
```

The bundle currently writes:

```text
manifest.json
run_record.json
run_request.json
run_result.json
replay_config.json
trace.json
events.jsonl
tool_calls.jsonl
agent_spec.json
prompt_manifest.json
state_snapshot.json
redactions.json
```

`run_request.json` is reconstructed from the stored run record with
`trigger: replay`; it preserves the original run input and run id for replay
or eval authoring. `replay_config.json` records the replay mode, source store,
catalog path, timeout, bundle asset names, suggested `agent replay --execute`
command, and the reconstructed run request. `state_snapshot.json` captures
persisted runtime context related to the run: run status, session/thread/step
records when the run was attached to a session, and proposal envelopes for the
run.
When `--catalog` is provided and the run's agent is found,
`prompt_manifest.json` records the same prompt/model/tool schema manifest as
`agent catalog prompt-manifest`; `replay_config.assets.prompt_manifest` points
to it so replay, eval authoring, and remote debugging can pin the prompt
composition used by the run.
`tool_calls.jsonl` is derived from `tool_call_finished` and `tool_call_failed`
trace events so tool outputs can be replayed, diffed, or inspected without
scanning the full trace.
`events.jsonl` contains the redacted `trace.events[]` stream as one JSON object
per line for TUI, CLI, and SDK consumers that want streaming/event-oriented
inspection.
The runner now wraps `AgentServices` with trace-aware state accessors. Any agent
using `ctx.services.load_state` or `ctx.services.save_state` emits
`state_read` / `state_write` events with `run_id`, `agent_id`, `key`,
`duration_ms`, `status`, BLAKE3 `value_hash`, and the observed JSON value.
Failure paths emit `state_read_failed` / `state_write_failed` with the
structured `AgentErrorRecord`. These events flow through `trace.json` and the
redacted `events.jsonl` stream, so debug bundles can explain state-dependent
behavior without custom agent instrumentation.
Proposal lifecycle operations also append to the persisted run trace when that
trace exists. `proposal_created`, `proposal_decided`, `proposal_applied`, and
`proposal_undone` events are therefore visible in `trace.json`, the HTTP
`/runs/{run_id}/events` SSE stream, and debug bundle `events.jsonl`.

Bundle JSON files are written through the built-in debug redaction policy before
they hit disk. The current policy replaces sensitive field names such as
`authorization`, `password`, `secret`, `token`, `access_token`,
`refresh_token`, `api_key`, `jwt`, `credential`, and `private_key` with
`[REDACTED]`. `redactions.json` records the policy name, replacement string,
and JSON paths that were redacted. The persisted run store is not mutated.

Inspect a Flutter-exported `agent_catalog.v1`:

```bash
rtk cargo run -p agent-cli -- catalog summary \
  fixtures/agent-runtime/catalog.valid.json
rtk cargo run -p agent-cli -- catalog agents \
  fixtures/agent-runtime/catalog.valid.json
rtk cargo run -p agent-cli -- catalog tools \
  fixtures/agent-runtime/catalog.valid.json
rtk cargo run -p agent-cli -- catalog prompt-manifest \
  fixtures/agent-runtime/catalog.valid.json
```

`catalog prompt-manifest` materializes the prompt/model version contract from
the runtime design. It records `prompt_version`, `agent_version`,
`catalog_version`, `model_family`, `provider`, `model`,
`tool_schema_version`, active domains, prompt block sources, and BLAKE3 content
hashes. The command reads optional agent metadata keys (`prompt_id`,
`prompt_version`, `model_family`, `provider`, `model`,
`tool_schema_version`) and falls back to stable defaults when older Flutter
catalogs do not provide them yet. Multi-agent catalogs require `--agent-id`.
The wire contract is schema-checked at
`schemas/agent-runtime/prompt-manifest.schema.json` and exposed as the OpenAPI
`PromptManifest` component.

Dry-run an agent spec from a Flutter-exported catalog through the Rust runner:

```bash
rtk cargo run -p agent-cli -- run execution_review \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --input fixtures/agent-runtime/run-request.valid.json \
  --trace-out /private/tmp/agent-runtime-catalog-dry-run-trace.json \
  --store /private/tmp/agent-runtime-catalog-dry-run-store
```

Catalog dry-run validates registry loading, run lifecycle, run-store writes, and
trace emission. It intentionally does not execute Flutter/Riverpod business
logic.

`ExecutionPolicy.max_concurrent_runs` is enforced inside `AgentRunner` with a
Tokio semaphore. `ExecutionPolicy.max_retries` and `retry_backoff` now provide
the structured retry policy from the runtime design. Retries are opt-in
(`max_retries = 0` by default) and only fire when the failed result carries a
structured `AgentErrorRecord.retryable = true`, such as timeout or an explicit
retryable tool/provider error. A retry keeps the same `run_id` and
idempotency key, appends `run_attempt_started`, `run_attempt_finished`, and
`run_retry_scheduled` trace events, and writes one final run record.

`AgentRunner` also acquires a lease for `agent:{agent_id}:scope:{scope}` before
writing a running record. The lease window covers timeout plus the configured
retry/backoff budget. A duplicate run for the same agent/scope returns a
skipped outcome while the lease is active. The current default lease store is
in-memory; distributed file/DB/Redis lease stores remain a later backend/worker
hardening step.

Recover stale runs after a crash or worker restart:

```bash
rtk cargo run -p agent-cli -- recover \
  --store /private/tmp/agent-runtime-store \
  --timeout-seconds 60
```

`agent recover` scans the run store and applies the MVP recovery policy from the
design doc: `running` records older than the configured execution window
(timeout plus retry/backoff budget) are marked `abandoned` with a structured
`stale_running_run_abandoned` error. Fresh `running` records and terminal states
are left untouched. The same recovery logic is exposed from `agent-runtime` as
`recover_stale_runs(...)` and `AgentRunner::recover_stale_runs()`.

Every new run record also carries `idempotency_key`, computed as a BLAKE3 hash
over the agent id, run scope, trigger kind, and `metadata.scheduled_for` value.
The key is stable for worker retries of the same scheduled fire and is exposed
through CLI inspect, HTTP `/runs`, debug bundles, and file-store JSON records.

Tool calls made by catalog dry-run agents are traced as
`tool_call_started`, `tool_call_finished`, or `tool_call_failed` events. Each
event pair shares a `tool_call_id`, includes a BLAKE3 `input_hash`, and records
duration plus completion status. The payload shape is captured by
`schemas/agent-runtime/tool-call-record.schema.json`.

Dry-run with an external process tool host:

```bash
rtk cargo run -p agent-cli -- run execution_review \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --input /private/tmp/catalog-tool-call.json \
  --tool-host target/debug/agent dev-tool-host \
  --store /private/tmp/agent-runtime-tool-host-store
```

Where the input can request a tool call:

```json
{
  "tool_call": {
    "name": "example_tool",
    "input": {"value": 7}
  }
}
```

The tool host protocol is JSONL over stdin/stdout. The runtime sends:

```json
{"jsonrpc":"2.0","id":"tool_call","method":"tool.call","params":{"name":"example_tool","input":{"value":7}}}
```

and expects:

```json
{"jsonrpc":"2.0","id":"tool_call","result":{"ok":true}}
```

`agent dev-tool-host` is a hidden self-contained test host used by integration
tests; production hosts should implement the same `tool.call` method.

Dry-run with deterministic mock tool output:

```bash
rtk cargo run -p agent-cli -- run execution_review \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --input /private/tmp/catalog-tool-call.json \
  --mock-tool 'example_tool={"ok":true}' \
  --store /private/tmp/agent-runtime-mock-tool-store
```

For larger outputs, point the mock at a JSON fixture:

```bash
rtk cargo run -p agent-cli -- run execution_review \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --input /private/tmp/catalog-tool-call.json \
  --mock-tool example_tool=@fixtures/agent-runtime/mock-tool-output.json
```

`--mock-tool` is available on `run`, `replay --execute`, `tool call`, `serve`,
and `eval`. Mock outputs take precedence over `--tool-host`, which keeps
fixtures deterministic without changing production tool-host wiring.

List tool specs from a catalog:

```bash
rtk cargo run -p agent-cli -- tool list \
  --catalog fixtures/agent-runtime/catalog.valid.json
```

Call a tool directly through a process tool host:

```bash
rtk cargo run -p agent-cli -- tool call propose_fake \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --input-json '{"value":7}' \
  --tool-host target/debug/agent dev-tool-host
```

`agent tool call` validates the requested tool against the catalog when
`--catalog` is provided. Without `--tool-host`, it can still call the built-in
debug `echo` tool.

Load external tool sources from JSON/YAML manifests:

```json
{
  "version": "tool_source.v1",
  "sources": [
    {
      "id": "local-dev",
      "command": "target/debug/agent",
      "args": ["dev-tool-host"],
      "tools": [
        {
          "name": "sourced_echo",
          "description": "Echo through a configured tool source.",
          "input_schema": {"type": "object"},
          "output_schema": {"type": "object"},
          "risk": "read_only",
          "metadata": {"source": "local-dev"}
        }
      ]
    }
  ]
}
```

The manifest can be used with `run`, `replay --execute`, `tool list`,
`tool call`, `serve`, `eval`, and proposal apply/undo:

```bash
rtk cargo run -p agent-cli -- tool list \
  --tool-source fixtures/agent-runtime/tool-source.example.json

rtk cargo run -p agent-cli -- tool call sourced_echo \
  --tool-source fixtures/agent-runtime/tool-source.example.json \
  --input-json '{"value":7}'
```

Tool-source commands use JSONL `tool.call` by default. Set
`"protocol": "mcp_stdio"` to call an MCP stdio server through `initialize` and
`tools/call`:

```bash
rtk cargo run -p agent-cli -- tool call mcp_echo \
  --tool-source fixtures/agent-runtime/mcp-tool-source.example.json \
  --input-json '{"value":7}'
```

Set `"protocol": "http_json"` to call an HTTP tool endpoint:

```json
{
  "version": "tool_source.v1",
  "sources": [
    {
      "id": "http-dev",
      "protocol": "http_json",
      "endpoint": "http://127.0.0.1:8766/tools/call",
      "headers": {"x-agent-runtime-source": "http-dev"},
      "tools": [
        {
          "name": "http_echo",
          "description": "Echo through an HTTP JSON tool endpoint.",
          "input_schema": {"type": "object"},
          "output_schema": {"type": "object"},
          "risk": "read_only",
          "metadata": {"source": "http-dev", "protocol": "http_json"}
        }
      ]
    }
  ]
}
```

The runtime POSTs `{"protocol_version":"agent.v1","method":"tool.call",
"tool":"http_echo","input":{...}}` to the endpoint and accepts either
`{"output": ...}` or `{"result": ...}` as the tool output envelope. Static
headers are supported for local gateways, IDE integrations, and remote runtime
adapters. `schemas/agent-runtime/tool-source-manifest.schema.json` validates
JSONL, MCP stdio, and HTTP JSON manifests, including the protocol-specific
`command`/`endpoint` requirements.

This keeps Flutter, process tools, MCP servers, and HTTP tool gateways behind
one runtime dispatch path.

Create and inspect a proposal envelope:

```bash
rtk cargo run -p agent-cli -- proposal create \
  --store /private/tmp/agent-runtime-store \
  --run-id run_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --agent-id execution_review \
  --kind fake \
  --summary 'Review fake proposal' \
  --payload-json '{"value":7}'

rtk cargo run -p agent-cli -- proposal list \
  --store /private/tmp/agent-runtime-store \
  --run-id run_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000
```

Record an approval decision:

```bash
rtk cargo run -p agent-cli -- proposal decide \
  proposal_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --store /private/tmp/agent-runtime-store \
  --decision approve \
  --comment 'Looks correct'
```

Apply and undo an approved proposal:

```bash
rtk cargo run -p agent-cli -- proposal apply \
  proposal_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --store /private/tmp/agent-runtime-store \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --mock-tool 'propose_fake={"applied":true}'

rtk cargo run -p agent-cli -- proposal undo \
  proposal_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --store /private/tmp/agent-runtime-store \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --mock-tool 'propose_fake={"undone":true}'
```

`proposal apply` requires status `approved`; `proposal undo` requires status
`applied`. The runtime resolves the proposal kind through the active catalog's
`proposal_kinds` entry and calls that `tool_name` with `{action, proposal}`.
The host tool performs the domain write or rollback. The runtime only owns the
protocol and status transitions: `applying -> applied | apply_failed` and
`undoing -> undone | undo_failed`.

Proposal envelopes and approval decisions are schema-first wire contracts:
`schemas/agent-runtime/proposal-envelope.schema.json` and
`schemas/agent-runtime/approval-decision.schema.json`.
CLI and HTTP proposal create/decision/apply/undo append lifecycle events to the
associated run trace if the trace is present; manually supplied external run ids
still work, but trace append becomes a no-op when the runtime has no matching
trace file.

Run a deterministic mock LLM completion:

```bash
rtk cargo run -p agent-cli -- llm complete \
  --prompt 'Summarize today' \
  --model mock-fast \
  --mock-response 'mock response'
```

Run against an OpenAI-compatible endpoint:

```bash
OPENAI_API_KEY=... rtk cargo run -p agent-cli -- llm complete \
  --provider openai-compatible \
  --api-base-url https://api.openai.com/v1 \
  --prompt 'Summarize today' \
  --model gpt-4.1-mini \
  --temperature 0.2 \
  --max-output-tokens 512
```

`--api-base-url` can also come from `OPENAI_BASE_URL`; the key is read from
`OPENAI_API_KEY` by default, or another environment variable via
`--api-key-env`.

Run against Anthropic Messages API:

```bash
ANTHROPIC_API_KEY=... rtk cargo run -p agent-cli -- llm complete \
  --provider anthropic \
  --prompt 'Summarize today' \
  --model claude-3-5-haiku-latest \
  --max-output-tokens 512
```

Anthropic uses `https://api.anthropic.com/v1` by default. Override with
`--api-base-url` or `ANTHROPIC_BASE_URL`; the API version defaults to
`2023-06-01` and can be changed with `--anthropic-version`.

Run against a local Ollama-compatible endpoint:

```bash
rtk cargo run -p agent-cli -- llm complete \
  --provider ollama \
  --prompt 'Summarize today' \
  --model llama3.2 \
  --max-output-tokens 512
```

Ollama uses `http://127.0.0.1:11434` by default. Override with
`--api-base-url` or `OLLAMA_BASE_URL`.

The LLM layer is provider-neutral. `agent-llm` defines `LlmProvider`,
`LlmRequest`, `LlmResponse`, streaming `LlmEvent`s, structured `LlmError`s, and
a deterministic `MockLlmProvider` for evals and CLI debugging. It also includes
`OpenAiCompatibleProvider`, `AnthropicProvider`, and `OllamaProvider`
implementations backed by `reqwest` with rustls TLS. Wire contracts are under
`schemas/agent-runtime/llm-request.schema.json` and
`schemas/agent-runtime/llm-response.schema.json`.

Flutter production integration is FRB-first. The bridge starts with
`agentRuntimeStartRunStep`: Dart passes the active `agent_catalog.v1`, a
`RunRequest`, and an agent id to the native Rust bridge. Rust validates the
contract and returns a JSON step:

- `completed` for a dry-run request without a tool call
- `tool_call_requested` when the request asks for a catalog tool

Dart remains responsible for executing device tools through
`DeviceToolDispatcher` and will feed tool results back through future FRB
continuation APIs. This keeps Rust responsible for runtime/protocol/trace
contracts while Drift/Riverpod access stays in Flutter.

Flutter also has a library-level JSONL adapter for process-host smoke tests:

```dart
final host = AgentRuntimeToolHost(dispatcher: driftDispatcher);
final responseLine = await host.handleLine(requestLine);
```

The adapter lives at `apps/mobile/lib/app/agent_runtime_tool_host.dart` and maps
JSONL `tool.call` requests onto the existing `DeviceToolDispatcher`. Tool-level
policy/error envelopes returned by device tools are preserved as `result`
payloads; malformed JSON-RPC requests return protocol errors.

There is also a pure Dart safe-mode process entry for protocol smoke tests:

```bash
cd apps/mobile
printf '%s\n' '{"jsonrpc":"2.0","id":"tool_call","method":"tool.call","params":{"name":"anything","input":{}}}' \
  | rtk dart run bin/agent_runtime_tool_host.dart --unavailable
```

`--unavailable` intentionally returns the standard `tool_unavailable` payload
without booting Flutter plugins, Drift, or native FFI. The app-backed provider
entry is `agentRuntimeToolHostProvider`.

The same pure-Dart entry also has a `--shell` mode for DB-free shell tools.
This gives the Rust CLI a real JSONL Dart tool-host path for interaction
tools without compiling Drift/sqlite FFI:

```bash
cd apps/mobile
printf '%s\n' '{"jsonrpc":"2.0","id":"decision","method":"tool.call","params":{"name":"ask_user","input":{"title":"Pick","options":[{"label":"A"},{"label":"B"}]}}}' \
  | rtk dart run bin/agent_runtime_tool_host.dart --shell
```

`--shell` currently executes `ask_user` and returns the same
`decision_request` envelope as the production device tool. Unknown tools still
return `tool_unavailable`, so data-backed tools cannot accidentally run without
the app database.

For library-level headless integration tests, use
`createAgentRuntimeHeadlessToolHost` from
`apps/mobile/lib/app/agent_runtime_headless_tool_host.dart`. It builds a
`ProviderContainer`, mounts the same tool dispatcher protocol, and can register
the production domain tool graph without starting the UI. This path is covered
by `test/app/agent_runtime_headless_tool_host_test.dart`.

The standalone app-backed process wrapper
`bin/agent_runtime_tool_host_headless.dart` is intentionally kept separate from
the safe-mode protocol host. On the current local latest Dart/Flutter toolchain,
running it through `dart run` reaches `sqlite3 3.3.3`'s `NativeCallable`
bindings through Drift native and crashes in the Dart VM compiler before `main`
executes. Until that upstream compatibility issue is resolved, Rust CLI
end-to-end runs should keep using `--tool-host target/debug/agent dev-tool-host`
or mock tool outputs; Flutter-side tool dispatch remains validated through the
library tests.

Start the headless stdio server over the same catalog:

```bash
rtk cargo run -p agent-cli -- serve \
  --stdio \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --store /private/tmp/agent-runtime-stdio-store \
  --tool-host target/debug/agent dev-tool-host
```

The stdio transport accepts one JSON request per line and returns one JSON
response per line:

```json
{"jsonrpc":"2.0","id":"summary","method":"catalog.summary","params":{}}
{"jsonrpc":"2.0","id":"run","method":"agent.run","params":{"agent_id":"execution_review","input":{"message":"hello"}}}
```

Start the headless HTTP server over the same catalog:

```bash
rtk cargo run -p agent-cli -- serve \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --store /private/tmp/agent-runtime-http-store \
  --host 127.0.0.1 \
  --port 8765
```

Current HTTP endpoints:

```text
GET  /healthz
GET  /catalog/summary
GET  /metrics/summary
GET  /tools
POST /tools/{tool_name}/call
GET  /runs
GET  /runs/{run_id}
GET  /runs/{run_id}/trace
GET  /runs/{run_id}/events
POST /runs/{run_id}/replay
GET  /proposals
POST /proposals
GET  /proposals/{proposal_id}
POST /proposals/{proposal_id}/decision
POST /proposals/{proposal_id}/apply
POST /proposals/{proposal_id}/undo
GET  /sessions
POST /sessions
GET  /sessions/{session_id}
POST /sessions/{session_id}/fork
POST /agents/{agent_id}/run
```

`GET /runs/{run_id}/events` returns `text/event-stream` where each SSE data
frame is one persisted `TraceEvent` JSON object from the run trace. This is the
server-side counterpart to debug bundle `events.jsonl`; it gives TUI/Web/IDE
clients a stable event-stream contract today and can be extended to live tailing
when the runner keeps per-run sinks open.

`agent metrics summary --store <path>` and `GET /metrics/summary` build metrics
from the same persisted run records, trace events, and proposal files. The MVP
summary includes run counts by status, completed/skipped/failed/timeout counts,
run latency totals/averages, tool call counts and latency, replay count,
proposal counts by status, proposal approved/denied/applied counts, and
`llm_total_tokens` when LLM trace events expose token usage.
Proposal approved/denied/applied counts are lifecycle operation counts derived
from trace events when available, so a proposal that is applied and later undone
still contributes to `proposal_applied_count` while `proposals_by_status`
reflects the final `undone` state. For older stores without lifecycle trace
events, the summary falls back to current proposal statuses.

Example run request:

```bash
rtk curl -s http://127.0.0.1:8765/agents/execution_review/run \
  -H 'content-type: application/json' \
  -d '{"input":{"message":"hello from HTTP"}}'
```

The HTTP transport uses the same `AgentRunner`, file run store, trace capture,
catalog registry, and process tool-host bridge as the CLI and stdio paths. The
initial OpenAPI 3.1 contract lives at `openapi/agent-runtime-api.yaml`.

Inspect an HTTP-created run and trace:

```bash
rtk curl -s 'http://127.0.0.1:8765/runs?agent_id=execution_review&limit=20'

rtk curl -s http://127.0.0.1:8765/runs/run_01

rtk curl -s http://127.0.0.1:8765/runs/run_01/trace

rtk curl -s http://127.0.0.1:8765/runs/run_01/replay -X POST
```

These endpoints read the same persisted run record and trace file that power
`agent inspect`, `agent replay`, eval generation, command generation, and debug
bundle export. `GET /runs` returns newest runs first and supports optional
`agent_id` and `limit` query parameters for TUI / SDK run inventory screens.
`POST /runs/{run_id}/replay` reconstructs a live replay from the persisted
trace, writes a new run/trace pair into the same store, and returns the same
`ReplayExecutionReport` shape as CLI replay.

HTTP session flow:

```bash
rtk curl -s http://127.0.0.1:8765/sessions \
  -H 'content-type: application/json' \
  -d '{"title":"Execution debug"}'

rtk curl -s http://127.0.0.1:8765/agents/execution_review/run \
  -H 'content-type: application/json' \
  -d '{"session_id":"session_01","thread_id":"thread_01","input":{"message":"hello"}}'

rtk curl -s http://127.0.0.1:8765/sessions/session_01

rtk curl -s http://127.0.0.1:8765/sessions/session_01/fork \
  -H 'content-type: application/json' \
  -d '{"parent_thread_id":"thread_01","title":"Alternative prompt"}'
```

The HTTP path uses the same `FileSessionStore` as `agent session`, so CLI,
TUI, SDK, and server clients can observe the same session/thread/step graph.

Example HTTP tool call:

```bash
rtk curl -s http://127.0.0.1:8765/tools/propose_fake/call \
  -H 'content-type: application/json' \
  -d '{"input":{"value":7}}'
```

Example HTTP proposal approval flow:

```bash
rtk curl -s http://127.0.0.1:8765/proposals \
  -H 'content-type: application/json' \
  -d '{"run_id":"run_01","agent_id":"execution_review","kind":"fake","summary":"Review fake proposal","payload":{"value":7}}'

rtk curl -s 'http://127.0.0.1:8765/proposals?run_id=run_01'

rtk curl -s http://127.0.0.1:8765/proposals/proposal_01/decision \
  -H 'content-type: application/json' \
  -d '{"decision":"approve","comment":"Looks correct"}'

rtk curl -s http://127.0.0.1:8765/proposals/proposal_01/apply -X POST

rtk curl -s http://127.0.0.1:8765/proposals/proposal_01/undo -X POST
```

The HTTP proposal endpoints use the same `FileProposalStore` as
`agent proposal create/list/inspect/decide/apply/undo`, so CLI, TUI, SDK, and
backend clients observe the same approval state.

Run all current checks:

```bash
rtk cargo test --workspace
```

Check the mobile native bridge crate:

```bash
cd apps/mobile/native/lifeos_native
rtk cargo test
```

Check the Dart-side native bridge wiring and generated FRB contract:

```bash
cd apps/mobile
rtk dart analyze lib/app/agent_runtime_native_bridge.dart \
  test/app/agent_runtime_native_bridge_test.dart \
  test/native/frb_garmin_codegen_contract_test.dart
rtk flutter test test/app/agent_runtime_native_bridge_test.dart \
  test/native/frb_garmin_codegen_contract_test.dart
```

Run the sample eval:

```bash
rtk cargo run -p agent-cli -- eval \
  evals/agent-runtime/catalog_dry_run.yaml \
  --store /private/tmp/agent-runtime-eval-store
```

Run every eval case under a directory:

```bash
rtk cargo run -p agent-cli -- eval \
  evals/agent-runtime \
  --store /private/tmp/agent-runtime-eval-suite-store
```

Eval expectations now cover persisted proposals as well as trace/tool output.
Agents create proposals through `AgentServices::create_proposal`; the runner
emits a `proposal_created` trace event and the CLI-backed services persist the
`ProposalEnvelope` in the same `FileProposalStore` used by CLI/HTTP approval
flows. A YAML case can assert proposal count, kinds, and statuses:

```yaml
expect:
  status: completed
  proposals:
    min_count: 1
    kinds: [fake]
    statuses: [pending_approval]
```

The catalog dry-run agent accepts a deterministic proposal fixture input for
regression tests:

```yaml
input:
  proposal:
    kind: fake
    summary: Eval fake proposal
    payload: {value: 19}
```

Eval cases can also bind the prompt/model/tool-schema contract produced by
`agent catalog prompt-manifest`. This makes prompt changes fail deterministic
evals until the expected version/hash is deliberately updated:

```yaml
expect:
  status: completed
  prompt_manifest:
    version: execution_review.prompt.v1
    model: gpt-5-mini
    tool_schema_version: tool_schema.v1
    block_hashes:
      - blake3:d838ad239f1e6a938780f02c79833321e8fbf2d5d13800030ed4edc40e687796
```

Eval cases may include a process scoring hook:

```yaml
scoring_hook:
  command: [agent, dev-score-hook]
  min_score: 0.8
```

The hook receives one JSON object on stdin with the eval id, run result, trace,
status, and checked assertions. It must write JSON like
`{"passed": true, "score": 1.0, "comment": "..."}` to stdout. The built-in
hidden `agent dev-score-hook` is deterministic and intended only for local
tests/examples; production scoring hooks can call an LLM judge, rubric script,
or regression scorer.

Scoring hook invocations are reported through the shared HookEvent contract.
`schemas/agent-runtime/hook-event.schema.json` reserves the MVP hook event names
from the runtime design (`SessionStart`, `RunStart`, `BeforeToolCall`,
`AfterAgentStep`, and the rest of the extension points), hook kinds
(`native_rust`, `process`, `server`), status, timestamps, duration, input, and
output/error fields. Eval scoring hooks currently emit `AfterAgentStep`
`process` records in the eval report `hooks` array, so CLI/TUI/server clients
can consume one protocol before a full plugin system exists. The same schema is
also exposed as the OpenAPI `HookEvent` component.

Committed eval YAML files are schema-checked with
`schemas/agent-runtime/eval-case.schema.json`, covering fixture input, expected
status, expected trace events, expected tool call sequence, expected proposals,
prompt manifest fields, golden trace, and scoring hook configuration.

Refresh golden traces for one file or an entire directory:

```bash
rtk cargo run -p agent-cli -- eval \
  evals/agent-runtime \
  --store /private/tmp/agent-runtime-eval-suite-store \
  --update-golden
```

Generate a regression eval from a persisted run:

```bash
rtk cargo run -p agent-cli -- eval create \
  --from-run run_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --store /private/tmp/agent-runtime-catalog-dry-run-store \
  --catalog fixtures/agent-runtime/catalog.valid.json \
  --out /private/tmp/agent-runtime-evals/generated.yaml \
  --id generated_from_run
```

The generated YAML preserves the stored run input, expected status, agent id,
output mode, trace event sequence, tool call sequence, prompt manifest
expectation, and any proposals persisted for the source run. It also writes a
normalized golden trace beside the eval under `golden/<id>.trace.json`, so the
file can be run directly with `agent eval`.

Generate a reusable markdown workflow command from a persisted run:

```bash
rtk cargo run -p agent-cli -- cmd create \
  --from-run run_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000 \
  --store /private/tmp/agent-runtime-catalog-dry-run-store \
  --out .agent-runtime/commands/execution-review.md \
  --registry examples/agent-runtime/agents.yaml \
  --description 'Replay execution review fixture'
```

The command file uses YAML frontmatter plus a captured JSON input fence:

````markdown
---
description: Replay execution review fixture
agent: execution_review
registry: examples/agent-runtime/agents.yaml
source_run_id: run_01975d8c-72f5-7f1e-9b7e-c7ef3e0a1000
source_run_status: completed
created_at: 2026-06-28T10:55:00Z
---

Run the configured agent with this captured input. Replace or extend
`$ARGUMENTS` when invoking the command to add run-specific instructions.

```json
{"message": "hello"}
```
````

Run the command template:

```bash
rtk cargo run -p agent-cli -- cmd run \
  .agent-runtime/commands/execution-review.md \
  --store /private/tmp/agent-runtime-command-store
```

`cmd run` reads the same registry/catalog contracts as `agent run`, writes the
new run and trace into the file store, and reports the result plus trace. This
completes the first trace/run -> eval -> command asset loop from the design
document.

Create and inspect a debugging session:

```bash
rtk cargo run -p agent-cli -- session create \
  --title 'Execution debug' \
  --store /private/tmp/agent-runtime-session-store

rtk cargo run -p agent-cli -- session list \
  --store /private/tmp/agent-runtime-session-store

rtk cargo run -p agent-cli -- session show session_01975d8c-72f5-7f1e-b111-000000000001 \
  --store /private/tmp/agent-runtime-session-store
```

`session create` also creates a root thread. A run can be attached to that
thread:

```bash
rtk cargo run -p agent-cli -- run echo_agent \
  --registry examples/agent-runtime/agents.yaml \
  --input examples/agent-runtime/fixtures/echo-input.json \
  --store /private/tmp/agent-runtime-session-store \
  --session session_01975d8c-72f5-7f1e-b111-000000000001 \
  --thread thread_01975d8c-72f5-7f1e-b111-000000000002
```

The run record stores `metadata.session_id` and `metadata.thread_id`; the
session store also writes a `StepRecord` with `kind: agent_run`. Fork a thread
to compare another prompt, model, tool output, or agent version:

```bash
rtk cargo run -p agent-cli -- session fork \
  session_01975d8c-72f5-7f1e-b111-000000000001 \
  thread_01975d8c-72f5-7f1e-b111-000000000002 \
  --title 'Alternative prompt' \
  --store /private/tmp/agent-runtime-session-store
```

The schema contracts live at:

```text
schemas/agent-runtime/session-record.schema.json
schemas/agent-runtime/thread-record.schema.json
schemas/agent-runtime/step-record.schema.json
```

Use a profile config for repeatable local, CI, and server runs:

```toml
[runtime]
profile = "local-dev"
registry = "examples/agent-runtime/agents.yaml"
catalog = "fixtures/agent-runtime/catalog.valid.json"
store = ".agent-runtime/store"
timeout_seconds = 60
max_retries = 1
retry_backoff_ms = 250

[profiles.ci]
store = "/private/tmp/agent-runtime-ci-store"
timeout_seconds = 10
max_retries = 0

[profiles.server]
catalog = "fixtures/agent-runtime/catalog.valid.json"
store = ".agent-runtime/server-store"
host = "127.0.0.1"
port = 8765
```

The CLI loads `agent-runtime.toml` automatically when it exists. Override the
location or profile explicitly:

```bash
rtk cargo run -p agent-cli -- \
  --config agent-runtime.toml \
  --profile ci \
  config show

rtk cargo run -p agent-cli -- \
  --config agent-runtime.toml \
  --profile ci \
  run echo_agent \
  --input examples/agent-runtime/fixtures/echo-input.json

rtk cargo run -p agent-cli -- \
  --config agent-runtime.toml \
  --profile server \
  serve
```

Command-line values win over profile values. Profiles currently cover common
runtime defaults: `registry`, `catalog`, `store`, `eval_store`,
`tool_sources`, `host`, `port`, `stdio`, `timeout_seconds`, `max_retries`, and
`retry_backoff_ms`. `agent run`, `agent replay --mode live`, and `agent cmd run`
also expose `--max-retries` and `--retry-backoff-ms` flags for one-off
debugging runs.

## Dependency Approach

The MVP targets Rust 1.96 (`rustc 1.96.0`, `cargo 1.96.0`) and Rust 2024
edition for newly introduced Rust workspace crates. The root runtime workspace
and the mobile native bridge use current mainstream Rust ecosystem crates:

- async runtime: `tokio`
- CLI: `clap`
- diagnostics: `miette`
- serialization/contracts: `serde`, `serde_json`, `serde_yaml`, `schemars`, `jsonschema`
- errors: `thiserror`
- stream abstraction: `futures`
- HTTP client: `reqwest` with rustls TLS
- time: `time`
- IDs: `uuid` v7
- filesystem paths and IO: `camino`, `fs-err`
- config/profile parsing: `toml`
- tracing: `tracing`, `tracing-subscriber`
- Flutter bridge: `flutter_rust_bridge`
- native embeddings: `fastembed`

Mobile Dart dependencies are kept at the newest versions the current Flutter
SDK and package graph can resolve. The June 2026 upgrade moved the app to
Forui `0.23`, `flutter_local_notifications` `22`, `local_auth` `3`,
`sentry_flutter` `9`, and enabled project-level Swift Package Manager because
`receive_sharing_intent` `1.9` is SPM-only. `intl` remains on `0.20.2`
because `flutter_localizations` pins it from the Flutter SDK, and
`drift_dev` remains on `2.34.0` because `2.34.1+1` requires analyzer `^13`
while the current `freezed` line resolves analyzer below that range.
Direct Dart constraints have been tightened to the newest resolvable versions
with `dart pub upgrade --tighten`; future dependency additions should follow
the same policy: use the latest stable release first, then document any SDK or
upstream package constraint that prevents moving to the published latest.

## Next Migration Step

The next useful increment is a Dart catalog export from the existing
`DomainPack` composition root. The first version now exists at
`apps/mobile/lib/app/agent_runtime_catalog.dart` and exports:

- active `Agent` values -> `AgentSpec`
- active `DeviceTool` values -> `ToolSpec`
- proposal kind registry -> `ProposalEnvelope.kind` inventory
- prompt blocks and agent metadata -> `PromptManifest`

`agent-cli` can now read `agent_catalog.v1` directly through the `catalog`
subcommands and can run catalog-backed dry-runs via `agent run --catalog`.
It also exposes `agent serve --stdio` and `agent serve --host/--port` as
headless JSONL / HTTP transports for future TUI, IDE, SDK, backend, and worker
clients. Both command and server paths can call a process tool host through
`--tool-host`. Flutter now has a library-level adapter for the same `tool.call`
protocol, and the native crate exposes a primitive/String FRB surface for
validating and summarizing agent runtime wire contracts. FRB codegen now
exports that surface to Dart, and `agentRuntimeNativeBridgeProvider` wires it
to the app composition root. CLI and HTTP sessions now provide the first
Session/Thread/Run/Step data model from the design doc, with shared file-backed
state that TUI/server clients can inspect. The next increment is either
resolving the `sqlite3`/Dart VM standalone-process blocker for data-backed
Flutter tools or migrating the first production agent into the embedded Rust
runner through the already-validated FRB/native bridge.

The eval loop is intentionally small: a YAML case points at an
`agent_catalog.v1`, runs one agent through the same runner path, and asserts
status, agent id, output mode, trace events, tool call order, proposals, prompt
manifest fields, and normalized golden traces. Directory mode recursively
discovers `.yaml` / `.yml` cases and returns a suite report. `agent eval create
--from-run` converts a successful debug run into the same YAML/golden format,
including prompt manifest and persisted proposal expectations, and `agent cmd
create --from-run` converts the same run record into a reusable markdown
workflow command.
