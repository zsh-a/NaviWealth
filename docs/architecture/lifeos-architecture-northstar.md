# LifeOS Architecture Northstar

This document defines hard architecture boundaries for new work. It is not a
roadmap. [ADR 0001](adr/0001-nsh-client-migration.md) adopts NSH and Rust domain
crates as the target. Flutter (`apps/mobile`) is frozen: bug fixes only; new
features belong in NSH/Rust crates. Existing Dart paths below describe the
frozen implementation until their owning migration phase is complete.

[ADR 0002](adr/0002-personal-local-scope.md) narrows the NSH client to a
personal, local-only app defined by [Product Scope](../product/product-scope.md):
ledger, holdings, meals, weight and Garmin. The multi-domain positioning,
opt-in domains, Sync v3 and Agent Runtime sections below apply only to the
frozen Flutter client and are not targets for the NSH client.

## Document Contract

Owns cross-domain layering, hard boundaries, and non-goals. It does not own
current feature inventories, wire formats, or delivery sequencing. The
architecture lint scripts enforce the existing Flutter dependency boundaries;
use [LifeOS Shell](lifeos-shell.md) for that implementation. The ADR owns the
client migration decision and [roadmap](../roadmap/roadmap-lifeos.md) its gates.

## Positioning

NaviWealth is a Personal LifeOS with multiple opt-in domains:

| Domain | Role | Activation |
|---|---|---|
| FinanceOS | Seed domain: wealth, cashflow, portfolio, FIRE, options income | Always on |
| HealthOS | Health signals, recovery, and trends | User opt-in |
| KnowledgeOS | Notes and decision memory | User opt-in |
| ExecutionOS | Plans, concrete actions, and progress review | User opt-in |

Future domains such as TimeOS or LivingOS require a separate ADR before code or planning starts.

LifeOS value lives in shared infrastructure: identity, memory, sync, AI runtime, agents, persistence, and multi-domain shell. Domains own their business models and user workflows.

## Non-Goals

- Do not add enums, fields, tools, tables, or abstractions without a current caller.
- Do not generalize for a hypothetical future domain. Add abstractions only when at least two real domains use them or a shell seam already exists.
- Do not add new Flutter features or extend the FRB architecture for new
  client work. NSH is the UI target; domain truth and business effects belong
  in their owning Rust crates under ADR 0001.
- Do not use NSH's 5 MB KV as the business database or as credential storage.
- Do not make one domain import another domain's business entities.
- Do not turn sync v3 into an event platform, CRDT framework, or multi-schema negotiation layer.
- Do not add social, collaboration, publishing, enterprise SaaS, or entertainment surfaces.
- Do not write phase plans for untriggered domains.
- Do not make a full-duplex or omni speech model the center of the product
  architecture. Model and engine choices belong behind capability seams.
- Do not add a second voice/agent execution loop or an `agent-interaction`
  crate to the standalone runtime without a current multi-host, durable-resume,
  or deterministic-replay caller.
- Do not move high-frequency PCM through Dart/FRB, and do not keep the
  microphone open in the background by default. Active-session audio belongs
  on the native hot path.

## Layering

```text
Experience and composition
  apps/nsh-client: NSH UI, presentation adapters, Rust domain registry

Domain business layer
  crates/{finance-core,health-core,knowledge-core,execution-core}

Cross-domain infrastructure
  crates/lifeos-core: encrypted persistence, HLC/outbox, Sync, audit, backup
  crates/lifeos-ai: in-process Agent Runtime host and domain-tool registration
  crates/sync-wire: shared envelopes and per-table JSON row contracts

Platform capabilities
  NSH host channels; apps/nsh-host-android Kotlin plugins where needed
```

This is the target package map; Phase 0 does not create the missing crates.
Dependencies flow from UI to domains to neutral infrastructure. Domain crates
must not import sibling domain business models. Cross-domain composition
belongs in the app; domain validation, calculations, and confirmed writes
belong in the owning domain crate. `sync-wire` does not give the backend
business ownership.

While Flutter remains, its existing rules still apply: `core/` is neutral and
must not import `features/`; domains must not import sibling domains; `app/`
is its composition root. Shared seams carry domain-neutral data. Use these
boundaries for bug fixes, not as a requirement to keep new truth in Dart.

## Domain Registration

The frozen Flutter shell registration seam is `DomainPack`. NSH preserves its
contribution/registry design through Rust traits and one app-owned registry;
ADR 0001 defines ownership without claiming that registry already exists.

Locations:

- Registry: `apps/mobile/lib/app/domain_packs.dart`
- Contract: `apps/mobile/lib/core/lifeos/domain_pack.dart`
- Domain opt-in: `apps/mobile/lib/core/auth/domain_scope.dart`
- Shell spec: `apps/mobile/lib/core/shell/domain_shell.dart`

Each domain may contribute:

- `DomainScope`
- AI device tools, descriptors, intents, and system prompt blocks
- Proposal kinds and apply/undo routing
- Shell spec, route builder, tab paths, and additional route ownership
- Agents and their presentation metadata
- Memory sources, indexers, and background jobs
- Command palette entries and provider overrides
- Life signals and cross-domain source-route resolution
- Data-management, notification, and domain-settings surfaces
- Share-intent handlers

`DomainPack` provides one app-composition registration for a domain. New domain
identities also require explicit `DomainScope` and client/backend sync namespace
registration; this is a finite build inventory, not a dynamic plugin contract.
Do not add independent domain switches in bootstrap, router, command palette,
tool registry, or agent registry.

## AI Boundaries

Existing Flutter domain-neutral code (target host: `crates/lifeos-ai`):

- `core/ai/contracts/`
- `core/ai/runtime/`
- `core/ai/local/memory/`
- `core/ai/agents/`
- `core/ai/composition/`

Existing Flutter domain-owned code (target: owning domain crates):

- `features/finance/ai_tools/` and finance slice `ai_tools/`
- `features/health/ai_tools/`
- `features/knowledge/ai_tools/`
- `features/<domain>/agents/`
- `features/<domain>/composition/`

App-owned cross-domain synthesis lives under `app/agents/`. It consumes only
domain-neutral signals/context and must not recalculate domain business values.
The production shape combines deterministic domain analyzers, confirmed
read-only scheduled LLM tasks, and one bounded Life synthesis agent. Financial
calculations remain domain-tool-owned; agents do not orchestrate other agents.

Rules:

- `ToolDescriptor`, `DeviceTool`, dispatcher, traces, proposal envelopes, and runtime loops are cross-domain contracts.
- Concrete business tools live in the owning domain.
- Tools that mutate state must use proposal or explicit confirmation semantics unless the tool is a narrow, user-explicit local write already documented in the domain SSOT.
- The LLM key is user-owned and stored on device. There is no backend AI relay or cloud fallback.

## Interaction Session Boundaries

One modality-agnostic `InteractionSession` coordinates voice, touch, and keyboard:

- Interaction owns timing and delivery; Agent Runtime owns semantics and
  execution; domains own truth and side effects; capabilities own modality.
- A pure reducer owns session policy. A thin Host coordinator invokes effects
  outside that reducer; voice must not introduce a second Agent loop.
- Pending `InteractionEnvelope` approval remains authoritative across input
  modalities. An interrupted response never rolls back a committed business effect.
- Generated text, delivered output, and next-turn context are distinct.
  Undelivered output must not silently become conversation history.
- High-frequency audio stays native. Dart/FRB receives semantic events, not PCM.
- Future realtime or omni adapters reuse tool, proposal, interaction, and resume
  gateways and explicitly declare their capabilities and transport policy.
  A local speech recognizer does not make a remote model request offline.

[AI Architecture](../ai/ai-architecture.md#51a-interactionsession-voice-turn)
owns session lanes, identifiers, event ordering, interruption, delivery projection,
and engine policy. [LifeOS Shell](lifeos-shell.md#interaction-session-runtime)
owns Host composition and code locations. These are implementation contracts,
not additional runtime architectures.

## Persistence Boundaries

The target is rusqlite + SQLCipher infrastructure in `crates/lifeos-core`, with
domain repositories owning business table access. HLC/outbox, sync, audit, and
backup are shared infrastructure; per-table wire specifications belong in
`crates/sync-wire`. Keys belong in platform secure storage, outside Sync and
exports. NSH KV is limited to small non-secret preferences.

The frozen Flutter client uses `core/persistence/` as its shared Drift adapter.
That placement does not make table ownership global. NSH migrates accounts by
pulling server rows into its database, never by converting Drift files.

Ownership rules:

- Finance business access goes through Finance repositories.
- Health business access goes through Health repositories.
- Knowledge business access goes through Knowledge repositories.
- Execution business access goes through Execution repositories.
- Cross-domain infrastructure may touch only infrastructure-owned tables such as auth, sync, traces, events, memories, embeddings, and local-only side tables.
- Direct DB access to another domain's business table is a boundary violation.

In the frozen Flutter client, shared sync envelope types live in `core/sync/`:

- `Hlc`
- `SyncMeta`
- `MutationStamper`
- Outbox providers

## Sync Boundaries

Sync v3 is the active protocol:

- Generic row-state store.
- Last-writer-wins register per row.
- One `POST /sync` cycle for push and pull.
- Row kinds are domain-prefixed at the sync boundary.
- Each domain has an authoritative reset generation so stale offline devices
  cannot resurrect data after permanent erasure.

Prefixes:

- `fin:`
- `health:`
- `know:`
- `exec:`

The backend remains schema-agnostic. Domain semantics stay on the client.

## Memory Boundaries

Memory Runtime is cross-domain infrastructure:

- Events: typed evidence identity for "what happened" (`domain`, `kind`,
  occurred/observed time, source family/row/fingerprint, facts, entities,
  confidence, and evidence anchor).
- Memories: source facts, explicitly confirmed long-term memory, and
  deterministic derived memory with required provenance.
- Embeddings: model-fingerprint-keyed side table.
- Context Builder: slot-based retrieval for agent and chat prompts.
- `PersonalProfileSnapshot`: stable, structured, explicitly confirmed goals,
  preferences, constraints, and rules. Derived baselines remain current state
  or lower-authority patterns unless the user confirms a Profile fact.
- `LifeContextSnapshot`: active-domain dynamic state, freshness, changes,
  relevant history, and a deterministic fingerprint.

Domain indexers convert domain rows into events and memories:

- Options trade journal indexer.
- Health metric indexer.
- Knowledge note and decision indexers.

New indexers belong in the owning domain and are contributed through the owning `DomainPack.lifecycle.memoryBootstrapBuilder`; `app/domain_bootstrap.dart` only loops active packs. Do not make `core/ai/local/memory/` import a domain.

Agent Artifacts, repeated reviews, attention decisions, and outcome feedback
are not durable Memory. A model inference can enter the stable profile only
through an explicit Memory proposal and user confirmation.

## Rust Boundary

[ADR 0001](adr/0001-nsh-client-migration.md) supersedes the old Dart-Host truth
and narrow-Rust-only restrictions. Rust now owns application domain truth,
repositories, Money math, and confirmed business effects in domain crates.
Cross-domain infrastructure stays neutral; NSH stays a UI/composition layer.

- `lifeos-core` owns rusqlite + SQLCipher infrastructure, HLC, outbox, Sync v3
  client, audit, and backup. Domains own table access and semantic migrations.
- `sync-wire` owns shared Sync v3 envelopes and existing table JSON formats.
  The backend remains schema-agnostic; it does not calculate domain values.
- `health-core` currently shares meal recognition, catalog nutrition, photo
  normalization, and destination-bound upload consent. Its planned domain
  expansion follows the roadmap; repositories and Sync are not already ported.
- `lifeos-ai` will host `third_party/agent-runtime` in process and register
  domain tools through traits. The standalone runtime remains the authority
  for provider-neutral execution, ChatTurn continuation, budgets, and resume.
- `apps/nsh-client` owns presentation and app-level registration. Platform-only
  Keystore, Health Connect, and background work use NSH host channels and a
  Kotlin Android plugin where needed.

New crates and abstractions require a current phase caller. Keep the reviewed
NSH 0.5.0 baseline and lockfiles; wrap framework use in local UI adapters.
Android encryption/key handling, Web feasibility, and plot suitability require
Phase 1 evidence. iOS remains outside active scope pending a product decision.

### Transitional Native Adapters

`apps/mobile/native/lifeos_native/` and generated FRB bindings remain only
while existing Flutter callers need them. Existing embedding, LLM transport,
Health, and market-data bridges are maintenance surfaces. Do not hand-edit
generated bindings. Retire FRB after replacements and caller-removal evidence,
not merely when the new in-process host compiles.

Speech capabilities remain domain-neutral. High-frequency audio stays native;
interaction policy and domain confirmation do not move into recognition
engines. Reuse the existing ChatTurn/proposal/session contracts rather than
introducing a second Agent loop.

### Standalone Market-Data SDK

`market-data-rs` remains an independent provider SDK. It may own upstream
protocols, identifier/quote normalization, routing, batching, rate limits,
bounded retries, deadlines, cancellation, and circuit breakers. It must not
depend on NaviWealth entities or repositories or mutate financial records.

Finance owns portfolio valuation, simulated trading, returns, corporate-action
application, Money math, ledger writes, policy, and persistent application
caching. These move from Dart into `finance-core` in verified batches. Existing
Flutter uses its Finance-owned `MarketDataService` adapter and Drift cache;
new NSH work uses Rust domain ownership. Avoid a second persistent cache or
stacked upstream retry/fallback chains.

Transport contracts preserve source, observation/fetch times, freshness,
adjustment mode, historical coverage, and failure diagnostics. Prices cross
JSON as decimal strings, quote instants as UTC, and daily bars as trading-date
labels. Do not substitute adjustment modes, merge incompatible histories, or
present partial coverage as complete. Provider rules remain owned by
[Market Data Providers](../domains/market-data-providers.md).

## Review Checklist

Before merging architecture-affecting code, answer:

- Which layer owns this code?
- Does `core/` remain domain-neutral?
- Is every new contract used by a current caller?
- Does cross-domain work go through `app/` composition or a `core/` seam?
- Are sync row families prefixed correctly?
- Are AI write paths confirmed or proposal-based?
- Did tests cover the owner boundary and the integration seam?
- Does the InteractionSession use a pure reducer behind a thin Coordinator?
- Are `BargeInCandidate` and `BargeInCommitted` distinct?
- Are generated text, delivered segments, and context projection separate?
- Does `ResponseEpoch` gate stale output without implying business rollback?
- Does high-frequency audio remain on the native hot path?

## Document Ownership

- This document: architecture boundaries.
- `lifeos-shell.md`: current shell implementation and extension points.
- `financeos-domain.md`: FinanceOS ownership and topic routing.
- `healthos-domain.md`: HealthOS domain behavior.
- `knowledgeos-domain.md`: KnowledgeOS domain behavior.
- `executionos-domain.md`: ExecutionOS domain behavior.
- `roadmap-lifeos.md`: cross-domain roadmap and product sequencing.
- `adr/0001-nsh-client-migration.md`: client direction and open platform decisions.
- `roadmap-finance.md`: archived historical sequencing, not active priorities.
