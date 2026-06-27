# NaviWealth LifeOS Roadmap

Status: active cross-domain roadmap.

This document owns product and engineering sequencing that cuts across
FinanceOS, HealthOS, KnowledgeOS, and ExecutionOS. Domain-specific behavior remains in
the domain SSOTs:

- FinanceOS: `roadmap-finance.md`
- HealthOS: `healthos-domain.md`
- KnowledgeOS: `knowledgeos-domain.md`
- ExecutionOS: `executionos-domain.md`
- Shell and registration seams: `lifeos-shell.md`
- Hard boundaries and non-goals: `lifeos-architecture-northstar.md`

## Current Product Shape

NaviWealth is now a local-first Personal LifeOS:

| Domain | Activation | Primary value |
|---|---|---|
| FinanceOS | Always on | Wealth, cashflow, FIRE, investment, options income |
| HealthOS | User opt-in | Recovery signals, health trends, morning briefing |
| KnowledgeOS | User opt-in | Decision memory, assumptions, routines, review work |
| ExecutionOS | User opt-in | Personal actions, projects, commitments, progress review |

FinanceOS remains the seed domain, but the active roadmap is no longer
Finance-only. New work should improve the shared LifeOS substrate or close
one domain's real user workflow; do not add untriggered domains.

## Priority Order

### 1. Multi-Domain Foundation Convergence

Make the current three-domain system coherent before adding new domains.

- Keep `DomainPack` as the single domain inventory.
- Keep domain opt-in behavior centralized through `activeDomainPacksProvider`.
- Ensure tools, prompts, shell specs, agents, and command palette entries
  all derive from active packs.
- Remove stale docs or code paths that still describe KnowledgeOS or
  HealthOS as untriggered future domains.

### 2. Task-Spine Completion

Grow task-level tests and product polish around durable user jobs, not pages:

- Add account.
- Import CSV or statement.
- Ask AI with local evidence.
- Generate FIRE report.
- Plan options income.
- Backup, restore, and export.

Each task should earn a flow test, a primary-surface golden where useful,
and a targeted integration or contract test for its data path.

### 3. High-Quality Data Ingestion

FinanceOS value is limited by manual data entry. The ingest substrate exists;
the next step is provider-specific parsing for real user files:

- Start with the most common user-provided source.
- Keep review and dedup explicit.
- Do not call the LLM synchronously on capture/import save paths.
- Treat imported data as draft until the user confirms it.

### 4. AI Evidence, Proposal, And Memory Quality

Device AI should be auditable by construction:

- Tool outputs should return `EvidenceAnchor` where they cite local state.
- Write tools should return proposals or use explicit confirmation.
- Batch proposals need UI, undo, and progress treatment before they become
  normal agent output.
- Memory retrieval should be evaluated for answer quality, not only for
  successful vector lookup.

### 5. Observability And Diagnostics

Default-off observability should become useful for development and opt-in
production diagnostics:

- Wire the chosen crash backend behind `OptInCrashReporter`.
- Surface sync and performance diagnostics in developer-facing views.
- Keep payload capture disabled unless the user explicitly enables verbose
  local diagnostics.

### 6. Sync Hardening

Sync v2 remains row-state LWW. Near-term work should harden the protocol,
not redesign it:

- Add Dart-to-Rust wire contract tests.
- Make conflicts and skipped rows diagnosable.
- Start E2EE only after the v2 stability window is met.
- Keep the backend schema-agnostic.

### 7. Bootstrap And Startup Composition

`bootstrap.dart` is the current composition root, but startup concerns should
stay modular:

- Move domain startup jobs into small startup modules.
- Keep provider overrides grouped by concern.
- Make eager background jobs opt-in aware and cheap at first paint.

### 8. Native Embedding Distribution

The Rust EmbeddingGemma path is a narrow native surface. It should be made
installable and diagnosable before more native runtime is added:

- Verify iOS and Android bundling paths.
- Keep Web on stub behavior.
- Provide model install and recovery UX.
- Test embedder fingerprint changes and vector invalidation.

### 9. Engineering Debt Burn-Down

Keep the ratchets moving down:

- Keep the non-golden test suite at zero failures; do not introduce failure
  allowlists.
- Keep boundary lint gates green.
- Prefer contract tests for cross-language or cross-domain seams.

### 10. Completion Audit Discipline

Before claiming a roadmap item done, prove it from current state:

- Identify the authoritative file, test, command, or runtime behavior.
- Verify the full stated scope, not a narrow proxy.
- Update the owning SSOT when the implementation changes the roadmap.

## Anti-Goals

- Do not add TimeOS, LivingOS, or any future domain without a new ADR.
- Do not turn sync v2 into CRDT, event sourcing, or schema negotiation.
- Do not add a backend AI relay.
- Do not put domain entities into `core/` contracts.
- Do not introduce social, collaboration, publishing, or entertainment
  surfaces.
