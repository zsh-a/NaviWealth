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
independent owner-scoped repository query and refresh with foreground time,
so older decisions and newly due reviews remain visible. Inbox previews three reviews and expands the
complete due list lazily. Notes and reviews retain independent loading/error
states; refresh waits for both sections. Wide Inbox layouts place recent Notes
in the primary pane and due reviews in an independently scrolling supporting
pane; narrow or large-text layouts retain the review-first single list.
Library grows its live browse window
in batches of 50, with deterministic updated-time ordering and a load-more
control. Tag facets cover the full library; tag filtering precedes the browse
and lexical-search limits. The tag picker searches a lazy list of facets.
Ranked search displays up to 50 results and explains when to refine the
query.

Library preserves query (`q`), object kind (`scope`), and tag (`tag`) in the
route alongside `selected`. Reloading restores those filters; clearing them
keeps the selected object and unrelated route parameters. Applied filters and
the displayed search-result count use the shared filter summary. Each applied
filter can be removed independently; the tag picker opens on demand. Search
excerpts show the matching passage when the query occurs in the document.
Note and Decision deletion live in the detail header's More actions menu and
still require confirmation. Desktop row changes, detail close, route parameter
and query changes, and route exits confirm discarding unsaved edits and block
navigation during saves. When the Library becomes too narrow for two panes,
the selected detail fills the content area and retains its mounted editor;
widening restores both panes.
Keyboard users can focus search with `/`, select adjacent rows with `j` / `k`,
and submit edits with Ctrl/Cmd + Enter.

Key files:

- `features/knowledge/composition/knowledge_routes.dart`
- `features/knowledge/composition/knowledge_domain_shell.dart`
- `features/knowledge/ui/knowledge_inbox_page.dart`
- `features/knowledge/ui/knowledge_library_page.dart`
- `features/knowledge/ui/knowledge_note_detail_page.dart`
- `features/knowledge/ui/knowledge_decision_detail_page.dart`

The primary capture action opens a Note directly, without a type chooser.
Decision capture remains an explicit secondary action in Inbox and Library.
Normal capture and creation from a Note share one full-page guarded form; the
latter still atomically creates its source Relation. Note and Decision editors
use pinned Save/Cancel actions and a readable content width. Notes require a
title or body in both capture and editing. Existing tags complete the current
input prefix and selected tags can be removed directly. Commas and newlines
separate tags; spaces inside an existing tag are preserved.
Inbox due rows provide a direct review action. Due reviews lead with actual
outcome and common statuses; scheduling leads with the date. Revisit conditions
and the full status set remain under an explicit reveal control. Unchanged
reviews cannot submit. Continuing an overdue Decision requires a future review
date, with one-week and 30-day shortcuts. Review submission atomically reads the
current Decision, preserves unrelated text changes, and rejects changed review
fields or deleted sources.
AI rewrite is native-only: unconfigured profiles link directly to settings,
and Web hides the entry. Generated drafts support original-text comparison,
confirm dirty dismissal/style resets, and only enter the editor after explicit
acceptance; the user still saves the record normally.
Capture never saves an intermediate Note merely to classify or promote it later.
Notes use a guarded sheet with source and tags collapsed initially. Structured
Decision capture opens a full page with an unsaved-changes guard; switching
types is not presented as a tab inside an existing draft. A new Decision
requires a question, one to three unique candidate options, and an explicit
selection from those options. Each option may keep a short rationale; existing
rows with more options remain editable without adding further options. The
richer review fields can be edited on the detail page. Note capture writes
optional source URL and tags in the same canonical row, matching the provenance
retained by system-share capture. Source URLs are normalized to HTTP(S)
document identity, render as an external-link card on Note detail, and receive
a non-blocking inline warning when quick capture finds an existing live Note
with the same source. Viewing that existing Note pushes its normal detail over
the capture sheet; returning retains the capture draft.

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
Tagged search applies its tag intersection to canonical candidates before
paging and ranking, so a matching old Note cannot disappear behind unrelated
top-ranked or recent rows. Semantic search and similarity candidates are
hydrated in owner-scoped batches and exclude tombstones. Lexical ranking reuses
query tokens and only cleans Markdown excerpts for consumed results.

The lexical path still scans the eligible canonical rows. Measure its cost with
the opt-in 1,000/5,000/10,000-Note benchmark before introducing another index:

```bash
cd apps/mobile
rtk flutter test test/benchmarks/knowledge_search_benchmark.dart --reporter expanded
```

The benchmark warms Drift, reports five-sample p50/p95 for tagged and untagged
search, and checks result integrity. Host debug timings do not establish mobile
or Web performance budgets.

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
Manual linking commits before closing its guarded picker; a failed write keeps
the chosen target and offers retry. Removal locks repeated submission and
offers the shared session Undo. Link creation and Undo validate both live,
owner-scoped endpoints; Undo also checks that its deletion receipt is current.

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
only a previously dropped Action after explicit replacement confirmation.
Done Actions remain linked. Status changes and Undo refresh the association;
opening the follow-up goes to its concrete registered object route.
KnowledgeOS does not import ExecutionOS.

Note and Decision edits use the shared commit-first submission protocol in
place: pending saves lock editing and navigation, failed writes keep the draft
and persistent inline feedback, and successful saves refresh the read view.
Decision review commits while its guarded sheet is still open and closes only
after success; failed review drafts can be retried without reopening the sheet.
Detail readers watch the current owner-scoped row, including tombstones for
draft preservation. Pristine editors follow updates; dirty editors retain their
input and show a change/deletion notice. Editor saves atomically check the
captured HLC and live source through `KnowledgeEditService`. Loading the latest
version confirms discarding a draft; a deleted source cannot be saved back into
existence. This is local edit protection over the existing Sync v3 protocol.

Note/Decision capture and detail editing also retain owner-scoped device-local
input snapshots through the shared form recovery store. Reopening offers restore
or discard, including unfinished alternatives and selection. Restored edits keep
their original HLC so recovery cannot overwrite a newer source revision. Saves
and explicit discards clear snapshots; domain reset and retention follow the
shared contract in [LifeOS Shell](../architecture/lifeos-shell.md).

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
Unchanged submissions and date-only scheduling do not count as completed
reviews; outcome/status changes provide the review evidence.

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
