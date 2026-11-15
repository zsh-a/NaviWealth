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
   no autonomous turns, no tools, no background rounds, no named agents,
   and no memory across drafts. It discusses nothing beyond turning the
   input into records. Confirming consumes the thread; discarding deletes
   it. Threads stay out of backups, like drafts today.
3. **The confirmation boundary is unchanged.** A thread never saves
   anything. The confirm action stays a single atomic batch write of all
   records, enabled only when every record is valid; missing money fields
   stay missing and block confirmation; estimates stay marked; a named new
   account is created only on confirm; the consent gate is unchanged.
4. **Questions become structured.** The per-turn response schema grows
   from `question: string` to `questions: [{text, kind, options}]` with
   tap-first options drawn from known accounts and categories (free text
   remains). Records and questions may share a turn; confirmation stays
   gated on readiness. The change is client-local
   (`apps/nsh-client/src/domain/capture.rs`), bumps `PROMPT_VERSION`, and
   touches neither `navi-finance` nor `navi-health`.
5. **Real multi-turn requests.** With a thread present, requests carry the
   conversation as proper alternating messages instead of re-embedding the
   draft in one user message. Photos ride only on the first turn. A bare
   string question from an older response degrades to a single plain
   question turn.
6. **No fake streaming.** NSH `fetch` returns a whole body, so text never
   types out progressively. Presence while working is a typing indicator
   in the thread; results arrive as whole turns with the existing appear
   motion. A chunked transport is a separate future decision, not part of
   this one.
7. **Same home for the thread.** Capture keeps its sheet entry beside the
   tab bar; the thread scrolls inside the sheet with the input pinned
   above the keyboard and the confirm action fixed. Capture does not
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
- Cost and latency scale with owner-initiated turns only; photos ride once.
  Multi-turn prompt quality becomes part of the existing "real-model
  quality" verification item.
- `agent-chat` from the Agent Runtime is not adopted: its durable
  interaction and tool machinery serves autonomous loops; the thread needs
  only message history and structured questions.
- Headless flows gain thread scenarios: chip answering, multi-turn
  correction, reopen-after-restart, degraded bare-string questions.
