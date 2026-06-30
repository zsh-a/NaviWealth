# Agent Runtime Current Architecture

This is the current implementation map for agents working on the Rust agent
runtime. Use this document for code navigation and maintenance decisions.
`rust-agent-runtime-design.md` is the long-term design direction; this document
describes what exists now.

## Scope

The runtime is currently part of the NaviWealth monorepo, not a standalone
repository. It provides:

- reusable Rust contracts and runner crates
- schema / fixture / OpenAPI wire contracts
- local CLI, HTTP, stdio, eval, replay, debug bundle, and TUI surfaces
- Flutter FRB JSON entrypoints for native mobile integration
- Dart app-level adapters that keep business data and device tools in Flutter

The runtime must remain independent of Flutter, Riverpod, Drift, and
NaviWealth domain models. Business policy and repositories stay in the host
application unless a migration explicitly moves them into a Rust agent.

## Code Map

```text
crates/
  agent-core/       Stable DTOs, traits, IDs, errors, trace/session/proposal contracts
  agent-runtime/    AgentRunner, scheduler, retry/timeout, lease locking, trace capture
  agent-store/      In-memory and file-backed run/state/proposal/session stores
  agent-llm/        Provider-neutral LLM DTOs, mock/OpenAI/Anthropic/Ollama providers
  agent-chat/       Shared ChatTurn request/event contract and provider/tool loop
  agent-cli/        Local developer surfaces and host adapters

crates/agent-runtime/src/
  lib.rs            Public exports only
  runner.rs         AgentRunner lifecycle, retry/timeout, idempotency keys
  policy.rs         ExecutionPolicy
  lock.rs           AgentLockStore helpers and in-memory lease store
  recovery.rs       Stale run recovery
  scheduler.rs      Manual/interval schedule decisions
  services.rs       Basic and traced AgentServices wrappers
  trace.rs          In-memory trace sink
  registry.rs       In-memory AgentRegistry
  tests.rs          Runner lifecycle tests

crates/agent-store/src/
  lib.rs            Public exports only
  memory.rs         In-memory run/state/proposal/session stores
  file.rs           File-backed run/proposal/session stores
  util.rs           Shared scope and run sorting helpers
  tests.rs          Store backend tests

crates/agent-llm/src/
  lib.rs            Public exports only
  types.rs          Provider-neutral LLM DTOs, stream events, errors, provider trait
  mock.rs           Mock provider for local tests and deterministic runners
  usage.rs          Rough token usage estimator for mock/local responses
  sse.rs            Shared server-sent event frame parsing helpers
  providers/
    mod.rs          Provider exports and shared mapping helpers
    openai.rs       OpenAI-compatible chat/completions request, response, stream mapping
    anthropic.rs    Anthropic messages request, response, stream mapping
    ollama.rs       Ollama chat request, response, synthetic stream mapping
  tests.rs          Provider request mapping and SSE stream tests

crates/agent-chat/src/
  lib.rs            ChatTurnRequest, ChatTurnEvent, ChatTurnRunner, tool-round loop

crates/agent-cli/src/
  main.rs           clap wiring and top-level command dispatch only
  chat.rs           CLI/TUI LLM provider construction for ChatTurnRunner
  commands/         Thin command handlers for run/catalog/tool/proposal/session/llm/cmd
  catalog.rs        Catalog loading, prompt manifest, catalog dry-run registry
  registry.rs       YAML registry and local example agent implementations
  tools.rs          CLI AgentServices, mock tools, process/MCP/HTTP tool sources
  runtime_server.rs HTTP/stdio runtime orchestration over AgentRunner
  server.rs         HTTP and stdio server transport handlers
  replay.rs         Trace replay modes and output comparison
  eval.rs           Eval case execution, golden trace checks, scoring hooks
  proposal.rs       Proposal lifecycle helpers and trace appenders
  session.rs        Session/thread/step reports and recording helpers
  debug_bundle.rs   Local reproduction bundle export and redaction helpers
  tui.rs, tui/      Interactive TUI shell, state, command handling, rendering

schemas/agent-runtime/
  JSON Schema contracts for runtime wire types, including ChatTurn request,
  state, event, and tool-result resume payloads.

fixtures/agent-runtime/
  Valid and invalid schema fixtures used by contract tests and CLI examples.
  ChatTurn fixtures are also consumed by `agent-chat` runtime tests so schema
  drift breaks locally.

openapi/agent-runtime-api.yaml
  Minimal HTTP API contract for server-first clients.
```

Flutter integration lives under:

```text
apps/mobile/native/lifeos_native/src/api/agent_runtime.rs
  FRB-visible primitive JSON functions. Keep generated Dart bindings out of
  app code by routing through app-level bridges.

apps/mobile/lib/app/
  agent_runtime_catalog.dart          DomainPack -> runtime catalog export
  agent_runtime_native_bridge.dart    Stable Dart map API over generated FRB
  agent_runtime_tool_host.dart        Device tool JSON-RPC host adapter
  agent_runtime_runner.dart           Profile turn + native step loop composition
  agent_runtime_llm_bridge.dart       LlmProfile -> provider-neutral request
  agent_runtime_llm_stream_bridge.dart ChatTurn streaming bridge over FRB JSON
  frb_chat_runner.dart                ChatTurn event mapping and Flutter tool loop
  agent_runtime_trace_recorder.dart   FRB result -> local AiTraceStore adapter
```

## Runtime Layers

1. `agent-core` defines protocol shapes and host-facing traits.
2. `agent-llm` owns provider-neutral request/response/event DTOs and provider
   clients.
3. `agent-chat` owns provider-neutral interactive ChatTurn request/event
   contracts and the LLM/tool continuation loop over `AgentServices`.
4. `agent-runtime` executes scheduled or explicit `Agent` instances through
   `AgentRunner`.
5. `agent-store` persists run/state/proposal/session records.
6. Host adapters implement `AgentServices` and tool/proposal/state behavior.
7. CLI/server/TUI/FRB are surfaces over these contracts.

`AgentRunner` returns `RunOutcome`, not only `AgentRunResult`, because callers
need both the final result and the captured `AgentTrace`.

## Interaction Entrypoints

Use these entrypoints when debugging:

```bash
rtk cargo run -p agent-cli -- list
rtk cargo run -p agent-cli -- run echo_agent --input examples/agent-runtime/fixtures/echo-input.json
rtk cargo run -p agent-cli -- tui
rtk cargo run -p agent-cli -- serve --catalog fixtures/agent-runtime/catalog.valid.json
rtk cargo run -p agent-cli -- validate schemas/agent-runtime/run-request.schema.json fixtures/agent-runtime/run-request.valid.json
```

TUI uses persistent natural input by default. Plain text runs the shared
`agent-chat` ChatTurn path; slash commands perform explicit runtime debugging:

```text
/run <agent_id> [json|text]
/tool <name> [json]
/replay <trace_path>
/inspect <run_id>
/refresh
/clear
/help
```

## Change Routing

| Change | Start Here | Required Checks |
|---|---|---|
| Add or change a wire field | `schemas/agent-runtime/`, `crates/agent-core/`, fixtures | schema validation tests, `rtk cargo test -p agent-cli` |
| Change runner lifecycle | `crates/agent-runtime/src/lib.rs` | `rtk cargo test -p agent-runtime`, `rtk cargo test -p agent-cli` |
| Change LLM provider behavior | `crates/agent-llm/src/providers/` | `rtk cargo test -p agent-llm`, native tests when FRB LLM bridge behavior changes |
| Change ChatTurn behavior | `crates/agent-chat/`, `schemas/agent-runtime/chat-turn-*.schema.json`, ChatTurn fixtures, `agent_runtime_llm_stream_bridge.dart`, `frb_chat_runner.dart` | `rtk cargo test -p agent-chat`, `rtk cargo test -p agent-cli --test contracts`, native tests, Flutter chat bridge tests |
| Change CLI command behavior | `crates/agent-cli/src/commands/` plus supporting module | focused command test, `rtk cargo test -p agent-cli` |
| Change tool host behavior | `crates/agent-cli/src/tools.rs`, `apps/mobile/lib/app/agent_runtime_tool_host.dart` | CLI tool tests, Flutter bridge tests when Dart changes |
| Change FRB API | `apps/mobile/native/lifeos_native/src/api/agent_runtime.rs` | FRB codegen, native API tests, Dart bridge tests |
| Change AI Chat streaming | `agent_runtime_llm_stream_bridge.dart`, `frb_chat_runner.dart` | `frb_chat_runner_test.dart`, stream bridge test |
| Change proposal apply behavior | `crates/agent-cli/src/proposal.rs`, `agent_runtime_proposal_bridge.dart` | proposal CLI tests, targeted Flutter proposal tests |

## Invariants

- All top-level runtime wire messages carry `protocol_version: "agent.v1"`.
- Cross-language contracts are JSON-first. Keep envelopes stable and put
  business-specific data in `input`, `output`, `payload`, or `metadata`.
- Runtime crates must not import Flutter, Dart, Drift, Riverpod, or domain
  feature code.
- Flutter feature code should not import app-level FRB bridges directly; route
  feature-owned seams through app composition.
- Generated FRB files are regenerated, not hand-edited.
- TUI natural input must execute through `ChatTurnRunner`. Runtime debugging
  slash commands may execute through `AgentRunner`, but must still use shared
  JSON contracts rather than ad-hoc behavior.

## Current Design Drift

These are intentional or pending differences from the long-term design:

- No standalone `agent-tools` crate exists yet. Tool traits live in
  `agent-core`; CLI and Flutter host adapters own concrete tool hosts.
- The runtime is still in this monorepo. There is no standalone `bindings/dart`
  or `bindings/ts` SDK package.
- Trace is event-first (`events`) and does not currently expose a separate
  `spans` array.
- `ProposalEnvelope` does not carry a `risk` field; risk is currently expressed
  through tool/proposal metadata and host-side confirmation.
- `ScheduleSpec` supports `manual` and `interval`; cron/plugin/HTTP registries
  remain future work.
- External cancel/pause/resume is not fully implemented. Flutter ChatTurn uses
  a Rust-owned pause/resume state (`chat_state` + `tool_results`) for device
  tool continuation; TUI natural input uses the shared `agent-chat` stream, but
  terminal redraw/cancel is still not a non-blocking live run loop.
- Flutter production agents still keep most business policy in Dart. Rust owns
  contracts, LLM provider paths, native-planned tool continuation, and trace
  normalization for migrated seams.
- Flutter interactive AI Chat uses the same ChatTurn request and event naming
  through the FRB stream bridge. Rust owns ChatTurn state, conversation
  continuation, and tool-round budget through the `chat_state` resume seam;
  `FrbChatRunner` only maps events and dispatches production Dart tools from
  DomainPack/Riverpod host code.

When code and older handoff notes disagree, use this document, the MVP status
doc, and current tests as authority.
