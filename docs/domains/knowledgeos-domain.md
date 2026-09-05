# KnowledgeOS Domain SSOT

KnowledgeOS is NaviWealth's opt-in decision-memory domain. It keeps useful
source material close to the decisions it informed without becoming a wiki,
publishing system, or general-purpose object database.

## Document Contract

This document owns KnowledgeOS product vocabulary, persistence, routes, tools,
proposal behavior, and Memory indexing. Shared Memory Runtime, Sync v3, and AI
wire contracts remain owned by their architecture documents. The production
inventory in `knowledge_pack.dart`, the Knowledge repository, and focused tests
is executable authority.

## Product Model

KnowledgeOS has exactly three domain entities:

| Entity | Purpose | Synced table |
|---|---|---|
| Note | Captured source material, observations, and working thoughts | `knowledge_notes` |
| Decision | A chosen option, rationale, expected/actual outcome, and optional review conditions | `knowledge_decisions` |
| Relation | An explicit Note ↔ Decision or same-kind association | `knowledge_relations` |

There is no typed-object taxonomy, promotion pipeline, or compatibility object
layer. Principles, assumptions, concepts, experiments, and routines are not
KnowledgeOS entities. Stable personal rules belong in Personal Profile;
recurring or actionable work belongs in ExecutionOS.

Core rule: store material that improves future recall or explains a decision.
Ordinary life events remain Memory Runtime events rather than Knowledge rows.

## Shell And Routes

`kKnowledgePack` registers the domain through the shared `DomainPack` seam.

| Surface | Route | Purpose |
|---|---|---|
| Inbox | `/knowledge` | Fast capture, due Decision reviews, and recent Notes |
| Library | `/knowledge/library` | Search and browse Notes and Decisions |
| Note detail | `/knowledge/library/note/:id` | Direct editing and deletion |
| Decision detail | `/knowledge/library/decision/:id` | Direct editing, outcome, and status |

Inbox and Library are the only shell tabs. KnowledgeOS has no Review route,
hidden tab, background Agent, triage queue, or separate lifecycle dashboard.
Due decisions surface as a compact Inbox section and remain available through
`list_due_reviews` and normal Library access. Inbox limits its Note list to
recent captures; the full collection belongs to Library. Due reviews use an
independent owner-scoped repository query, so the Library's recent-row limit
cannot omit older due decisions. Inbox previews three reviews and expands the
complete due list lazily. Notes and reviews retain independent loading/error
states; refresh waits for both sections.

Key files:

- `features/knowledge/composition/knowledge_routes.dart`
- `features/knowledge/composition/knowledge_domain_shell.dart`
- `features/knowledge/ui/knowledge_inbox_page.dart`
- `features/knowledge/ui/knowledge_library_page.dart`
- `features/knowledge/ui/knowledge_note_detail_page.dart`
- `features/knowledge/ui/knowledge_decision_detail_page.dart`

Capture lets the user choose Note or Decision directly. It never saves an
intermediate Note merely to classify or promote it later. A new Decision
requires a question, one to three unique candidate options, and an explicit
selection from those options. Each option may keep a short rationale; existing
rows with more options remain editable without adding further options. The
richer review fields can be edited on the detail page. Note capture writes
optional source URL and tags in the same canonical row, matching the provenance
retained by system-share capture. Source URLs are normalized to HTTP(S)
document identity, render as an external-link card on Note detail, and receive
a non-blocking inline warning when quick capture finds an existing live Note
with the same source.

Note and Decision editors share one reliability contract: unchanged forms do
not submit, dirty forms guard system/back-button dismissal, in-flight saves
cannot be dismissed, invalid fields stay visible, and deletion always requires
explicit confirmation.

Decision detail keeps review work out of the general text editor. A focused
review sheet owns review date, revisit conditions, actual outcome, and status;
completing it persists the same Decision row and removes terminal Decisions
from the Inbox due section.

## Persistence And Sync

Drift declarations live in `core/persistence/knowledge_tables.dart`; business
access goes through `features/knowledge/data/knowledge_repository.dart`.

Synced row families:

- `know:knowledge_notes`
- `know:knowledge_decisions`
- `know:knowledge_relations`

All three use Sync v3 row-state semantics, owner scoping, soft deletion, HLC
stamps, and the shared outbox.

Schema version 81 destructively replaces the former Knowledge tables with the
three canonical tables. There is no legacy decoder, dual write, compatibility
query, or migration backfill for retired object types.

## Search And Memory

Knowledge source rows remain authoritative in Drift. Two domain indexers mirror
them into Memory Runtime:

- `knowledge_note_memory_indexer.dart` → `know:notes`
- `knowledge_decision_memory_indexer.dart` → `know:decisions`

Search iterates these concrete sources because Memory Runtime source filtering
is exact-match. Lexical fallback hydrates only live Notes and Decisions from the
repository. Decision memories use `role=decision` and `authority=source_fact`;
Note memories use `role=episode`.

Library exposes the same unified search seam with All, Notes, and Decisions
scopes. Empty-query browsing is a single update-ordered collection; active
queries merge semantic recall with deterministic lexical matches from canonical
Notes and Decisions. The lexical path remains available when the derived index
is cold, partially populated, or unavailable on Web/native devices.

## AI Tools

The bounded catalog in `knowledge_ai_tools.dart` contains:

- `recall_decision`
- `list_due_reviews`
- `search_notes`
- `search_knowledge`
- `find_similar_knowledge`
- `propose_capture`
- `propose_merge`

`propose_capture` accepts an explicit `note` or `decision` target and returns a
proposal envelope. Decision proposals carry the same one-to-three option set
and selected-label invariant as manual capture. It does not classify into
hidden types. `propose_merge` supports only same-kind Note or Decision merges.
Proposal application and undo are owned by `KnowledgeProposalApplier`; no AI
tool writes synced tables before user confirmation.

The system prompt must describe only Note and Decision. It must not ask the
user to select, review, or restore a retired object type.

### Explicit AI Rewrite

Note and Decision detail pages offer a user-triggered rewrite surface backed by
the active device-configured LLM profile through the native FRB runtime. Note
rewrites cover title and body; Decision rewrites cover question and rationale.
The user chooses clear, concise, or structured style, then reviews and may edit
the generated draft before adopting it into the editor. The normal Save action
is still required to persist or sync any change.

Knowledge Markdown fields use a shared source/preview editor in capture, Note
body, Decision rationale and actual outcome, and AI Rewrite. They support the
app's Markdown subset: headings, emphasis, inline and fenced code, lists and
task lists, blockquotes, rules, tables, and links. The rewrite sheet defaults
to rendered preview after generation and lets the user switch back to Markdown
source editing. Titles and questions remain plain text.

Rewrite source text is treated as untrusted data. The response must match the
kind-specific JSON contract, preserve empty fields, URLs, Markdown link
destinations, fenced code blocks, and numeric factual anchors, and is never
applied in the background. Web and devices without an active provider show the
feature as unavailable rather than using a backend or cloud fallback.

Key files:

- `features/knowledge/data/knowledge_rewrite_client.dart`
- `features/knowledge/ui/knowledge_rewrite_sheet.dart`

## Relations, Merge, And Deletion

Relations use stable typed endpoints whose kinds are only `note` or `decision`.
Note and Decision detail pages expose the same related-content section: users
can search live Knowledge rows, add a generic `related_to` link, remove a link,
and navigate to the related row. Both endpoints render the relation regardless
of which side originally created it.

The same section offers an explicit “discover related” action backed by the
local Memory semantic index. It excludes the current row and every already
linked endpoint, shows only hydrated live Note/Decision candidates, and writes
`related_to` only after the user links an individual suggestion. This is local
retrieval rather than an LLM request, so it does not create an AI transparency
trace.

The explicit “create Decision from this Note” action writes the new Decision
and a directed `informs` relation from the source Note in one local transaction,
including both Sync outbox rows. It never infers a Decision automatically: the
user must provide the question, candidate options, and selection before
creation.

When ExecutionOS is active, Decision detail can explicitly create or open one
source-linked Action through the domain-neutral Life action dispatcher. The
Action stores `knowledge` / `know:knowledge_decisions` / Decision id as its
source identity; app composition de-duplicates repeated creation and replaces
only a previously dropped Action. KnowledgeOS does not import ExecutionOS.

Deleting an entity also tombstones every live relation touching it.

Same-kind merges keep one survivor, union Note tags where applicable, soft
delete duplicates with `mergedIntoId`, and enqueue every changed row. Proposal
undo restores captured row snapshots with fresh Sync metadata.

## Product Evidence

Opt-in device-only aggregates record Decision creation, source-linked Action
creation, and review completion. Review evidence may include elapsed duration,
but never stores Note/Decision text, row ids, option labels, source URLs, or
relation endpoints. Metric failure is best-effort and cannot roll back or fail
the domain mutation that produced it.

## Boundaries

Included:

- Fast local capture.
- Direct Note and Decision editing.
- Source links, tags, review dates, revisit conditions, and outcomes.
- Search, semantic recall, deduplication, relations, and confirmed proposals.
- Explicit, previewed AI rewriting that still requires the normal Save action.
- Cross-domain recall through Memory Runtime.

Excluded:

- Rich block editor or WYSIWYG authoring.
- Wiki, graph visualization, forced backlinks, publishing, or collaboration.
- Automatic source rewriting or persistence of unconfirmed AI-generated knowledge.
- Background classification, contradiction detection, or review Agents.
- Recurring reminders and task execution.
- Legacy object import or compatibility behavior.

## Verification

For KnowledgeOS changes, prefer:

- `KnowledgeRepository` CRUD, relation cleanup, merge, and schema tests.
- Inbox focus and Library search widget tests.
- Decision review and source-linked Action workflow tests.
- Search and Memory indexer tests for Note and Decision only.
- Proposal apply/undo tests for capture and same-kind merge.
- Domain composition, route ownership, sync registry, and schema verification.
- The architecture lint gates listed in `lifeos-shell.md`.
