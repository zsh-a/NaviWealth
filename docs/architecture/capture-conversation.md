# Capture Is A Bounded Conversation

Status: accepted.

Date: 2026-11-15. Implementation is sequenced in the
[roadmap](../roadmap/roadmap-nsh.md); the descriptive interaction text in
[Product Scope](../product/product-scope.md) and
`apps/nsh-client/DESIGN.md` updates when the increment lands.

## Context

Capture turns one description or photo into record drafts through the
owner's own model account. Today recognition is a single structured
request; the draft carries at most one plain question string, and every
correction re-sends the whole draft as a fresh one-shot request. The owner
reviewed this in daily use (2026-11-15): the question has no visual
identity, the answer box does not echo the question, and re-parsing the
whole draft after each sentence feels unstable. The owner chose a
chat-timeline capture experience.

Constraints that still hold: [Personal Local Scope](personal-local-scope.md)
removed AI chat and agents as features; recognition runs on device against
user-owned profiles through `llm-protocol`/`llm-client`; NSH `fetch`
returns a whole body (no streaming); nothing is saved without explicit
confirmation; drafts live in SQLite and stay out of backups.

## Decision

1. **The capture thread is the interface.** The owner's text or photo is
   the first message of a thread inside the capture sheet. Recognition
   results, clarifying questions and corrections are turns of that thread.
   The separate "input recap" block and the dual-role correction box
   disappear.
2. **A bounded conversation, not AI chat.** The thread exists only inside
   one capture draft. The model only ever answers owner-initiated turns:
   no autonomous turns, no background rounds, no named agents,
   and no memory across drafts. The only tool is `ask_user`, which suspends
   the current request for an explicit owner response. It discusses nothing beyond turning the
   input into records. Confirming consumes the thread; discarding deletes
   it. Threads stay out of backups, like drafts today.
3. **The confirmation boundary is unchanged.** A thread never saves
   anything. The confirm action stays a single atomic batch write of all
   records, enabled only when every record is valid; missing money fields
   stay missing and block confirmation; estimates stay marked; a named new
   account is created only on confirm; the consent gate is unchanged.
4. **Decisions use one tool.** The model calls only `ask_user`, with one
   to three questions. Each has a stable ID, question text, reason, required
   flag and up to four choices with IDs, labels and descriptions. Nothing is
   preselected. Choices are staged locally, can be changed, and are submitted
   together through Submit answers; text and image-only evidence remain valid
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
   contains only the complete records array; questions do not have a second
   live response channel. Existing stored plain questions and option chips
   remain readable for backward compatibility. Images replay with the owner
   turn or tool answer that supplied them.
6. **No fake streaming.** NSH `fetch` returns a whole body, so text never
   types out progressively. Presence while working is a typing indicator
   in the thread; results arrive as whole turns with the existing appear
   motion. A chunked transport is a separate future decision, not part of
   this one.
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
  destination and needs a transport upgrade that does not exist; revisit
  only with owner evidence after daily use.

## Consequences

- Product Scope Rule 3 changes from "not a chat timeline" to the bounded
  conversation above; the Removed entry for "AI chat" refers to free-form
  chat and agents, not to this thread.
- Cost and latency scale with owner-initiated turns only; each photo belongs to its owner turn and is replayed with that turn in subsequent requests.
  Multi-turn prompt quality becomes part of the existing "real-model
  quality" verification item.
- `agent-chat` from the Agent Runtime is not adopted: its durable
  interaction and tool machinery serves autonomous loops; the thread uses
  `llm-protocol` tool-use/result blocks with a single suspended tool.
- Headless flows gain thread scenarios: chip answering, multi-turn
  correction, reopen-after-restart, degraded bare-string questions.

## Image evidence

A draft accepts at most four images across the whole thread. The composer
accepts images on the first turn and on later owner-initiated turns, including
an image-only answer. Unsent images can be removed; sent images remain with
their original message. Closing/reopening and interrupted-request retries
preserve these references. Older single-photo drafts remain readable.

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
