# Capture Is A Bounded Conversation

Status: accepted.

Accepted 2026-11-15. Updated 2026-11-27. See the [roadmap](../roadmap/roadmap-nsh.md)
and [Product Scope](../product/product-scope.md) for scope and outstanding device checks.

## Context

Capture turns one description or photo into record drafts through the
owner's own model account. The original implementation used a single structured
request. A draft carried at most one plain question string, and every
correction re-sent the whole draft as a fresh one-shot request. The owner
reviewed this in daily use (2026-11-15): the question has no visual
identity, the answer box does not echo the question, and re-parsing the
whole draft after each sentence feels unstable. The owner chose a
chat-timeline capture experience.

Constraints that still hold: recognition runs on device against
user-owned profiles through pinned pi-rust providers in `navi-assistant`.
Unified capture receives native provider events and validates structured result
tool arguments locally. Records require explicit confirmation; drafts live in SQLite and stay out of backups.
The owner authorized a separate general assistant on 2026-11-27, recorded in
[Personal Local Scope](personal-local-scope.md). Its persistent conversations
and memories do not change this capture-specific lifecycle or confirmation boundary.

## Decision

1. **The capture thread is the interface.** The owner's text or photo is
   the first message of a thread inside the capture sheet. Recognition
   results, clarifying questions and corrections are turns of that thread.
   The separate "input recap" block and the dual-role correction box
   disappear.
2. **A bounded conversation, not AI chat.** The thread exists only inside
   one capture draft. The owner controls submissions. A separate per-profile setting enables text-only
   previews after a 700 ms typing pause. Edits, closing the composer, or sending
   cancel a pending preview. Its output is ephemeral. A second setting allows
   bounded recent records, favorites and held security identities on Send. The only tool is `ask_user`, which suspends
   the current request for an explicit owner response. It discusses nothing beyond turning the
   input into records. Confirming consumes the thread; discarding deletes
   it. Threads stay out of backups, like drafts today.
3. **The confirmation boundary is unchanged.** A thread never saves
   anything. The confirm action stays a single atomic batch write of all
   records, enabled only when every record is valid; missing money fields
   stay missing and block confirmation; estimates stay marked; a named new
   account is created only on confirm. A suggested funding account needs explicit
   approval. The receipt offers a guarded atomic Undo that preserves later edits.
4. **Decisions use one tool.** The model calls only `ask_user`, with one
   to three questions. Each has a stable ID, question text, a reason when useful, required
   flag and up to four choices with IDs, labels and descriptions. Nothing is
   preselected. Choices are staged locally, can be changed, and are submitted
   together through Continue; text and image-only evidence remain valid
   responses. Required questions need an answer or supplemental evidence;
   optional questions may be omitted. Omitting a question is not consent to an
   invented fact. Missing money fields still prevent confirmation.
5. **Protocol-correct continuation.** An assistant tool call (including its
   original signed content blocks) persists in the draft. The owner response
   references that exact call ID and replays as a tool result, followed by any
   supplemental image message. One owner submission makes one model request;
   the app never automatically resumes or loops over tools. Only one
   `ask_user` call is accepted in a response. Unknown tools, malformed arguments
   and reused call IDs fail without writing records. A normal final answer
   contains the complete records array and a nullable destination. A request to view
   data can return an empty array and a link to Review, Assets or Records. Later
   submissions carry the locally edited set, including removals. Existing stored plain questions and option chips
   remain readable for backward compatibility. Images replay with the owner
   turn or tool answer that supplied them.
6. **Streamed record cards.** Anthropic Messages, OpenAI Chat and OpenAI Responses
   use their native streaming formats. Complete, individually parsed cards can
   appear while the provider is still working. Editing and confirmation wait
   for a successful final response and domain validation. Stream interruption
   clears provisional cards and exposes retry. Field evidence accompanies the
   final records and local edits take precedence.
7. **Same home for the thread.** Capture keeps its sheet entry beside the
   tab bar. The first entry field sits under the title. On later turns the
   panel expands to the available screen above the keyboard. The latest exchange
   stays visible, earlier messages fold, and the footer offers a reply on demand
   alongside the current action. Capture does not
   become a tab, page or destination.

## Alternatives Considered

- **Single question card with option chips (no thread).** Cheapest, and
  its pieces (chips, question styling, typing indicator) are absorbed into
  the thread, but it keeps the one-shot model: no continuity, and the
  owner still answers into an unlabeled box.
- **Thread only for clarification, composer before it.** Two interaction
  models in one sheet; the input recap and mode switch stay.
- **Full-screen chat page with streaming.** Elevates capture into a
  destination outside the four-tab interaction model.

## Consequences

- Capture follows the bounded conversation above. The separately authorized
  general assistant has its own persistent conversation page and runtime;
  structured proposals from that assistant open editable capture cards after
  confirmation; older text proposals open unsent drafts. Neither path confirms
  business records automatically.
- Each Send and each optional debounced typing preview is a separate request; each photo belongs to its owner turn and is replayed with that turn in subsequent requests.
  Multi-turn prompt quality becomes part of the existing "real-model
  quality" verification item.
- Recognition uses a single pi-rust provider request, without the general
  assistant loop. The thread preserves tool-call/result identity and supports
  a single suspended `ask_user` call. The `emit_result` schema tool only returns
  a draft; later replay acknowledges its result without executing a side effect.
- Headless flows gain thread scenarios: chip answering, multi-turn
  correction, reopen-after-restart, degraded bare-string questions.

## Image evidence

A draft accepts at most four images across the whole thread. The composer
accepts images on the first turn and on later owner-initiated turns, including
an image-only answer. Unsent images can be removed; sent images remain with
their original message. Closing/reopening and interrupted-request retries
preserve these references. Older single-photo drafts remain readable.

The device numbers distinct sent images from 1 to 4 by their first appearance.
Each image-bearing message carries `image_numbers` in attachment order. A
correction keeps those numbers when the thread is replayed. Each meal in a
final reply requires `meal.source_image`, either a sent image number showing
that meal or null. Only the cited photo is kept with the confirmed meal. A
scale photo, receipt or unrelated image in the same capture can remain
unlinked. References to unsent images fail local validation before confirmation.
Older drafts with exactly one record (a meal) and one sent image retain that
association. Ambiguous older batches keep their meals without an assigned photo.

The model distinguishes multiple views or documents for one record from
independent records. It reconciles the same serving or transaction once;
labels support the matching product and after-meal photos describe leftovers.
Unclear relationships or materially missing consumption information prompt a
short question with useful choices or a request for supporting evidence.
Outstanding questions and unsent evidence prevent confirmation.

Capture uses metadata-free images bounded to a 4096 px edge, four megapixels
and 2 MiB each. Lossless PNG is preferred when within the byte budget; noisy
images use bounded high-quality JPEG. The picker does not first shrink or
lossily encode capture inputs. The durable evidence is the same normalized
image used for requests; MIME follows its actual encoding. This differs from
the smaller meal-photo preparation path. Recognition quality still needs
comparison against real owner samples; headless tests establish flow and wire
contracts, not estimation accuracy.

## Ask User durability and confirmation

A pending tool call, staged answers and staged images survive close/reopen and
restart. Choices carry no record side effects. A failed continuation retains
the exact tool result for an owner-initiated retry; it does not create a second
answer. The UI verifies the active call ID before applying a choice, and cannot
submit historical questions. Consent still covers text, images and account
names sent to the owner's configured model.

While a tool is pending, while its answer awaits a successful final model
reply, or while any new answer/text/image is unsent, confirmation is blocked.
Keeping an earlier recognition result after a failed continuation cannot bypass
that gate. Final confirmation remains one atomic batch write.

## Compatible provider output contracts

Every capture request includes the complete final-record JSON Schema and a
plain-JSON-only instruction in its system prompt, in addition to the native
structured-output option. Some Anthropic-compatible services accept that option
without enforcing its schema: tool calls can succeed while the final response
uses code fences or different record fields. The prompt must therefore carry
the contract explicitly. Local schema and domain validation remain mandatory;
formatting problems never authorize guessed accounting fields or record writes.
Diagnostics keep only bounded error classifications, never provider response
contents, thinking, owner input, image data or credentials.

## OpenAI Responses

The model profile explicitly selects Anthropic Messages, OpenAI Chat Completions
or OpenAI Responses. Responses is a distinct protocol with a distinct consent
fingerprint. It uses `store: false` and locally replayed native output items;
server-side conversation IDs are not a persistence dependency. The draft keeps
native reasoning, message and function-call items with each assistant turn,
including the items needed to resume an `ask_user` call after restart. Tool
answers reference the function call's `call_id`, never its output item's `id`.
Images follow as input-image content. Malformed, failed or incomplete responses
cannot become confirmed records. Legacy drafts without native output remain
readable, and their text/image history can still be encoded.
