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

### BCR Knowledge Sources

Library's **BCR sources** action opens `/knowledge/library/bcr` inside the
existing Library branch. Connect the same private GitHub repository and branch
used by BCR; no file export/import is needed. A blank branch resolves the
repository's default branch on connection, then persists that explicit branch.
The connection sheet also supplies a display name and GitHub access token;
there is no BCR page URL field. Navi needs only the repository's Contents read
permission.

BCR owns the source documents. These snapshots are read-only projections, not
additional KnowledgeOS business entities or synced `knowledge_notes` rows.
The source id is a SHA-256 of normalized GitHub owner/repository and the
case-sensitive branch, independently of display names, note titles, contents
and reading-page URL. Notes keep BCR's stable ids. New connections do not need
a page URL. Existing HTTP(S) page URLs remain as metadata for opening the source
in BCR and survive reconnection. Connecting from an earlier file-import cache
adopts that page's cache atomically, without changing saved citations. Missing
page URLs are stored as empty strings in the existing local cache/connection
columns and exposed as absent links to readers and tools.

`KnowledgeSourceConnections` keeps device-local connection metadata, credential
ids, revision, last accepted Git HEAD and last check time. Tokens stay outside
Drift, ordinary preferences, logs, exports and Navi Sync: native hosts use
owner-scoped SecureKeyStore documents; Web uses session memory and requests a
token again after reopening. Domain reset fences pending work in SQLite before
attempting credential cleanup through the DomainPack resource-cleanup seam.

`KnowledgeSourceCache` stores owner-scoped text snapshots in the existing
database. `KnowledgeSourceImportLeases` is the existing storage name for pending
connection/sync tokens, acquired **before** HTTP. Commit rechecks the owner,
connection revision and lease, and updates the complete cache and HEAD in one
transaction. Reset/disconnect/changed credentials or cancelled sessions cannot
be undone by late responses, including a first connection without prior data.
Failed network, validation and storage operations keep the prior snapshot.

Cache cleanup removes cached text and leases but keeps connection metadata for
automatic reconstruction. Domain reset removes connections too. Cached text
can transfer with the owner's local data; credential-bound connections and
pending leases invalidate on owner transfer and require reconnection. All
three tables remain outside Navi Sync and backup. Readers lose access when a
source is disconnected, reset, replaced or owned by another active user.

The Knowledge DomainPack mounts a foreground-only sync driver when the domain
is enabled: check on startup/resume and every 30 seconds, pause on background,
and coalesce in-flight operations. **Sync now** uses the same service. Network
errors retry with bounded exponential backoff; GitHub Retry-After/reset waits
take precedence, including manual checks. Permission or missing-token failures
pause automatic retry until the connection is repaired. Clearing the cache
retains the ability to rebuild it even if the stored HEAD has not changed.

Search covers all cached notes through bounded lexical retrieval on native and
Web; it does not depend on the recent-Note Memory subscription or a model.
`search_bcr_notes` and `read_bcr_note` expose the same read-only sources to the
native assistant. Responses identify their source, document, update/cache
times and snapshot fingerprint. Reading is paginated and requires the current
fingerprint; cached documents must not be presented as a live BCR query.

Decision capture can start from a source reader. Existing Decision editors can
pick a source and explicitly insert its previewed excerpt into the rationale
draft. The ordinary Save action persists it. Standard Markdown retains the
source id, original note id, page URL when available, original update time, bounded excerpt
and `sha256:` snapshot fingerprint. Updating/removing the cache never rewrites
saved decision evidence. This reuses existing rationale editing, recovery,
merge, proposal Undo, Sync and encrypted backup behavior without introducing a
parallel Decision source field. Without a page URL, the citation keeps a plain
title and all other evidence, and the reader omits the external source link.

The snapshot fingerprint covers the fixed-order note fields (id, title,
optional path, body, tags, collection id, creation/update epoch milliseconds
and citations), using UTF-8 JSON with recursively sorted citation-map keys.
It is Navi's SHA-256 fingerprint, **not** BCR's BLAKE3 revision or Git HEAD.
Quotes and titles remain user-editable as part of the rationale.

GitHub traffic is GET-only to api.github.com, with redirects disabled and a
bounded response stream. Each cycle verifies the repository is private and
reads an immutable commit/tree. Same-HEAD checks reuse a complete local cache;
otherwise managed files are read with bounded concurrency and verified using
their Git SHA-1 blob identities. Verified text blobs use a bounded in-memory
LRU so changed HEADs and rate-limit retries can resume without redownloading
unchanged content. No remote commit, push or three-way merge is needed for this
read-only consumer; BCR retains ownership of document edits and conflict policy.

Limits: 12 MiB per JSON response, 16 MiB managed text, 2 MiB per text file,
5,000 notes per source, and 32 MiB total persisted cached content per owner.
Truncated trees, unsupported files/symlinks, size or SHA mismatches, invalid
UTF-8, YAML aliases/complex keys or excessive nesting, inconsistent ids and
missing provenance stop the cycle before replacing the cache. Text parsing
supports BCR manifest versions 1–4 and is shared with the format fixtures.
The YAML event preflight uses pinned `yaml` 3.1.4; upgrades must retain its
safety regressions. GitHub endpoint behavior follows the
[Git trees](https://docs.github.com/en/rest/git/trees),
[Git blobs](https://docs.github.com/en/rest/git/blobs) and
[rate-limit](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
contracts.

Attachment metadata and Git tree sizes are checked, but binary attachments
are neither downloaded, BLAKE3-verified nor cached. Offline support is
for note text; view attachments, relative links and backlinks separately in BCR.
The connection synchronizes remote BCR content into local read-only snapshots;
it does not add a second writer for BCR documents.

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
- `search_bcr_notes`
- `read_bcr_note`
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
