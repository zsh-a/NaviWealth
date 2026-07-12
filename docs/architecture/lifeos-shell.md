# LifeOS Shell SSOT

This document describes the current cross-domain shell. It is written for implementation agents: where to plug in, which files own each seam, and which boundaries must not move.

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

- FinanceOS: `../roadmap/roadmap-finance.md` and finance feature docs.
- HealthOS: `../domains/healthos-domain.md`.
- KnowledgeOS: `../domains/knowledgeos-domain.md`.
- ExecutionOS: `../domains/executionos-domain.md`.

## Current Shape

```text
app/
  bootstrap.dart                 Provider overrides and shell composition
  domain_packs.dart              Production domain inventory
  router_builder.dart            Outer dock shell plus domain routes
  app_dock_shell.dart            Multi-domain chrome
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
| FinanceOS | `finance` | Today, Activity, Wealth, Plan | `kFinanceDeviceTools` | none |
| HealthOS | `health` | Today, Trend, Plan | `kHealthDeviceTools` | Morning Briefing, Recovery Alert, Weekly Summary |
| KnowledgeOS | `knowledge` | Inbox, Library, Review | `kKnowledgeDeviceTools` | Review, Assumption, Contradiction, Inbox Triage, Routine Due |
| ExecutionOS | `execution` | Today, Commitments, Review | `kExecutionDeviceTools` | Review |

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
8. Add tests for opt-in behavior, route ownership, tool registration, and domain-specific repositories.

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

## Agent Runtime

Core framework:

- `core/ai/agents/agent.dart`
- `core/ai/agents/agent_schedule.dart`
- `core/ai/agents/agent_registry.dart`
- `core/ai/agents/agent_runner.dart`

Current domain agents:

- Health: Morning Briefing, Recovery Alert, Weekly Summary.
- Knowledge: Review, Assumption, Contradiction, Inbox Triage, Routine Due.
- Execution: Review.

Rules:

- Agents are named use cases, not a general automation platform.
- Agents read through repositories, tools, or Memory Runtime and write events/memories/proposals/notifications according to domain SSOTs.
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

Rules:

- `core/ai/local/memory/` does not import domains.
- Domain indexers live in domain `data/`.
- Domain indexers are contributed through `DomainPack.memoryBootstrapBuilder`;
  the app bootstrap only loops active packs.
- Memory embeddings are derived local data and can be rebuilt.
- `build_context` is the preferred LLM retrieval tool for contextual answers; `query_memory` remains a flat fallback.

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
- Build helper: `tool/build-lifeos-native.sh` from the repository root.

Behavior:

- Bootstrap attempts to load EmbeddingGemma when model, ORT, and library paths are available.
- Failures fall back to `StubEmbedder`.
- Fingerprint changes drop stale vectors and allow reindexing.
- Web does not load the native embedder.

## Sync V2

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
./tool/lint-no-finance-in-core.sh
./tool/lint-no-feature-in-shared.sh
./tool/lint-design-system-domain-neutral.sh
./tool/lint-no-legacy-mobile-domain.sh
./tool/lint-cross-feature-imports.sh
./tool/lint-finance-domain-model-path.sh
./tool/lint-finance-domain-data-imports.sh
./tool/lint-finance-dashboard-read-model-path.sh
./tool/lint-row-family-prefix.sh
./tool/lint-domain-neutral-contracts.sh
./tool/lint-frb-llm-entrypoints.sh
./tool/check-tool-descriptors.sh
```

Expected guarantees:

- `core/ai/runtime/` does not import domain features.
- `features/ai_chat/` does not import sibling features directly.
- `design_system/` stays free of domain business value objects.
- The retired top-level mobile `domain/` package does not return.
- Finance core models stay under `features/finance/domain/models/`, not the
  data-layer repository directory.
- Row change literals in sync code carry domain prefixes.
- Domain-neutral contracts do not mention domain business types.
- Tool descriptors mirror registered tools.

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
