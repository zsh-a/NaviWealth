# Agent Runtime Current Architecture

Status: active native-runtime implementation reference.

## Document Contract

Owns the current Rust Agent Runtime layout, Dart bridge boundaries, context
pipeline, and durable-resume implementation. It does not own domain Agent
behavior or user-facing presentation. The `third_party/agent-runtime` crates,
FRB bridge code, and contract tests are authoritative for exact APIs.

This is the current implementation map for agents working on the Rust agent
runtime. Use this document for code navigation and maintenance decisions.
It is the single source of truth for the runtime that exists now.

NaviWealth consumes the standalone runtime through the
`third_party/agent-runtime` Git submodule, pinned to
`https://github.com/zsh-a/agent-runtime.git`. Unless a path explicitly starts
with `apps/mobile/`, paths below are relative to that submodule.

## Scope

The runtime source of truth is now the standalone `agent-runtime` repository,
vendored into NaviWealth as `third_party/agent-runtime`. It provides:

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
  agent-tools/      Reusable tool registry, policy, and tool-host helpers
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
  types.rs          ChatTurn request and resume contracts
  state.rs          Persistable ChatTurnState
  context.rs        ContextBlock validation, budgeting, rendering, snapshots
  runner.rs         Provider/tool continuation loop
  snapshot.rs       Chat snapshot helpers
  events.rs         ChatTurn event contract
  lib.rs            Public exports

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

schemas/
  JSON Schema contracts for runtime wire types, including ChatTurn request,
  state, event, tool-result resume payloads, typed embedded steps, and
  versioned embedded-run snapshots.

fixtures/contracts/
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

apps/mobile/lib/app/agent_runtime/
  catalog/agent_runtime_catalog.dart           DomainPack -> runtime catalog export
  bridges/agent_runtime_native_bridge.dart     Stable Dart map API over generated FRB
  persistence/agent_runtime_checkpoint_store.dart
                                                Drift snapshot/effect journal
  tools/agent_runtime_tool_host.dart           Device tool JSON-RPC host adapter
  runner/agent_runtime_runner.dart             Profile turn + Rust-owned snapshot composition
  bridges/agent_runtime_llm_bridge.dart        LlmProfile -> provider-neutral request
  bridges/agent_runtime_llm_stream_bridge.dart ChatTurn streaming bridge over FRB JSON
  chat/frb_chat_runner.dart                    ChatTurn event mapping and Flutter tool loop
  context/app_chat_context_assembler.dart      Active-domain Memory -> ContextBlock
  trace/agent_runtime_trace_recorder.dart      FRB result -> local AiTraceStore adapter
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

## Context Pipeline

`agent-core::ContextBlock` is the provider-neutral context unit. A ChatTurn may
carry runtime, agent, or command instructions plus untrusted profile, memory,
compaction summary, resource, and metadata blocks. Data blocks may carry
`ContextEvidence` with authority, provenance, validity, and supersede lineage.
The runtime:

1. validates block ids and rejects duplicate host ids;
2. recomputes token estimates and BLAKE3 content hashes instead of trusting
   host-supplied values;
3. validates evidence intervals and filters expired, not-yet-valid, and
   superseded data blocks;
4. separates instruction authority from evidence authority — including
   `user_confirmed` evidence;
5. selects blocks by priority within `ContextPolicy`, always preserving
   instruction blocks and configured recent messages;
6. records selected and omitted blocks with omission reasons in
   `ContextSnapshot`; and
7. persists the snapshot in `ChatTurnState` so resume uses the same execution
   context.

Host context is rendered for the current turn but is not appended to the
persistent transcript. This prevents retrieved memory and portfolio/resource
snapshots from compounding across turns.

Flutter owns retrieval policy. `ChatRepository` invokes the app-level
`app_chat_context_assembler.dart`, which uses one `MemoryAccessPolicy` derived
from active `DomainPack.memorySourcePrefixes`. The same policy protects
automatic context, explicit recall tools, proposal target lookup, and apply.
Host-owned current Profile facts become untrusted `profile` blocks; retrieved
memories and recent events become untrusted `memory` blocks. Drift, embeddings,
Personal Profile, user/domain permissions, and repositories remain outside Rust.

When the Flutter chat window omits older persisted turns, it also creates a
local `conversation_checkpoints` row. The checkpoint stores a source
fingerprint, summary-through message id/time, and structured payload containing
topic, quoted tool evidence, decisions, rejected options, open loops, entities,
time anchors, and a bounded turn digest. It is injected as an untrusted
`compaction_summary` ContextBlock and never appended to the transcript.
Mutating or deleting any summarized source turn invalidates the row. The
current summarizer is deterministic and non-generative; the
`ConversationCheckpointSummarizer` host seam permits a device-LLM summarizer
later without moving provenance or persistence authority into the model.

## Approved Long-Term Memory

Models cannot write durable user memory or Profile directly. The shell tool
`propose_memory` stages a local-only `memory_candidates` row with a generic
`memory | profile_fact` target and returns a `LocalProposal`. Only an explicit
user approval may materialize the candidate in `memories` or
`personal_profile_facts`.

The candidate lifecycle supports `create`, `supersede`, and `forget`, plus
reject and undo. Candidate ownership, active-domain policy, target ownership,
operation, and model-proposed identifiers are revalidated at apply time; a
candidate cannot be confirmed twice or mutate another user's record. Confirmed
AI records use `authority=user_confirmed` and fixed provenance
`user_confirmed_ai`; Memory confidence is `0.95`. Cancelled proposals reject
their candidate, failed applications remain retryable, and terminal candidates
are pruned after 90 days per owner.

This flow is separate from conversation checkpoints. Checkpoints preserve
bounded conversational continuity; approved Memory represents a durable user
fact or preference. Neither table syncs today.

## Human Interaction and Durable Resume

`agent-core::InteractionEnvelope` and `InteractionResponse` are the shared
human-in-the-loop contract for chat questions and proposal approval:

- kinds: `input`, `choice`, and `approval`;
- confirmation modes: `one_tap`, `confirm_diff`, and `typed`;
- lifecycle: `pending`, `resolved`, `rejected`, `cancelled`, or `expired`;
- routing: stable interaction id, optional subject, response schema, expiry,
  and a typed resume target; and
- responses: `submit`, `approve`, `reject`, or `cancel`, with typed
  confirmation text validated by the runtime.

A `ChatTurnState` may have pending tool calls or one pending interaction, never
both. `chat_turn_suspend_for_interaction` clears no tool state and fails if
tools remain pending. `chat_turn_resume_state` accepts exactly one continuation
input: tool results or an interaction response. Resolving an interaction adds
a provider-neutral `interaction_result` user block before the next model
round.

`ask_user` first executes as a normal client tool. Its result carries the
standard envelope, after which the host reapplies that tool result together
with `suspend_interaction`. Rust returns `requires_interaction` without making
another LLM request. Flutter persists that state in local-only
`agent_runtime_chat_snapshots`; the row contains no tool dispatch journal.
When the user responds, `ChatRepository` routes the response back to the
original turn id, and Rust resumes the same ChatTurn. Missing or expired
snapshots fail closed rather than silently starting a different execution.

Proposal `readyPlan()` results expose the same approval envelope. Proposal
approve/reject/cancel actions and `ask_user` selections persist the same
`InteractionResponse` shape while retaining legacy `DecisionSelection` and
`applyState` fields for compatibility.

## Interaction Entrypoints

Use these entrypoints when debugging:

```bash
cd third_party/agent-runtime
rtk cargo run -p agent-cli -- list
rtk cargo run -p agent-cli -- run echo_agent --input examples/fixtures/echo-input.json
rtk cargo run -p agent-cli -- tui
rtk cargo run -p agent-cli -- serve --catalog fixtures/contracts/catalog.valid.json
rtk cargo run -p agent-cli -- validate schemas/run-request.schema.json fixtures/contracts/run-request.valid.json
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
| Add or change a wire field | `schemas/`, `crates/agent-core/`, fixtures | schema validation tests, `rtk cargo test -p agent-cli` |
| Change runner lifecycle | `crates/agent-runtime/src/lib.rs` | `rtk cargo test -p agent-runtime`, `rtk cargo test -p agent-cli` |
| Change LLM provider behavior | `crates/agent-llm/src/providers/` | `rtk cargo test -p agent-llm`, native tests when FRB LLM bridge behavior changes |
| Change ChatTurn behavior | `crates/agent-chat/`, `schemas/chat-turn-*.schema.json`, ChatTurn fixtures, `apps/mobile/lib/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart`, `apps/mobile/lib/app/agent_runtime/chat/frb_chat_runner.dart` | `rtk cargo test -p agent-chat`, `rtk cargo test -p agent-cli --test contracts`, native tests, Flutter chat bridge tests |
| Change CLI command behavior | `crates/agent-cli/src/commands/` plus supporting module | focused command test, `rtk cargo test -p agent-cli` |
| Change tool host behavior | `crates/agent-cli/src/tools.rs`, `apps/mobile/lib/app/agent_runtime/tools/agent_runtime_tool_host.dart` | CLI tool tests, Flutter bridge tests when Dart changes |
| Change FRB API | `apps/mobile/native/lifeos_native/src/api/agent_runtime.rs` | FRB codegen, native API tests, Dart bridge tests |
| Change AI Chat streaming | `apps/mobile/lib/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart`, `apps/mobile/lib/app/agent_runtime/chat/frb_chat_runner.dart` | `frb_chat_runner_test.dart`, stream bridge test |
| Change proposal apply behavior | `crates/agent-cli/src/proposal.rs`, `apps/mobile/lib/app/agent_runtime/proposals/agent_runtime_proposal_bridge.dart` | proposal CLI tests, targeted Flutter proposal tests |

## Invariants

- All top-level runtime wire messages carry `protocol_version: "agent.v1"`.
- Persistable embedded checkpoints carry `snapshot_version: 1`; hosts must
  round-trip the whole snapshot rather than reconstructing continuation state.
- Pending tool calls and pending interactions are mutually exclusive in
  ChatTurn state and snapshots. Hosts must resume with exactly one of
  `tool_results` or `interaction_response`.
- A `requires_interaction` snapshot contains one pending `chat_turn`
  interaction, no pending tools, and no tool dispatch journal.
- Flutter persists embedded snapshots in the local-only
  `agent_runtime_checkpoints` table. Each host effect moves through
  `awaiting_effect -> dispatching -> effect_recorded` before the next Rust
  snapshot replaces the row; revisions use optimistic concurrency control.
- A recovered `effect_recorded` row reuses its stored response and never
  redispatches the host effect. A recovered `dispatching` row fails closed
  because the host cannot prove whether the effect completed before shutdown.
- Profile turns persist the completed LLM response in checkpoint resume
  context, so recovery does not repeat the provider request. Checkpoint rows
  are local-only, carry an expiry, and terminal rows can be pruned by the host.
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

## Current Limitations

These are the current implementation limits:

- There is no standalone `bindings/dart` or `bindings/ts` SDK package yet.
- Trace is event-first (`events`) and does not currently expose a separate
  `spans` array.
- `ProposalEnvelope` does not carry a `risk` field; risk is currently expressed
  through tool/proposal metadata and host-side confirmation.
- `ScheduleSpec` supports `manual` and `interval`; cron/plugin/HTTP registries
  remain future work.
- Snapshot cancellation is exposed through FRB and persists a Rust-produced
  terminal `cancelled` snapshot without consuming effect budget. General
  arbitrary host pause and non-blocking live-run control are not fully
  implemented. Human interaction pause/resume is implemented through
  `InteractionEnvelope`; Flutter ChatTurn uses
  a Rust-owned pause/resume state (`chat_state` + `tool_results`) for device
  tool continuation; TUI natural input uses the shared `agent-chat` stream, but
  terminal redraw/cancel is still not a non-blocking live run loop.
- Flutter production agents still keep business policy, device tools,
  proposals, and Drift persistence in Dart. Rust owns contracts, LLM provider
  paths, embedded continuation snapshots, effect budgets, subagent-depth
  limits, and trace normalization for migrated seams. Dart dispatches requested
  host effects and returns their JSON-RPC responses without rebuilding runtime
  state.
- Flutter interactive AI Chat uses the same ChatTurn request and event naming
  through the FRB stream bridge. Rust owns ChatTurn state, conversation
  continuation, and tool-round budget through the `chat_state` resume seam;
  `FrbChatRunner` only maps events and dispatches production Dart tools from
  DomainPack/Riverpod host code.
- Flutter long-chat compaction now persists a structured deterministic
  conversation checkpoint and Rust still provides its own final
  priority-context/recent-message fallback. A richer device-LLM checkpoint
  summarizer is not yet implemented.

Use this document and current tests as authority.
