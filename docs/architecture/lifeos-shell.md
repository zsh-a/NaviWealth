# LifeOS Shell SSOT

This document describes the current cross-domain shell. It is written for implementation agents: where to plug in, which files own each seam, and which boundaries must not move.

## Document Contract

Owns `DomainPack` composition, opt-in behavior, shell routing, and the
cross-domain integration seams. It does not own domain business rules or exact
AI/Sync wire contracts. `domain_pack.dart`, `domain_packs.dart`, and their
composition tests are authoritative for the current inventory.

## Scope

The shell owns cross-domain infrastructure:

- Multi-domain IA and routing.
- Domain opt-in.
- AI tool, prompt, proposal, and agent composition.
- Memory Runtime and indexer bootstrap.
- Sync v3 row-family namespace and per-domain reset generations.
- Shared persistence adapter.
- Encrypted local backup and restore.
- Background jobs and notifications.

Domain business behavior belongs in the domain SSOT:

- FinanceOS: `../domains/financeos-domain.md`.
- HealthOS: `../domains/healthos-domain.md`.
- KnowledgeOS: `../domains/knowledgeos-domain.md`.
- ExecutionOS: `../domains/executionos-domain.md`.

## Current Shape

```text
app/
  bootstrap.dart                 Provider overrides and shell composition
  domain_packs.dart              Production domain inventory
  routing/router_builder.dart    Outer dock shell plus domain routes
  shell/app_dock_shell.dart      Multi-domain chrome
  domain_bootstrap.dart          Domain indexer/background startup

core/
  lifeos/domain_pack.dart        Domain registration contract
  shell/domain_shell.dart        Domain shell spec and tab ownership
  auth/domain_scope.dart         Domain opt-in enum and wire values
  backup/backup_table_registry.dart  Encrypted backup table metadata
  sync/sync_table_registry.dart  Row-family prefixes and sync table metadata
  ai/composition/                Cross-domain AI seams
  ai/agents/                     Agent framework
  ai/local/memory/               Memory Runtime
  persistence/                   Drift adapter and shared tables

features/<domain>/
  composition/                   Domain shell, routes, command palette, overrides
  ai_tools/                      Domain-owned device tools
  agents/                        Domain-owned agents
  data/                          Repositories, platform adapters, indexers
  domain/                        Domain entities
  ui/                            Domain screens
```

## Domain Inventory

`apps/mobile/lib/app/domain_packs.dart` is the source of truth for domains in this build.

| Domain | Scope | Shell tabs | Tools | Agents |
|---|---|---|---|---|
| FinanceOS | `finance` | Today, Activity, Wealth, Plan | `kFinanceDeviceTools` | Weekly Wealth Review, Cashflow Anomaly Review, FIRE Plan Drift Monitor, Options Income Risk Review |
| HealthOS | `health` | Today, Trends | `kHealthDeviceTools` | Morning Briefing, Recovery Alert, Weekly Summary |
| KnowledgeOS | `knowledge` | Inbox, Library | `kKnowledgeDeviceTools` | Review, Assumption, Contradiction, Inbox Triage |
| ExecutionOS | `execution` | Today, Plans | `kExecutionDeviceTools` | Review, Due Action |

Finance is always active. Health, Knowledge, and Execution are enabled through
`domainOptInsProvider`.

## Adding Or Changing A Domain

Use this path for any domain-level change:

1. Add or update domain code under `features/<domain>/`.
2. Export tools through `features/<domain>/<domain>_ai_tools.dart`.
3. Add or update shell spec and route builder under `features/<domain>/composition/`.
4. Add agents under `features/<domain>/agents/` and expose a builder provider if needed.
5. Add command palette entries under `features/<domain>/composition/`.
6. Register the domain once in `app/domain_packs.dart`.
7. Add domain memory/background bootstraps through the owning `DomainPack` only when they have a real source stream or startup task.
8. Register any data-management, settings, notifications, share handlers, Life
   signals, or source-route resolution on the same pack rather than in shell
   conditionals.
9. Add tests for opt-in behavior, route ownership, tool registration, and domain-specific repositories.

Do not add custom opt-in checks to every consumer. Consumers should derive from `activeDomainPacksProvider` or from a domain-owned provider that already observes the opt-in.

## Multi-Domain IA

The router uses a two-layer shell:

- Outer shell: `AppDockShell`, global lifecycle, route context, system-back behavior, and domain dock/switcher.
- Inner shell: one `StatefulShellRoute` per active domain route builder.

Important files:

- `app/routing/router_builder.dart`
- `app/shell/app_dock_shell.dart`
- `core/shell/domain_shell.dart`
- `features/finance/composition/finance_routes.dart`
- `features/health/composition/health_routes.dart`
- `features/knowledge/composition/knowledge_routes.dart`

Rules:

- Settings, login, onboarding, AI history, and global configuration routes stay outside the domain dock shell.
- A domain owns its tab paths through `DomainPack.tabPaths`.
- Additional route prefixes that belong to a domain but are not tabs use `DomainPack.additionalPathPrefixes`.
- The dock is visible when at least two domain shell specs are active.

## Identity And Opt-In

Location:

- `core/auth/domain_scope.dart`
- `core/auth/providers.dart`
- `features/settings/ui/domains_settings_page.dart`

Rules:

- `DomainScope.finance` is always present.
- Optional domains default to off.
- Tool lists, prompt blocks, shell specs, agents, and command entries are derived from active domain packs.
- Backend auth may use the domain claim to filter sync pulls; client code must still enforce local opt-in for UI and domain jobs.

## AI Composition

Core contracts:

- `core/ai/contracts/`
- `core/ai/runtime/`
- `core/ai/composition/`

Aggregation:

- Tools: `deviceToolsProvider`.
- Prompt blocks: `systemPromptBlocksProvider`.
- Agents: `agentRegistryProvider`.
- Domain inventory: `activeDomainPacksProvider`.

Domain exports:

- Finance: `features/finance/finance_ai_tools.dart`.
- Health: `features/health/health_ai_tools.dart`.
- Knowledge: `features/knowledge/knowledge_ai_tools.dart`.
- Execution: `features/execution/execution_ai_tools.dart`.

Rules:

- Domain tools live in `features/<domain>/ai_tools/`.
- Shell tools that are genuinely domain-neutral may remain in `core/ai/runtime/device/tools/`.
- Read tools can return direct data.
- Write tools either return `ProposalEnvelope` or require explicit confirmation. Narrow local writes must be documented in the domain SSOT.
- System prompts are active-domain scoped. The model must not receive instructions for inactive domain tools.

## Proposal Application

Proposal application is a cross-domain seam under `core/ai/composition/`.

Current composition:

- Each domain contributes proposal card metadata through `DomainPack.proposalKinds`.
- Each domain contributes proposal apply/undo routing through `DomainPack.proposalApplierRouteBuilder`.
- `proposalKindRegistryProvider` and `proposalApplierProvider` are derived from active domain packs by `app/domain_composition.dart`.
- Finance exposes `financeProposalApplierProvider`.
- `CompositeProposalApplier` routes by explicit domain-owned proposal kinds and applied table prefixes. Unknown kinds or tables fail fast.

Rule: proposal metadata and proposal applier routes belong in the owning domain's `DomainPack`, not in bootstrap-time manual unions or domain-specific composite overrides.

## Cross-Domain Review

KnowledgeOS and ExecutionOS contribute their contextual review destinations
through `DomainPack.reviewRoutePath`. The Life hub renders one review entry and
offers only active domains with a real destination. Review data and pages stay
domain-owned; the Life surface composes routes and signal counts only.

## Agent Runtime

Core framework:

- `core/ai/agents/agent.dart`
- `core/ai/agents/agent_schedule.dart`
- `core/ai/agents/agent_registry.dart`
- `core/ai/agents/agent_runner.dart`

Current domain agents:

- Health: Morning Briefing, Recovery Alert, Weekly Summary.
- Knowledge: Review, Assumption, Contradiction, Inbox Triage.
- Execution: Review.

Rules:

- Agents are named use cases, not a general automation platform.
- Agents read through repositories, tools, or Memory Runtime and write events/memories/proposals/notifications according to domain SSOTs.
- Cross-run diagnostics are stored as local-only stable findings. Agents
  reconcile open findings by stable identity; disappeared signals resolve, and
  ignored/snoozed findings reopen only when evidence changes or snooze expires.
- Agents must not call other agents.
- Background isolate callbacks remain lightweight. Heavy work runs in the foreground path where Riverpod, memory, LLM, and notification services are available.

## Memory Runtime

Location:

- `core/ai/local/memory/`
- `core/ai/local/embedding/`
- `app/domain_bootstrap.dart`

Core types:

- `EventRecord`
- `MemoryRecord`
- `MemoryRuntime`
- `MemoryStore`
- `EventStore`
- `ContextBuilder`
- `Embedder`

Indexers:

- Options trade journal to trade events and episodic memories.
- Health metrics to health events and selected sleep episodic memories.
- Knowledge objects and decisions to `know:*` memories.
- Execution actions, commitments, projects, and progress to `execution:*`
  memories/events.

Rules:

- `core/ai/local/memory/` does not import domains.
- Domain indexers live in domain `data/`.
- Domain indexers are contributed through `DomainPack.memoryBootstrapBuilder`;
  the app bootstrap only loops active packs.
- Every domain also declares `DomainPack.memorySourcePrefixes`. Interactive
  Chat unions only active packs' prefixes and applies that hard allow-list to
  both memory and recent-event retrieval; rows from disabled domains remain
  local but cannot enter the AI context.
- Memory embeddings are derived local data and can be rebuilt.
- `build_context` is the preferred LLM retrieval tool for contextual answers; `query_memory` remains a flat fallback.
- App-level retrieval emits untrusted `ContextBlock(kind=memory)` records.
  Rust validates, hashes, budgets, snapshots, and renders them; memory text is
  evidence and never instruction authority.
- Long-chat transcript compaction is separate from Memory Runtime. The chat
  feature stores a source-fingerprinted structured checkpoint locally and
  emits it as untrusted `ContextBlock(kind=compaction_summary)`. It never
  syncs or becomes durable user memory; editing/deleting summarized source
  turns invalidates it.
- Models stage durable memory changes through `propose_memory`; they never
  write `memories` directly. Local-only `memory_candidates` become Memory only
  after explicit user approval through the proposal seam.
- Candidate apply supports create, supersede, forget, reject, retry, and undo.
  Owner and target-memory isolation are revalidated at apply time. Confirmed
  AI memory uses provenance `user_confirmed_ai`; terminal candidates are
  pruned per owner after 90 days.

## Human Interaction Contract

The shell uses the provider-neutral `InteractionEnvelope` /
`InteractionResponse` pair for `ask_user`, proposal approval, and typed
confirmation. Domain payloads remain opaque; the shell/runtime own interaction
identity, lifecycle, confirmation mode, expiry, subject, response schema, and
resume routing.

For ChatTurn, pending tools and a pending interaction are mutually exclusive.
`ask_user` is first dispatched as a device tool, then its standard interaction
is suspended into a local `requires_interaction` snapshot without another
model request. A user response resumes the original turn id and becomes an
`interaction_result` block. Missing or mismatched snapshots fail closed.
Proposal approval uses the same response contract but resumes through the
proposal-apply route. Legacy decision/apply fields remain during the
compatibility migration.

## Data Management

The Settings → Data & Storage surface is composed through the same domain
registry seam:

- Domain-neutral contracts and inspection/maintenance orchestration live in
  `core/data_management/`.
- Each domain owns a `features/<domain>/data_management/` spec and registers it
  through `DomainPack.dataManagementSpec`.
- The page reads the complete `domainPackRegistryProvider`, not only active
  packs. Data from a disabled optional domain must remain visible and
  maintainable.
- Synced source tables are derived from `sync_table_registry.dart`. Explicit
  reset actions can erase one OS on the current device or permanently across
  all devices through the Sync v3 generation protocol.
- Only tables explicitly registered as local, re-creatable caches may be
  hard-deleted. Cache cleanup never writes tombstones or the sync outbox.
- Per-user cache tables are filtered by `owner_user_id`; device-global derived
  caches may be cleared for the whole device.
- Per-OS encrypted archives filter the shared backup inventory by row-family
  prefix and can restore that OS without replacing unrelated domains.
- AI chat, audit traces, memories, event projections, and agent history are
  counted and cleaned as a separate cross-domain local resource. Source data,
  credentials, and preferences are not included in that action.
- Daily retention maintenance is opt-out, recorded in
  `data_maintenance_runs`, and can also be run manually. Database compaction is
  manual because SQLite `VACUUM` can be comparatively expensive.

Disabling a domain does not delete its data. Cache cleanup also does not imply
server erasure. Permanent erasure increments the domain generation before
physically deleting its server rows; stale offline writes are rejected and the
client hard-resets that domain when it observes a newer generation.

## Embedding Runtime

Current native runtime:

- Rust crate: `apps/mobile/native/lifeos_native/`.
- Dart adapter: `core/ai/local/embedding/rust_gemma_embedder.dart`.
- Generated bindings: `apps/mobile/lib/src/rust/`.
- Model installer: `core/ai/local/embedding/model_*`.
- Native build: the `rust_builder` Flutter plugin invokes cargokit from the
  normal `flutter run` and `flutter build` commands.

Behavior:

- Bootstrap attempts to load EmbeddingGemma when model, ORT, and library paths are available.
- Failures fall back to `StubEmbedder`.
- Fingerprint changes drop stale vectors and allow reindexing.
- Web does not load the native embedder.

## Speech Input Runtime

Speech recognition is a domain-neutral input capability, not an AI tool and
not a source of automatic writes.

Location:

- Contract and platform selection: `core/speech/`.
- Native engine: the `sherpa_onnx` Dart FFI plugin backed by C++ and ONNX Runtime.
- Reusable draft control: `design_system/widgets/speech_input_button.dart`.
- Model bundle: the shared AI model installer under `core/ai/local/embedding/model_*`.

Behavior:

- Native mobile/desktop uses the opt-in INT8 Mandarin streaming Zipformer.
- Managed recognition owns one application-wide microphone session. Concurrent
  starts fail deterministically with `session_busy`, and every completion,
  cancellation, startup failure, or stream error releases the session lease.
- A recognition session is bounded to five minutes. Reaching the limit emits
  the final transcript available from the native engine and closes the session.
- Moving the app out of the foreground finalizes active dictation. Editing the
  draft while recognition is starting or active cancels dictation, so a late
  partial result cannot overwrite user-authored text.
- Microphone PCM is consumed in memory and is neither persisted nor synced.
- Partial/final transcripts only update an editable text controller. Sending,
  saving, tool invocation, and proposal application remain explicit user actions.
- Speech diagnostics retain only counters, durations, and stable error enums.
  Microphone bytes and transcript text are never passed to diagnostics or logs.
- AI Chat and Knowledge Inbox are the first callers; domains do not own or
  import the recognizer implementation.
- Web uses the unsupported stub and keeps microphone access disabled.
- Android packages the ONNX Runtime supplied by `sherpa_onnx`; the Rust
  embedder dynamically reuses that single process-wide library.
- Model installation prefers individually checksummed files and falls back to
  the checksummed official sherpa-onnx GitHub Release archive when the primary
  host is unreachable. Archive extraction runs off the UI isolate and retains
  only the four manifest-declared runtime files.
- `apps/mobile/tool/run-asr-native-smoke.sh` downloads checksummed, pinned model
  and WAV fixtures and invokes `asr_native_smoke.dart` against the production
  recognizer configuration. `.github/workflows/asr-native-smoke.yml` runs the
  exact-transcript native regression for relevant changes, weekly, and on
  manual dispatch.

## Sync V3

Location:

- Client: `core/sync/`.
- Backend: `apps/backend/src/sync/`.
- Prefix/table registry: `core/sync/sync_table_registry.dart`.

Row-family prefixes:

| Domain | Prefix |
|---|---|
| FinanceOS | `fin:` |
| HealthOS | `health:` |
| KnowledgeOS | `know:` |
| ExecutionOS | `exec:` |

Rules:

- Local table names are unprefixed.
- Prefixing and stripping happen at the sync boundary.
- Sync table primary keys, owner-scope flags, and backfill eligibility are
  registered in one place: `SyncTableRegistration`.
- Backend store is generic and does not inspect domain payloads.
- Local-only tables and derived data do not sync.

## Persistence

Location:

- `core/persistence/app_database.dart`
- `core/persistence/tables.dart`
- `core/persistence/health_tables.dart`
- `core/persistence/knowledge_tables.dart`
- `core/persistence/execution_tables.dart`
- `core/persistence/local_only_tables.dart`

Rules:

- Drift stays centralized because the app uses one database.
- Ownership remains per domain even when table declarations live in `core/persistence/`.
- Repositories are the domain boundary for business reads and writes.
- Generated Drift files are never edited by hand.

## Backup And Restore

Location:

- `core/backup/`
- `core/backup/backup_table_registry.dart`

Rules:

- Backup/restore uses `kBackupTables`, not `kSyncableTables`.
- Backup table primary keys and restore outbox enqueue behavior are explicit
  in `BackupTableRegistration`.
- Syncable tables are not automatically backup tables unless their table
  metadata opts into backup coverage.

## Background And Notifications

Location:

- `core/background/`
- `core/notifications/`
- Health, Knowledge, and Execution agent providers.

Rules:

- Platform callbacks set lightweight flags and optional placeholder notifications.
- Full agent runs happen after app startup with a complete provider graph.
- Notification channels are domain-named and documented in the owning domain SSOT.

## Rust Boundary

Allowed:

- Embedding runtime and tokenizer through `flutter_rust_bridge`.
- Future security-sensitive sync encryption only after a separate trigger.

Not allowed:

- Business logic.
- Money math.
- Market data fetchers.
- SQL/Drift logic.
- Local LLM inference.
- Wide protobuf/event-dispatch SDKs.

## CI Gates

Run these when touching architecture boundaries:

```bash
./tool/lint-no-feature-in-shared.sh
./tool/lint-cross-feature-imports.sh
./tool/lint-finance-domain-data-imports.sh
./tool/lint-domain-neutral-contracts.sh
./tool/lint-frb-llm-entrypoints.sh
./tool/check-ai-contract-wire-enums.sh
```

Expected guarantees:

- Shared layers do not import domain features.
- `features/ai_chat/` does not import sibling features directly.
- Finance domain code does not import data-layer repositories or Drift rows.
- Domain-neutral contracts do not mention domain business types.
- AI contract wire enums match the checked-in serializer fixture.

Tool descriptor registration and sync row-family behavior are covered by the
regular Flutter test suite rather than duplicated shell wrappers.

## Change Checklist

For shell changes, verify:

- Domain inventory still comes from `DomainPack`.
- Optional domains work when disabled.
- Tool catalog and prompt blocks include only active domains.
- Router deep links still resolve for each domain.
- Proposal applier has one composite owner.
- Memory indexers do not create domain imports from `core/`.
- Sync prefixes are correct for new tables.
- Tests cover both active and inactive domain states.
