# Agent Runtime Current Architecture

Status: active native-runtime implementation reference.

## Document Contract

Owns the runtime boundaries used by NaviWealth: recognition and the general
assistant share pinned pi-rust through `crates/navi-assistant`. Source and
contract tests are authoritative for exact APIs. The former Agent Runtime
submodule and its protocol/client crates have been retired.

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

Recognition uses the same pinned provider libraries through a separate
single-turn API described below. Android target checks are compilation
evidence, not evidence for physical-device TLS, lifecycle or background behavior.

One pinned-provider limitation: keyless OpenAI Chat sends no Authorization
header, while the v0.29.0 Responses adapter needs an explicitly empty header
to suppress its environment-key fallback. A gateway rejecting empty headers
needs an explicit configured key or a future upstream adapter fix. The app
never silently borrows provider credentials from the process environment.

## Recognition and Capture

The former Agent Runtime submodule is removed. Both meal recognition and
unified capture use pi-rust provider adapters in `crates/navi-assistant`;
connection tests use the same provider path. Recognition does not run the
assistant Agent loop and does not execute model-selected tools.

`crates/navi-health/src/recognition.rs` owns pure meal preparation, prompts,
JSON Schema, strict parsing and catalog validation. Preparation validates
model-destination consent before decoding and re-encoding photos. The app
assigns local food IDs and composes the result with its draft. Health has no
model-client dependency. Unified capture prompts, evidence, editable records
and atomic confirmation remain app-owned.

The pinned pi-rust API has no separate structured-response option. Recognition
therefore declares an `emit_result` tool whose input schema is the result
schema, alongside capture's `ask_user` tool. An `emit_result` call returns a
draft; it executes no business operation. The host validates the complete
result against its schema and domain contracts. Legacy JSON text responses
remain accepted only after the same validation. Multiple or mixed result and
question calls are rejected. Streaming text or result arguments may produce
provisional cards in memory; only a valid terminal response can produce a
persistable final result. A disconnected or truncated stream is not repaired
into a successful draft.

`ask_user` stores a suspended call in the draft. Only explicit owner submission
or retry continues it. Existing drafts retain their saved content blocks and
provider output through a compatibility boundary; new native replay metadata
preserves pi message identities. Anthropic signed thinking and Responses
reasoning/output identity must survive continuation. Result-tool calls are
acknowledged when constructing a later request so replay never contains an
unanswered completed result call. Responses remains stateless (`store: false`).
The pinned Responses adapter preserves composite tool identities in its
`call_*|fc_*` form. Nonstandard gateway call/item pairs that it would rewrite
are rejected before accepting or replaying a draft; safe standalone call IDs
remain supported. Existing nonstandard pairs require upstream adapter support
to continue, rather than sending an answer under a different call ID.
Restart, reopening and backup restore never start a request or execute a tool.
Capture drafts remain excluded from backups; assistant sessions and approved
memories use their existing encrypted-backup contracts. Each recognition run
makes one request without automatic retries or capability-fallback calls. A
gateway that rejects constrained tools returns an error for owner review; the
runtime does not silently replay uploaded images in a second request.

Recognition bounds serialized request input to 32 MB and decoded response
messages to 100 KB, with a total deadline and cancellation. These checks do
not impose a hard pre-parser byte cap on a malformed SSE frame or an upstream
HTTP error body; the pinned provider currently owns that buffering.

All requests use owner-configured endpoints and credentials, bounded deadlines
and cancellation. Credentials do not follow redirects and are never borrowed
from process environment variables. The host's cancellation guard terminates
an abandoned recognition worker. No backend relay or cloud fallback is added.

## Change Routing

| Change | Start Here | Required Checks |
|---|---|---|
| Change model provider adaptation or recognition transport | `crates/navi-assistant/` | Real loopback HTTP/SSE fixtures for all three providers, images, structured results, replay and cancellation |
| Change meal preparation, prompts or parsing | `crates/navi-health/src/recognition.rs` | Health consent/photo/schema/parser contracts |
| Change unified capture prompts, tools or history replay | `apps/nsh-client/src/domain/capture.rs`, `apps/nsh-client/src/data/vision.rs` | Capture, streaming and headless continuation flows |
| Change assistant context or tool execution | `crates/navi-assistant/` | Deterministic multi-step, continuation, cancellation and provider mapping tests |
| Change assistant records, memory, proposals or backup behavior | `apps/nsh-client/src/data/assistant*.rs`, `apps/nsh-client/src/data/db.rs` | Session recovery, stale-write, confirmation and atomic restore tests |

CI checks the first-party runtime alongside the other independent Cargo
workspaces with fmt, strict clippy and locked tests. Provider libraries are
pinned by revision and lockfile; there is no separate runtime submodule job.
