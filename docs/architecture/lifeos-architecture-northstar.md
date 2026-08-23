# LifeOS Architecture Northstar

This document defines hard architecture boundaries for new work. It is not a roadmap and does not track completed migration history. When code and this document disagree, treat this document as the target boundary and update the stale source.

## Document Contract

Owns cross-domain layering, hard boundaries, and non-goals. It does not own
current feature inventories, wire formats, or delivery sequencing. The
architecture lint scripts are the executable authority for dependency
boundaries; use [LifeOS Shell](lifeos-shell.md) for current composition.

## Positioning

NaviWealth is a Personal LifeOS with multiple opt-in domains:

| Domain | Role | Activation |
|---|---|---|
| FinanceOS | Seed domain: wealth, cashflow, portfolio, FIRE, options income | Always on |
| HealthOS | Health signals, recovery, and trends | User opt-in |
| KnowledgeOS | Decision memory, review, assumptions, routines | User opt-in |
| ExecutionOS | Personal actions, projects, commitments, and progress review | User opt-in |

Future domains such as TimeOS or LivingOS require a separate ADR before code or planning starts.

LifeOS value lives in shared infrastructure: identity, memory, sync, AI runtime, agents, persistence, and multi-domain shell. Domains own their business models and user workflows.

## Non-Goals

- Do not add enums, fields, tools, tables, or abstractions without a current caller.
- Do not generalize for a hypothetical future domain. Add abstractions only when at least two real domains use them or a shell seam already exists.
- Do not pivot the app into a wide Flutter/Rust local engine. Rust is allowed only for narrow performance or security surfaces.
- Do not make one domain import another domain's business entities.
- Do not turn sync v3 into an event platform, CRDT framework, or multi-schema negotiation layer.
- Do not add social, collaboration, publishing, enterprise SaaS, or entertainment surfaces.
- Do not write phase plans for untriggered domains.

## Layering

```text
Experience layer
  Flutter UI, Forui, design system, domain shells

Domain business layer
  features/<domain>/{ui,data,domain,ai_tools,agents}

Cross-domain infrastructure
  core/{ai,auth,sync,persistence,audit,shell,lifeos,background,notifications}
```

Rules:

- Dependencies flow downward: experience to domain to infrastructure.
- `core/` must stay domain-neutral and must not import `features/`.
- `features/<domain>/` must not import a sibling domain. Cross-domain coordination belongs in `app/` or `core/` seams.
- `app/` is the composition root and may import multiple domains.
- Shared contracts carry primitive, JSON, or domain-neutral data. They must not
  expose Finance, Health, Knowledge, or Execution entities.

## Domain Registration

The current shell registration seam is `DomainPack`.

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

Adding a domain means landing the domain feature, adding a `DomainPack`, and wiring a single registry entry. Do not add independent domain switches in bootstrap, router, command palette, tool registry, or agent registry.

## AI Boundaries

Domain-neutral code:

- `core/ai/contracts/`
- `core/ai/runtime/`
- `core/ai/local/memory/`
- `core/ai/agents/`
- `core/ai/composition/`

Domain-owned code:

- `features/finance/ai_tools/` and finance slice `ai_tools/`
- `features/health/ai_tools/`
- `features/knowledge/ai_tools/`
- `features/<domain>/agents/`
- `features/<domain>/composition/`

App-owned cross-domain synthesis lives under `app/agents/`. It consumes only
domain-neutral signals/context and must not recalculate domain business values.
The production shape is many deterministic domain analyzers plus one bounded
Life synthesis agent, not agent-to-agent orchestration.

Rules:

- `ToolDescriptor`, `DeviceTool`, dispatcher, traces, proposal envelopes, and runtime loops are cross-domain contracts.
- Concrete business tools live in the owning domain.
- Tools that mutate state must use proposal or explicit confirmation semantics unless the tool is a narrow, user-explicit local write already documented in the domain SSOT.
- The LLM key is user-owned and stored on device. There is no backend AI relay or cloud fallback.

## Persistence Boundaries

`core/persistence/` is the shared Drift adapter and contains app tables because Drift uses one database. That placement does not make table ownership global.

Ownership rules:

- Finance business access goes through Finance repositories.
- Health business access goes through Health repositories.
- Knowledge business access goes through Knowledge repositories.
- Execution business access goes through Execution repositories.
- Cross-domain infrastructure may touch only infrastructure-owned tables such as auth, sync, traces, events, memories, embeddings, and local-only side tables.
- Direct DB access to another domain's business table is a boundary violation.

Shared sync envelope types live in `core/sync/`:

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
  preferences, constraints, baselines, and routines.
- `LifeContextSnapshot`: active-domain dynamic state, freshness, changes,
  relevant history, and a deterministic fingerprint.

Domain indexers convert domain rows into events and memories:

- Options trade journal indexer.
- Health metric indexer.
- Knowledge object and decision indexers.

New indexers belong in the owning domain and are contributed through the owning `DomainPack.memoryBootstrapBuilder`; `app/domain_bootstrap.dart` only loops active packs. Do not make `core/ai/local/memory/` import a domain.

Agent Artifacts, repeated reviews, attention decisions, and outcome feedback
are not durable Memory. A model inference can enter the stable profile only
through an explicit Memory proposal and user confirmation.

## Rust Boundary

Rust is allowed only when all are true:

- There is a real performance or security delta.
- A caller exists in the current phase.
- The FFI surface is narrow enough for `flutter_rust_bridge`.
- Web does not require a new wasm runtime.

Current Rust surface:

- `apps/mobile/native/lifeos_native/`
- EmbeddingGemma embedder via fastembed and ONNX Runtime.
- Native agent-runtime / `agent-llm` / `agent-chat` FRB bridge for
  device-only provider calls, ChatTurn request contracts, and runtime JSON
  contract normalization.
- Native Health provider primitives where platform/runtime behavior requires
  Rust.
- Generated FRB bindings under `apps/mobile/lib/src/rust/`.

The separate `sherpa_onnx` C++/Dart-FFI dependency is allowed only behind the
domain-neutral `core/speech/` contract. It consumes microphone PCM and emits
draft text; it does not own business policy, persistence, tools, or automatic
writes. Web uses a stub and does not load the native runtime.

Do not move business logic, Money math, market fetchers, SQL access, domain
repositories, or local LLM model inference into Rust.

## Review Checklist

Before merging architecture-affecting code, answer:

- Which layer owns this code?
- Does `core/` remain domain-neutral?
- Is every new contract used by a current caller?
- Does cross-domain work go through `app/` composition or a `core/` seam?
- Are sync row families prefixed correctly?
- Are AI write paths confirmed or proposal-based?
- Did tests cover the owner boundary and the integration seam?

## Document Ownership

- This document: architecture boundaries.
- `lifeos-shell.md`: current shell implementation and extension points.
- `financeos-domain.md`: FinanceOS ownership and topic routing.
- `healthos-domain.md`: HealthOS domain behavior.
- `knowledgeos-domain.md`: KnowledgeOS domain behavior.
- `executionos-domain.md`: ExecutionOS domain behavior.
- `roadmap-lifeos.md`: cross-domain roadmap and product sequencing.
- `roadmap-finance.md`: FinanceOS roadmap and product sequencing.
