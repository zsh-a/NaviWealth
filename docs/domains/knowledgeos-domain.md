# KnowledgeOS Domain SSOT

KnowledgeOS is the LifeOS personal cognitive infrastructure domain. It is a user-opt-in, AI-native decision memory system. It is not a Notion, Obsidian, wiki, publishing, or collaboration product.

## Document Contract

Owns KnowledgeOS objects, review behavior, proposals, Memory indexing, tools,
and Agents. It does not own shared Memory Runtime or AI wire semantics.
`knowledge_pack.dart`, Knowledge repositories, and focused Knowledge tests are
authoritative for the current implementation inventory.

## Scope

Included:

- Inbox capture for high-signal notes.
- Library of Notes, Concepts, Principles, Assumptions, Decisions, Experiments, and Routines.
- Decision log with assumptions, principles, rationale, expected outcome, review date, and actual outcome.
- Review workflow for due decisions, stale assumptions, contradictions, inbox triage, and due routines.
- Cross-domain recall through Memory Runtime.
- AI tools that read, search, and propose changes.
- Agents that surface review work and contradictions.

Excluded:

- Rich block editor or WYSIWYG document authoring.
- Collaboration, comments, sharing, publishing, or blog mode.
- Automatic AI-generated knowledge as source of truth.
- Low-signal diary capture.
- Graph database or graph visualization.
- Forced backlinks.
- Notion, Obsidian, Logseq import in the MVP.
- OCR, video transcription, crawlers, RSS, or read-later queues.

Core rule: KnowledgeOS stores information that affects long-term decisions or cognitive evolution. Ordinary life events belong in Memory Runtime events, not in KnowledgeOS objects.

## Shell Registration

KnowledgeOS is registered through `kKnowledgePack` in `app/domain_packs.dart`.

Contributions:

- Scope: `DomainScope.knowledge`.
- Shell: `features/knowledge/composition/knowledge_domain_shell.dart`.
- Routes: `features/knowledge/composition/knowledge_routes.dart`.
- Primary tabs: Inbox, Library. Review is a contextual destination reached from
  due signals and the command palette rather than a permanent shell tab.
- Tools: `features/knowledge/knowledge_ai_tools.dart`.
- Agents: `features/knowledge/agents/providers.dart`.
- Command palette: `features/knowledge/composition/knowledge_command_palette.dart`.
- Proposal kinds: `features/knowledge/composition/knowledge_proposal_kinds.dart`.
- Proposal applier: `features/knowledge/composition/knowledge_proposal_applier.dart`.

KnowledgeOS is active only when the user enables it in Settings.

## Domain Objects

| Object | Purpose | Storage |
|---|---|---|
| Note | Raw capture and source material | `knowledge_notes` |
| Concept | Named concept with aliases and summary | `knowledge_concepts` |
| Principle | Long-lived worldview or operating rule | `knowledge_principles` |
| Assumption | Falsifiable belief used by decisions | `knowledge_assumptions` |
| Decision | Chosen option, rationale, assumptions, outcome, review lifecycle | `knowledge_decisions` |
| Experiment | Hypothesis, method, metrics, result | `knowledge_experiments` |
| Routine | Recurring personal reminder with next due date | `knowledge_routines` |
| Relation | Typed, queryable edge between knowledge objects | `knowledge_relations` |

Domain models:

- `features/knowledge/domain/knowledge_models.dart`

Repositories:

- `features/knowledge/data/knowledge_repository.dart`
- `features/knowledge/data/inbox_triage_repository.dart`

## Persistence

Tables:

- `core/persistence/knowledge_tables.dart`
- `core/persistence/local_only_tables.dart`

Synced tables use `SyncableTable` and the `know:` row-family prefix:

- `know:knowledge_notes`
- `know:knowledge_principles`
- `know:knowledge_assumptions`
- `know:knowledge_decisions`
- `know:knowledge_concepts`
- `know:knowledge_experiments`
- `know:knowledge_routines`
- `know:knowledge_relations`

Local-only:

- `knowledge_inbox_triage`
- `agent_findings` rows with `domain = knowledge`

Local-only triage stores AI suggestions, the source-note fingerprint, and
dismissal state. A material Note edit changes the fingerprint and makes the
Note eligible for triage again; dismissed suggestions are preserved only while
the source fingerprint is unchanged. It does not sync because it is derived
workflow state.

## UI

| Tab | Purpose |
|---|---|
| Inbox | Fast capture with no synchronous LLM call |
| Library | Browse, search, and edit the complete knowledge collection; Decision is the primary object |
| Review (contextual) | Due decisions, stale assumptions, contradictions, inbox AI suggestions, and existing due routines |

Key files:

- `features/knowledge/ui/knowledge_inbox_page.dart`
- `features/knowledge/ui/knowledge_library_page.dart`
- `features/knowledge/ui/knowledge_review_page.dart`
- `features/knowledge/ui/knowledge_capture_sheet.dart`
- `features/knowledge/ui/knowledge_decision_detail_page.dart`
- `features/knowledge/ui/knowledge_object_detail_page.dart`

Capture rule: saving to Inbox must remain fast and offline. Inbox capture always
creates a Note from title and body; it does not expose the object taxonomy or
call the LLM synchronously. AI classification, tags, links, and merge
suggestions are asynchronous review work. Users create an explicitly structured
object from Library only when they already know the intended type.

Library exposes Notes, Decisions, and Assumptions in its adaptive picker and
creation sheet. Existing advanced objects remain searchable in All, but
Principles, Concepts, Experiments, and Routines are no longer creation choices
in the primary UI. Library filtering has one contextual dimension: All filters
by object type, while a typed collection filters by its status. Tags, scope,
and dates remain searchable content rather than separate filter configuration.

Decision detail exposes one source-preserving follow-up action when ExecutionOS
is active. Creation uses the domain-neutral Life action dispatcher with
`know:knowledge_decisions` plus the decision id, reuses an existing linked
action, and opens that action on later visits instead of creating duplicates.
Concept relationships render as accessible links, never as a graph
visualization. Review is a signal-first work queue: suggestions, due routines,
due decisions, stale assumptions, and agent findings appear without a duplicate
dashboard or manual agent-control surface.

Repository writes debounce an event-triggered agent run. New or edited Notes
schedule Inbox Triage and contradiction detection; changes to Decisions,
Principles, and Assumptions schedule contradiction detection. Agent run records
identify these runs with the `event` trigger.

## AI Tools

Tool barrel: `features/knowledge/knowledge_ai_tools.dart`.

Read tools:

- `recall_decision`
- `list_open_assumptions`
- `list_due_reviews`
- `list_due_routines`
- `search_notes`
- `search_knowledge`
- `find_similar_knowledge`
- `review_knowledge_health`
- `summarize_topic_evolution`

Write/proposal tools:

- `propose_concept_link`
- `propose_merge`
- `queue_inbox_classification`
- `queue_inbox_tags`
- `queue_link_to_decision`
- `propose_routine`
- `propose_capture`

Rules:

- `propose_*` tools return `ProposalEnvelope`; they do not directly mutate synced KnowledgeOS tables.
- `queue_*` inbox triage tools persist derived envelopes to `knowledge_inbox_triage` for the Review tab; they are not chat proposal-card apply kinds.
- Before creating new knowledge, prefer search or similarity tools to avoid duplicates.
- The model must not invent decisions, principles, assumptions, or outcomes. User confirmation is required.
- `review_knowledge_health` uses the user-configured stale-assumption threshold
  shared by Review agents/UI. Review cadence and the stale threshold are
  device-local Knowledge Settings preferences. Orphan Notes must be older than 24 hours and have neither
  tags, project membership, nor incoming/outgoing Knowledge relations.
- Topic evolution expands the query through matched Concept aliases, paginates
  Notes and Decisions, and reports truncation metadata instead of silently
  treating a bounded page as the full history.

## Proposal Application

KnowledgeOS owns the cross-domain proposal composite because Riverpod allows one override per provider.

Key files:

- `app/domain_composition.dart`
- `app/domain_packs.dart`
- `features/knowledge/composition/knowledge_proposal_applier.dart`
- `features/knowledge/composition/knowledge_proposal_kinds.dart`
- `core/ai/composition/composite_proposal_applier.dart`

Behavior:

- `CompositeProposalApplier` routes by explicit domain-owned proposal kinds and applied table prefixes.
- Knowledge proposal kinds route to `KnowledgeProposalApplier`.
- Finance proposal kinds route to the Finance applier.
- Unknown proposal kinds or applied tables fail fast.
- Proposal card metadata and apply routes are contributed through `DomainPack.proposalKinds` and `DomainPack.proposalApplierRouteBuilder`, then aggregated from active domain packs.

Do not override `proposalApplierProvider` from a domain bundle. Do not manually union proposal card metadata in bootstrap code; add proposal metadata and applier routes to the owning domain pack.

## Memory Integration

Indexers:

- `features/knowledge/data/knowledge_decision_memory_indexer.dart`
- `features/knowledge/data/knowledge_object_memory_indexers.dart`

Memory sources:

- `know:notes`
- `know:principles`
- `know:assumptions`
- `know:concepts`
- `know:experiments`
- `know:decisions`
- `know:routines`

Rules:

- Knowledge objects remain source-of-truth in Drift tables.
- Memory mirrors make cross-domain recall work without a Knowledge-specific retrieval engine.
- Search tools iterate concrete `know:*` sources because Memory Runtime source filtering is exact-match.
- Memory Runtime stays in `core/ai/local/memory/` and does not import KnowledgeOS.

## Agents

Current agents:

| Agent | Purpose |
|---|---|
| ReviewAgent | Surfaces decisions due for review and stale assumptions |
| AssumptionAgent | Finds assumptions that need verification |
| ContradictionAgent | Detects structural and semantic conflicts against active principles, assumptions, Notes, and all active Decisions |
| InboxTriageAgent | Produces async proposals for new or materially edited captured notes |

Location:

- `features/knowledge/agents/`

Rules:

- Agents write memories, local triage state, proposals, and notifications as documented.
- Agents must not modify user-authored source content without a proposal and confirmation.
- Agents must skip cleanly when no LLM profile exists if the task requires LLM judgment.
- Agents must not call other agents.
- Durable findings use stable subject/reference identities and reconcile
  `open -> resolved`; dismiss and snooze suppress unchanged evidence, while
  materially changed evidence reopens the finding.

## Inbox Triage Flow

```text
User saves Note
  -> KnowledgeRepository.upsertNote
  -> Memory/Event indexing
  -> InboxTriageAgent later reads untriaged notes
  -> propose classification, tags, and decision links
  -> proposals stored in knowledge_inbox_triage
  -> Review tab shows accept/dismiss cards
  -> accepted classification atomically creates the typed object
     and records promoted_to_kind / promoted_to_id on the source Note
  -> promoted source Notes remain provenance but leave normal Note queries
```

Classification is a domain transition, not a `kind:*` tag. Typed Library
segments must always be backed by their corresponding `knowledge_*` table.
Deterministic promotion ids make repeated acceptance idempotent. This preserves
zero-latency capture and makes AI suggestions reviewable.

Decision links are persisted as typed `knowledge_relations` rows, never as
synthetic tags. When a Note is promoted, its outgoing relations move to the
typed object in the same transaction; proposal undo restores both the source
Note and its original relation endpoints.

Promotion is structurally strict: a Decision needs at least two options, an
Assumption needs an explicit confidence, and an Experiment needs both a method
and one or more metrics. Capture classifiers and Inbox proposals must carry
these fields through to the confirmed promotion; incomplete suggestions stay
as Notes instead of creating hollow first-class objects.

## Decision Lifecycle

Decision is the primary KnowledgeOS object. It should preserve:

- Question.
- Options.
- Selected option.
- Rationale.
- Linked principles.
- Linked assumptions.
- Expected outcome.
- Review date.
- Actual outcome.
- Status.
- Optional context snapshot.

Status changes and lifecycle editing live in the KnowledgeOS UI and repository. Agents can recommend review work but must not silently rewrite a decision.

## Tests To Prefer

When touching KnowledgeOS, add or run targeted tests for:

- `KnowledgeRepository` CRUD, status filters, merges, due reviews, due routines.
- Inbox triage repository persistence and dismissal behavior.
- AI tool JSON outputs and proposal envelopes.
- `KnowledgeProposalApplier`.
- Memory indexers for each object type.
- Agents and skip/fallback paths.
- Route shell, opt-in, and command palette behavior.
