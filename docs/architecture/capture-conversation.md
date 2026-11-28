# Unified Conversation and Record Review

Status: accepted and implemented.

Accepted 2026-11-15; unified-session decision accepted 2026-11-28. See the
[roadmap](../roadmap/roadmap-nsh.md), [Product Scope](../product/product-scope.md)
and [runtime architecture](agent-runtime-current.md) for scope, implementation
boundaries and outstanding device checks.

## Context

The original capture sheet turned descriptions and photos into editable record
drafts through a bounded conversation. The separately authorized general
assistant added ongoing conversation, memory, web research and multi-step work.
Two entry points made an ordinary question, a photo and a follow-up correction
feel like different tasks. The owner chose one persistent session entry:
continue the most recent conversation when opening, with a visible New
conversation action.

The application remains local-first. Models run against owner-configured
profiles through pinned pi-rust in `navi-assistant`; there is no backend relay
or cloud fallback. Business truth stays in domain repositories. Every saved
record batch requires explicit owner confirmation.

## Decision

1. **One conversation entry.** The home action opens the conversation page.
   Text, images, questions, record proposals and receipts share a timeline.
   General questions do not require a record mode. The four main tabs remain;
   conversation is an auxiliary page with Back, history and New conversation.
2. **Session-owned composition.** Unsent text, attachments and the selected
   record revision target persist on the session. Switching conversations,
   closing the page and restarting preserve that state. Sent messages retain
   image filenames and their explicit revision target so an owner-initiated
   retry cannot accidentally turn a correction into a new record batch.
3. **Inline reviews use authoritative drafts.** A record proposal creates a
   `capture_drafts` row and a message referencing its ID in one transaction.
   The timeline reads that row, including local edits and field evidence.
   A model revision can replace only a draft whose snapshot still matches the
   one supplied to that run. A late result cannot overwrite a newer edit.
   Existing unlinked capture drafts are adopted into conversations without
   sending a request. Legacy structured assistant proposals migrate to linked
   reviews without approving their records.
4. **Confirmation stays explicit and atomic.** The model cannot save records.
   Confirm is available only when every card is valid and blocking questions
   or unsent changes are resolved. Missing money fields remain missing;
   inferred accounts require approval; estimates remain marked. Confirmation
   consumes the draft, writes the business records and stores a durable saved
   receipt in one transaction. Discard removes the pending draft and stores
   a discarded receipt. Guarded Undo updates business records and the receipt
   together, preserving later independent edits. Receipt failures roll back
   the complete save or undo.
5. **Receipts stay in the timeline.** `Session.record_actions` keeps the capture
   ID, saved/discarded/undone status, reviewed record snapshot and timestamp.
   The original message position remains stable. Receipts survive restart and
   backup; the guarded Undo capability is process-local and is not recreated
   from restored history. Deleting a conversation removes only its unshared
   pending drafts. Confirmed records and approved memories remain.
6. **Questions are explicit proposals.** A question contains stable IDs,
   wording, an optional reason, a required flag and up to four named options;
   at most three questions are grouped together. Nothing is preselected.
   Staged choices persist with that exact pending proposal and can be changed
   before Continue. Required questions need an answer or supplemental text or
   images; optional questions may be omitted. The host rejects stale question
   and option IDs. These local question identities are separate from native
   provider tool-call IDs, which the Agent runtime owns.
7. **Runs are bounded and cancellable.** Only explicit Send, Continue or Retry
   starts model work. Running indicators and errors belong to the conversation.
   Tools can read permitted local data, research public pages, propose memory
   or propose records within the runtime budget. Startup and restore never
   resume requests, replay tools or interpret saved messages as authorization.
   The unified composer does not automatically send typing previews.

## Image evidence

The composer accepts up to four attachments, including image-only messages.
Unsent images can be removed; sent images remain with their original message.
Requests select relevant evidence from the current review, explicit attachments
or a recent image-bearing exchange, with a total of at most four images. A long
session does not resend every historical photo. Missing selected image bytes
produce a visible reattachment error before sending.

Images are normalized without metadata, bounded to a 4096 px edge, four
megapixels and 2 MiB each. Lossless PNG is preferred within that byte budget;
noisy images use bounded high-quality JPEG. MIME follows the actual encoding.
Normalized photo filenames are the durable references on messages and drafts.
A message distinguishes its explicitly attached `images` from the actual
`request_images` sent for that turn. Retry uses the latter; timeline thumbnails
and recent-image selection use the former. Carried evidence therefore does not
turn every later text-only message into another image-bearing message. Both
sets participate in photo retention, backup and restore remapping.
Every native history checkpoint replaces image payload blocks with explicit
image-omitted text; summaries hash the same redacted representation. Images are
reattached separately for explicit requests, so base64 image bodies never grow
session JSON or survive in provider replay history.

The request numbers its selected images. Every proposed meal must name its
`source_image` number or explicitly choose null. Local parsing checks that the
number belongs to sent evidence. Only that photo is assigned to the saved meal;
a scale photo, receipt or unrelated attachment does not become a meal photo.
Legacy one-meal/one-image drafts retain their unambiguous association. Ambiguous
older batches retain meals without inventing an association.

The model distinguishes multiple views of one serving or transaction from
independent records. Labels can support a product and after-meal images can
show leftovers. Unclear relationships or materially missing consumption
information should produce a short clarification. Headless tests establish
request, persistence and flow contracts; recognition quality still requires
comparison against actual owner samples.

## Persistence and backup

Schema 25 adds backward-compatible session/message fields for composition,
attachments, revision targets, question choices and record receipts. Sessions
are bounded to 4 MiB each and 32 MiB in aggregate. Capture drafts remain the
single source of truth for unconfirmed cards; a session stores references.
Approved cross-task memories retain their own confirmation and deletion rules.

Encrypted backups include assistant sessions, approved memories, and only
capture drafts linked by conversations. Unlinked legacy recognition drafts
remain device-local. Photo export and garbage collection include session
messages, unsent attachments and linked drafts, in addition to meals and
favorites. Restore validates session identities, draft references, record
values and safe photo filenames before replacing destination tables atomically.
Incoming photo collisions remap all references. Missing incoming photos get
fresh unavailable references, preserving evidence positions without binding an
unrelated existing file. Running sessions become interrupted and analyzing
reviews become editable; no request or business operation is replayed.

Older session bodies deserialize new fields with defaults. Backups before the
assistant existed preserve the device's current conversations and linked
reviews. Newer full backups replace conversations and their linked drafts
together. A missing draft without a terminal receipt, or a completed receipt
that still has a pending draft, rejects restore.

## Retained bounded recognition API

The former capture sheet remains a legacy component with explicit test harness
coverage. Dedicated meal recognition and this component use the separate
single-call API through the same pinned providers. It remains useful for
bounded recognition contracts; it is not the normal unified conversation entry.

A legacy capture submission makes one request without automatic retries or a
capability-fallback request. `emit_result` returns validated draft data and
`ask_user` suspends for an explicit owner response. Existing saved content
blocks, signed Anthropic thinking and Responses output identities retain their
compatibility boundary. A continued legacy question references its exact
provider call ID; later replay acknowledges completed result-tool calls.
Responses stays stateless (`store: false`). Unusual composite gateway call IDs
that the pinned adapter would rewrite are rejected rather than resumed under
a different identity. Old plain questions and option chips remain readable.

Legacy streaming can show provisional, individually parsed record cards.
Editing and confirmation wait for a valid final response. A disconnected or
truncated stream clears provisional results and requires an owner-initiated
retry. Its optional, separately consented typing-preview setting applies only
to this retained component. The unified Agent entry uses its own bounded loop,
durable session and proposal tools.

## Output validation and failure diagnostics

Structured records always pass local schema and domain validation. A provider
accepting constrained tools does not guarantee that its response obeys the
schema. Legacy plain-JSON compatibility therefore includes the full contract in
the prompt, and applies the same validation to fenced or otherwise compatible
JSON. A partial stream, invalid image reference or missing accounting field
cannot become a confirmed record.

Capture and meal review retain detailed localized failure wording, recovery
guidance and an allowlisted diagnostic code with the app version. Output-token
exhaustion differs from an incomplete stream; JSON decoding, schema validation,
protocol, clarification, record values and image references have separate
classifications. HTTP errors include their validated status. Diagnostics never
include raw provider bodies, thinking, owner input, image bytes or credentials.
After restart a saved failed draft remains available, but any unavailable
in-memory diagnostic detail is identified as such. Retry is always an explicit
owner action and never confirms business records.
