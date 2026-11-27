# Agent Runtime Current Architecture

Status: active native-runtime implementation reference.

## Document Contract

Owns the runtime boundaries used by NaviWealth: the pi-rust general assistant
in `crates/navi-assistant` and recognition through the
`third_party/agent-runtime` submodule. Their source and contract tests are
authoritative for exact APIs.

## General Assistant (2026-11-27)

The owner authorized ongoing conversation, cross-task memory, web research and
multi-step tasks. The embedded assistant uses `rpi-agent` and `rpi-ai` from
[pi-rust v0.29.0](https://github.com/bigfish1913/pi-rust/tree/v0.29.0), pinned to
`6d697126b4149fd1fd69d4c741c6103b37ddc615`. The app does not embed the CLI, TUI,
dynamic extension loader, shell tools or a remote WebView/server architecture.
`rpi-harness` is deliberately not required: host SQLite stores the conversations
without pulling the harness's desktop-tool dependencies or its optional
`rusqlite 0.31` backend into the app's `rusqlite 0.43` graph.

| Layer | Authority |
|---|---|
| Provider adaptation and Agent loop | `crates/navi-assistant/` over pinned `rpi-agent` / `rpi-ai` |
| Source-bound conversation summaries and provider context projection | `crates/navi-assistant/src/compaction.rs` |
| Reactive state, consent, cancellation and proposals | `apps/nsh-client/src/data/assistant.rs` |
| Read-only records, memory retrieval and proposals | `apps/nsh-client/src/data/assistant_tools.rs` |
| Complete-period financial and health summaries | `apps/nsh-client/src/data/assistant_analysis.rs`, domain Review and attribution functions |
| Structured proposal validation and capture handoff | `apps/nsh-client/src/domain/assistant_proposal.rs` |
| Optional Brave Search and bounded public-page fetch | `apps/nsh-client/src/data/assistant_web.rs` |
| Sessions, messages, native replay history and approved memories | `apps/nsh-client/src/data/assistant_store.rs`, migrations 22–24 |
| Conversation, history and memory UI | `apps/nsh-client/src/pages/assistant.rs` |

The model profile selects Anthropic Messages, OpenAI Chat Completions or OpenAI
Responses. Separate destination-scoped consent covers conversation, recalled
memories and requested records. The runtime preserves native message/tool-call
identity for subsequent turns; the host binds saved history to the model
destination. Context selection bounds serialized model input to 120,000 UTF-8
bytes while keeping the complete native conversation. On an explicit new turn,
an over-limit context may summarize earlier complete turns using the same
configured model, retaining the two most recent prior user turns when possible.
At most two summary calls take input chunks of at most 64,000 serialized bytes
(or the lower configured context limit). Summaries contain at most 12,000 UTF-8
bytes and are quoted as untrusted user-context data, never system instructions
or approval. They are reused while the resulting context fits. Failed or
impossible compaction falls back to whole-turn trimming with a visible notice;
exhausting the shared deadline stops the task. Saved memories provide explicit
cross-task recall separately.
An individual complete turn larger than the summary input limit is not split
or skipped over to pretend it was summarized. That prefix keeps falling back
to trimming; full-history search and multi-part oversized-turn summarization
are separate future work.

`ContextSummary` binds its covered native message prefix to a SHA-256 digest.
The boundary cannot split a turn or leave an unresolved tool call. Prefix
validation uses canonical native serialization; old summaries remain valid
when later messages are appended. The host saves summary and full history
together on `SummaryUpdated`, including the current submitted user message.
Startup/restore validates the pair without requesting a summary or executing
past tools. Neither a summary nor its generation writes approved memory or
changes pending proposals. Summary streams have no tools, share cancellation
and the task deadline, and reject tool calls, truncation and oversized output.

Each submitted run is cancellable and bounded to eight model requests and 150
seconds. The host registers only its declared tools. Record reads are
date-bounded and paged; aggregate tools use complete snapshots and the domain
Review calculations, with explicit period comparisons and missing data.
Memory tools retrieve approved facts or create a pending proposal; they cannot
save a memory directly. Structured record proposals are bounded to ten cards
and 80,000 serialized bytes, validated through the capture parser on storage,
restore and opening. Model-supplied approval/evidence is rejected. Account
evidence is host-marked inferred; neutral capture input prevents the model's
description from masquerading as owner-provided account evidence in later
corrections. Opening review atomically creates a ready capture draft and
consumes the proposal. Capture owns local editing, final atomic business
write and Undo; no further model request is required. Legacy text proposals
remain readable as unsent drafts. Public web content is data, never a grant of
tool permissions. Search needs a separate owner-provided Brave API key, kept
in app-private preferences and excluded from backups. Fetch rejects non-public
destinations and bounds redirects, DNS/network work and response bytes;
JavaScript execution, authenticated browsing and PDF parsing are unsupported.

SQLite holds display messages, serialized runtime history, pending proposals,
model destination, confirmed/dismissed action outcomes and status. The latest
host outcomes accompany later prompts so an old tool result is not mistaken
for a still-pending proposal. Native replay history is structurally validated
before loading or restoring it. Serialized conversations are capped at 4 MiB
each and 32 MiB in aggregate while the host loads full histories; old chats can
be deleted to free space. Startup marks `Running` sessions `Interrupted`
without executing a request or tool. Deleted sessions cannot be resurrected by
an old worker. Memory provenance can outlive its source conversation. The host
invalidates active work before restoring a backup. Schema 22+ snapshots include
assistant tables; restore validates them before replacing anything, resets
running state, and leaves proposals unapproved. Older backups preserve current
assistant tables. Memory proposal confirmation and removal from the pending
list are one transaction.
Schema 23 marks the new structured proposal JSON format without changing table
columns, so older apps reject newer backups before interpreting those bodies.
Schema 24 similarly marks source-bound summaries in session JSON. Existing
sessions without a summary remain valid and old backups are still accepted.

The existing recognition path remains in place during this migration. Removing
its old runtime dependencies requires separate image, structured-output,
provider replay and capture regression parity; enabling the assistant alone
does not satisfy that gate. Android target checks are compilation evidence,
not evidence for physical-device TLS, lifecycle or background behavior.

One pinned-provider limitation: keyless OpenAI Chat sends no Authorization
header, while the v0.29.0 Responses adapter needs an explicitly empty header
to suppress its environment-key fallback. A gateway rejecting empty headers
needs an explicit configured key or a future upstream adapter fix. The app
never silently borrows provider credentials from the process environment.

## Recognition Runtime Submodule

NaviWealth consumes the standalone runtime from
`https://github.com/zsh-a/agent-runtime.git` through the Git submodule at
`third_party/agent-runtime`. Paths below are relative to that submodule root
unless prefixed with the submodule directory.

### Submodule Scope

The runtime provides:

- reusable Rust contracts and runner crates;
- schema / fixture / OpenAPI wire contracts;
- local CLI, HTTP, stdio, eval, replay, debug bundle, and TUI surfaces;
- a dependency-light TypeScript client under `bindings/ts`.

The runtime must remain independent of NSH, nsh-base, and NaviWealth domain
models. Business policy, permissions, repositories, and business side effects
stay in the host application. Rust agents consume domain-neutral contracts and
request effects through host gateways; adding one does not transfer domain
ownership into the standalone runtime.

### Submodule Code Map

```text
crates/
  agent-core/       Stable DTOs, traits, IDs, errors, trace/session/proposal contracts
  agent-runtime/    AgentRunner, scheduler, retry/timeout, lease locking, trace capture
  agent-store/      In-memory and file-backed run/state/proposal/session stores
  llm-protocol/     Typed LLM content, provider codecs, SSE and schema validation (no I/O)
  llm-client/       Runtime-neutral transport, retry, deadline and capability policy
  llm-reqwest/      Reqwest transport and native/browser provider adapters
  agent-chat/       Shared ChatTurn request/event contract and provider/tool loop
  agent-tools/      Reusable tool registry, policy, and tool-host helpers
  agent-cli/        Local developer surfaces and host adapters

schemas/            JSON Schema contracts for runtime wire types
fixtures/contracts/ Valid and invalid schema fixtures used by contract tests
openapi/            agent-runtime-api.yaml — HTTP API contract for server-first clients
```

### Submodule Runtime Layers

1. `agent-core` defines protocol shapes and host-facing traits.
2. `llm-protocol` owns typed LLM contracts, codecs and SSE parsing. `llm-client`
   owns shared request policy over a Host Transport; `llm-reqwest` implements
   that transport for native and browser hosts.
3. `agent-chat` owns provider-neutral interactive ChatTurn request/event
   contracts and the LLM/tool continuation loop over `AgentServices`.
4. `agent-runtime` executes scheduled or explicit `Agent` instances through
   `AgentRunner`.
5. `agent-store` persists run/state/proposal/session records.
6. Host adapters implement `AgentServices` and tool/proposal/state behavior.
7. CLI/server/TUI are surfaces over these contracts.

## How NaviWealth Uses It

- `crates/navi-health` performs meal recognition through `llm-protocol` wire
  types and `llm-client` request policy; the NSH client supplies its platform
  fetch as the Host Transport. Recognition is a single-shot draft operation;
  it does not use the general assistant loop. Unified capture
  uses `llm-reqwest` to receive SSE events through the same protocol/client
  contracts. Provisional cards remain in memory. Capture supports `ask_user`, persisting
  the suspended call and owner answers in its local draft. Continuation occurs
  only when the owner submits or retries; `agent-chat` is not adopted.
- `llm-protocol` owns Anthropic Messages, OpenAI Chat Completions and OpenAI
  Responses codecs. Responses requests keep `store: false`; native
  output items are returned as metadata for the host to persist and replay.
  The NSH host stores them only inside the draft and continues on owner input.
- Domain truth in `crates/navi-finance` and `crates/navi-health` never imports
  runtime crates; only recognition paths do.
- CI runs `cargo fmt --check` and `cargo test --workspace --locked` inside the
  submodule (`.github/workflows/crates.yml`).

## Invariants

- All top-level legacy runtime wire messages carry `protocol_version: "agent.v1"`;
  this is not the pi-rust message format.
- The submodule's cross-language contracts are JSON-first. Keep envelopes stable and put
  business-specific data in `input`, `output`, `payload`, or `metadata`.
- Runtime crates must not import NSH, nsh-base, or NaviWealth domain code.
- Business side effects are never executed by the runtime; hosts own
  confirmation and writes.

## Interaction Entrypoints

Use these entrypoints when debugging:

```bash
cd third_party/agent-runtime
rtk cargo run -p agent-cli -- list
rtk cargo run -p agent-cli -- tui
rtk cargo run -p agent-cli -- validate schemas/run-request.schema.json fixtures/contracts/run-request.valid.json
```

## Change Routing

| Change | Start Here | Required Checks |
|---|---|---|
| Add or change a wire field | `schemas/`, submodule `third_party/agent-runtime/crates/agent-core/`, fixtures | schema validation tests |
| Change LLM provider behavior | submodule `third_party/agent-runtime/crates/llm-protocol/`, `third_party/agent-runtime/crates/llm-client/` | `rtk cargo test` in the submodule |
| Change meal-recognition prompts or parsing | `crates/navi-health/` | health fixtures and adapter tests |
| Change unified capture prompts, tools or history replay | `apps/nsh-client/src/domain/capture.rs`, `apps/nsh-client/src/data/vision.rs` | capture and Responses adapter/headless flows |
| Change assistant providers, context or tool execution | `crates/navi-assistant/` | deterministic multi-step, continuation, cancellation and provider mapping tests |
| Change assistant records, memory, proposals or backup behavior | `apps/nsh-client/src/data/assistant*.rs`, `apps/nsh-client/src/data/db.rs` | session recovery, stale-write, confirmation and atomic restore tests |

## Legacy Submodule Limitations

- There is no standalone `bindings/dart` package; the pinned runtime ships
  `bindings/ts` only.
- Trace is event-first (`events`) and does not expose a separate `spans` array.
- `ScheduleSpec` supports `manual` and `interval` only.

Use this document and current tests as authority.
