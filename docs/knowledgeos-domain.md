# KnowledgeOS Domain SSOT

KnowledgeOS is the LifeOS personal cognitive infrastructure domain. It is a user-opt-in, AI-native decision memory system. It is not a Notion, Obsidian, wiki, publishing, or collaboration product.

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
- Tabs: Inbox, Library, Review.
- Tools: `features/knowledge_ai_tools.dart`.
- Agents: `features/knowledge/agents/providers.dart`.
- Command palette: `features/knowledge/composition/knowledge_command_palette.dart`.
- Proposal composition: `features/knowledge/composition/knowledge_bootstrap.dart`.

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

Local-only:

- `knowledge_inbox_triage`

Local-only triage stores AI suggestions and dismissal state. It does not sync because it is derived workflow state.

## UI

| Tab | Purpose |
|---|---|
| Inbox | Fast capture with no synchronous LLM call |
| Library | Browse and edit knowledge objects; Decision is the primary object |
| Review | Due decisions, stale assumptions, contradictions, inbox AI suggestions, due routines |

Key files:

- `features/knowledge/ui/knowledge_inbox_page.dart`
- `features/knowledge/ui/knowledge_library_page.dart`
- `features/knowledge/ui/knowledge_review_page.dart`
- `features/knowledge/ui/knowledge_capture_sheet.dart`
- `features/knowledge/ui/knowledge_decision_detail_page.dart`
- `features/knowledge/ui/knowledge_object_detail_page.dart`

Capture rule: saving to Inbox must remain fast and offline. Do not call the LLM synchronously on the save path. AI classification, tags, links, and merge suggestions are asynchronous review work.

## AI Tools

Tool barrel: `features/knowledge_ai_tools.dart`.

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

Proposal tools:

- `propose_concept_link`
- `propose_merge`
- `propose_inbox_classification`
- `propose_inbox_tags`
- `propose_link_to_decision`
- `propose_routine`
- `propose_capture`

Rules:

- Proposal tools return `ProposalEnvelope`; they do not directly mutate synced KnowledgeOS tables.
- Inbox triage proposal tools may persist derived envelopes to `knowledge_inbox_triage`.
- Before creating new knowledge, prefer search or similarity tools to avoid duplicates.
- The model must not invent decisions, principles, assumptions, or outcomes. User confirmation is required.

## Proposal Application

KnowledgeOS owns the cross-domain proposal composite because Riverpod allows one override per provider.

Key files:

- `features/knowledge/composition/knowledge_bootstrap.dart`
- `features/knowledge/composition/knowledge_proposal_applier.dart`
- `features/knowledge/composition/knowledge_proposal_kinds.dart`
- `core/ai/composition/composite_proposal_applier.dart`

Behavior:

- `knowledge_*` proposal kinds route to `KnowledgeProposalApplier`.
- Finance proposal kinds fall back to the Finance applier.
- The proposal card registry is the union of Finance and Knowledge kinds.

Do not override `proposalApplierProvider` from another domain bundle without replacing the composite owner.

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
| ContradictionAgent | Detects conflicts against active principles, assumptions, and recent memories |
| InboxTriageAgent | Produces async proposals for captured notes |
| RoutineDueAgent | Surfaces routines due soon and sends review notifications |

Location:

- `features/knowledge/agents/`

Rules:

- Agents write memories, local triage state, proposals, and notifications as documented.
- Agents must not modify user-authored source content without a proposal and confirmation.
- Agents must skip cleanly when no LLM profile exists if the task requires LLM judgment.
- Agents must not call other agents.

## Inbox Triage Flow

```text
User saves Note
  -> KnowledgeRepository.upsertNote
  -> Memory/Event indexing
  -> InboxTriageAgent later reads untriaged notes
  -> propose classification, tags, and decision links
  -> proposals stored in knowledge_inbox_triage
  -> Review tab shows accept/dismiss cards
  -> accepted cards call repositories through KnowledgeProposalApplier
```

This preserves zero-latency capture and makes AI suggestions reviewable.

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
