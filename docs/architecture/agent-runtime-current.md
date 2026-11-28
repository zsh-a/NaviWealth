# Agent Runtime Current Architecture

Status: active native-runtime implementation reference.

## Document Contract

Owns the runtime boundaries used by NaviWealth: recognition and the general
assistant share pinned pi-rust through `crates/navi-assistant`. Source and
contract tests are authoritative for exact APIs. The former Agent Runtime
submodule and its protocol/client crates have been retired.

## Unified Conversation (2026-11-28)

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
| Durable composer, image selection, question staging and inline record reviews | `apps/nsh-client/src/data/assistant/conversation.rs` |
| Structured proposal validation | `apps/nsh-client/src/domain/assistant_proposal.rs` |
| Optional Brave Search and bounded public-page fetch | `apps/nsh-client/src/data/assistant_web.rs` |
| Sessions, messages, native replay history and approved memories | `apps/nsh-client/src/data/assistant_store.rs`, migrations 22–25 |
| Conversation, history and memory UI | `apps/nsh-client/src/pages/assistant.rs` |

The former assistant and plus-record actions open one conversation page. Opening
continues the most recently selected session; an explicit New conversation action starts
another. Text, image attachments, questions, editable record cards and saved
receipts share this timeline. Unsent text and attachments belong to the session
and survive switching, closing and restart. Record writes still require the
owner to confirm the complete review batch.

The model profile selects Anthropic Messages, OpenAI Chat Completions or OpenAI
Responses. Destination-scoped v2 consent covers submitted text/images, local account
context, recalled memories and requested records; older assistant consent does
not grant the expanded scope. Unsent typing remains local. The runtime preserves native message/tool-call
identity for subsequent turns; the host binds saved history to the model
destination. Context selection bounds serialized model input to 120,000 UTF-8
bytes while keeping native text and tool history. Persisted native image blocks are
replaced with explicit image-omitted text at every checkpoint, including the
pre-network checkpoint, summary update, cancellation and final result. The host
keeps normalized photo filenames on display messages and reattaches only the
images selected for an explicit request. Requests allow at most four images,
2 MiB each, with a separate serialized wire budget. Image bytes never consume
the 4 MiB durable session budget.
On an explicit new turn,
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
validation uses canonical native serialization with the same image redaction; old summaries remain valid
when later messages are appended. The host saves summary and full history
together on `SummaryUpdated`, including the current submitted user message.
Startup/restore validates the pair without requesting a summary or executing
past tools. Neither a summary nor its generation writes approved memory or
changes pending proposals. Summary streams have no tools, share cancellation
and the task deadline, and reject tool calls, truncation and oversized output.

Each submitted run is cancellable and bounded to eight model requests and 150
seconds. Provider setup and stream reads select cancellation directly, and the
host drains queued display events without rebuilding the UI after Stop. Only
fixed diagnostic codes cross the provider boundary: authentication, permissions,
quota/rate limits, HTTP/network/TLS, image support, incomplete or empty streams,
truncation and protocol errors. The UI provides a localized hint and code/version;
upstream response bodies and secrets are never retained in diagnostics.
The host registers only its declared tools. Record reads are
date-bounded and paged; aggregate tools use complete snapshots and the domain
Review calculations, with explicit period comparisons and missing data.
Memory tools retrieve approved facts or create a pending proposal; they cannot
save a memory directly. Structured record proposals are bounded to ten cards
and 80,000 serialized bytes, validated through the capture parser. A proposal
creates or revises a `capture_drafts` row and its session message reference in
one transaction; it does not save a business record. The timeline reads the
authoritative draft by `Message.capture_id`. Model-supplied approval/evidence
is rejected; account evidence remains host-marked inferred. Revisions bind to
the exact draft snapshot offered to the run, and submitted messages retain their
explicit revision target for retry. `Message.record_targets` is written in the
same transaction as each proposal/revision; retrying the same request and target
returns the existing outcome instead of applying relative edits twice. The
pre-request `history_start` preserves completed native turns when retry follows
a failure during summary preparation, before the new user turn was appended. Pending question choices are durable,
unselected by default, and checked against the exact pending question identity
before an explicit submission. They are UI proposal identities; provider-native
tool-call identity remains the runtime's responsibility.

Local review owns final atomic business writes and guarded Undo. Confirming or
discarding creates a durable `RecordAction` receipt with the reviewed record
snapshot; undo updates its status. The business write, draft consumption and
receipt update share the same SQLite transaction. A receipt-storage failure
rolls back the entire save or undo. Saved/discarded/undone cards remain in their
original timeline position. Durable receipts do not restore an expired Undo
capability: guarded undo data remains process-local. Legacy pending structured
proposals migrate into linked reviews without sending a request or approving
records; legacy text proposals remain readable as unsent drafts.
Public web content is data, never a grant of
tool permissions. Search needs a separate owner-provided Brave API key, kept
in app-private preferences and excluded from backups. Fetch rejects non-public
destinations and bounds redirects, DNS/network work and response bytes;
JavaScript execution, authenticated browsing and PDF parsing are unsupported.

SQLite holds display messages and image references, unsent composer state,
serialized runtime history, pending questions/proposals, model destination,
record receipts, confirmed/dismissed action outcomes and status. The latest
host outcomes accompany later prompts so an old tool result is not mistaken
for a still-pending proposal. Native replay history is structurally validated
before loading or restoring it. Serialized conversations are capped at 4 MiB
each and 32 MiB in aggregate while the host loads full histories; old chats can
be deleted to free space. Startup marks `Running` sessions `Interrupted`
without executing a request or tool. Deleted sessions cannot be resurrected by
an old worker. Memory provenance can outlive its source conversation. The host
invalidates active work before restoring a backup. Schema 22+ snapshots include
assistant tables; restore validates them before replacing anything, resets
running state, and leaves proposals unapproved. Schema 25 snapshots also include
only capture drafts linked by conversations, plus their referenced photos.
Restore validates IDs, references, record values and photo names before atomic
replacement. Photo collisions remap every session/draft reference; missing
incoming photos receive fresh unavailable filenames, so an unrelated existing
file can never become evidence. Older backups remain readable; pre-assistant
backups preserve current assistant tables and linked drafts. Deleting a session
removes only unshared pending drafts, never saved business records or approved
memories. Photo cleanup includes session messages and unsent attachments.
Memory proposal confirmation and removal from the pending list are one transaction.
Schema 23 marks the new structured proposal JSON format without changing table
columns, so older apps reject newer backups before interpreting those bodies.
Schema 24 similarly marks source-bound summaries in session JSON. Existing
sessions without a summary remain valid and old backups are still accepted.
Schema 25 marks unified composer, image, question-answer and receipt fields;
older sessions deserialize these additions with empty/default values.

Recognition uses the same pinned provider libraries through a separate
single-turn API described below. Android target checks are compilation
evidence, not evidence for physical-device TLS, lifecycle or background behavior.

One pinned-provider limitation: keyless OpenAI Chat sends no Authorization
header, while the v0.29.0 Responses adapter needs an explicitly empty header
to suppress its environment-key fallback. A gateway rejecting empty headers
needs an explicit configured key or a future upstream adapter fix. The app
never silently borrows provider credentials from the process environment.

## Retained Single-Call Recognition and Legacy Capture

The former Agent Runtime submodule is removed. Meal recognition and the retained
legacy capture component use pi-rust provider adapters in `crates/navi-assistant`;
connection tests use the same provider path. These bounded APIs remain available
for dedicated recognition and legacy component tests. The normal unified
conversation entry uses the assistant Agent loop described above. The retained
single-call recognition API does not run that loop or execute model-selected tools.

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
result against its schema and domain contracts. Recognition requests carry
the result schema directly; protocol-version, effort, response-format names
and request metadata from the retired runtime are not part of this API.
Only content blocks and provider replay metadata retain saved-draft compatibility. Legacy JSON text responses
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
Unlinked legacy capture drafts remain excluded from backups. Drafts adopted into
unified conversations follow the linked-draft backup contract above. Each retained recognition run
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
| Change legacy recognition prompts, tools or history replay | `apps/nsh-client/src/domain/capture.rs`, `apps/nsh-client/src/data/vision.rs` | Capture, streaming and explicit legacy harness continuation flows |
| Change unified composer, revisions or record receipts | `apps/nsh-client/src/data/assistant/conversation.rs`, `apps/nsh-client/src/data/capture/batch.rs` | Session, draft identity, atomic receipt and unified conversation flows |
| Change assistant context or tool execution | `crates/navi-assistant/` | Deterministic multi-step, continuation, cancellation and provider mapping tests |
| Change assistant records, memory, proposals or backup behavior | `apps/nsh-client/src/data/assistant*.rs`, `apps/nsh-client/src/data/db.rs` | Session recovery, stale-write, confirmation and atomic restore tests |

CI checks the first-party runtime alongside the other independent Cargo
workspaces with fmt, strict clippy and locked tests. Provider libraries are
pinned by revision and lockfile; there is no separate runtime submodule job.

## Recognition failure diagnostics

Capture and meal review show a localized cause, recovery guidance and an
allowlisted diagnostic code with the app version. Capture retains the explanatory
body instead of showing only the error title. Output-token exhaustion is distinct
from an incomplete response stream; JSON decoding, schema validation, protocol,
clarification, record values and image references have separate classifications.
HTTP failures include their validated status. Provider bodies, arbitrary error
text, API keys and submitted content are never included in these diagnostics.
The safe failure detail lives with the in-memory draft state; after process
restart the saved draft remains, but the UI explicitly says the previous detail
is unavailable and offers a new owner-initiated attempt. No automatic retry or
business-record write is added.
