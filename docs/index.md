# NaviWealth Documentation

NaviWealth is a local-first Personal LifeOS. FinanceOS is always on; HealthOS,
KnowledgeOS, and ExecutionOS are opt-in domains registered through the LifeOS
shell. The client is migrating to NSH 0.5.0 and domain-owned Rust crates.
Android is the active migration target; Web retention and iOS remain open.
Device AI stays native-only; any retained Web client excludes AI and Health
platform integration.

Flutter (`apps/mobile`) is frozen: bug fixes only; new features belong in
NSH/Rust crates. [ADR 0001](architecture/adr/0001-nsh-client-migration.md)
records the decision and [LifeOS Roadmap](roadmap/roadmap-lifeos.md) its gates.

This documentation uses a docs-as-code structure:

- Architecture documents define boundaries and extension seams.
- Domain SSOTs define business behavior owned by each domain.
- Reference documents describe active wire protocols and runtime contracts.
- The LifeOS roadmap owns active migration sequencing. The old Finance roadmap
  and product-direction study are explicitly archived historical context.
- `AGENTS.md` / `CLAUDE.md` is the compact AI-agent operating guide.
- `llms.txt` is the LLM-friendly public entry point.

## Start Here

| Need | Read |
|---|---|
| Route an Agent task to the minimum SSOT set | [Agent Task Map](agent-map.md) |
| Change client direction | [NSH Migration ADR](architecture/adr/0001-nsh-client-migration.md), [LifeOS Roadmap](roadmap/roadmap-lifeos.md) |
| Change architecture or cross-domain code | [Architecture Northstar](architecture/lifeos-architecture-northstar.md), [LifeOS Shell](architecture/lifeos-shell.md) |
| Add or modify a domain | [LifeOS Shell](architecture/lifeos-shell.md), then the owning domain SSOT |
| Work on device AI | [Device AI Architecture](ai/ai-architecture.md), [Runtime Event Contract](ai/ai-protocol.md), [Agent Experience](ai/agent-experience.md) |
| Work on personal memory beyond V1 | [AI Architecture](ai/ai-architecture.md) for current Memory behavior; the [Personal Memory Implementation Plan](ai/personal-memory-implementation-plan.md) retains only the deferred Phases 4–5 |
| Work on Rust agent runtime | [Agent Runtime Current Architecture](architecture/agent-runtime-current.md) |
| Work on sync | [Sync v3 Protocol](sync/sync-v3.md), [Protocol Test Catalogue](sync/sync-protocol-tests.md) |
| Add business diagnostics | [Structured Logging](development/logging.md) |
| Run or test locally | [Local Development](development/local-development.md), [Testing Strategy](development/testing-strategy.md) |
| Review historical product hypotheses | [Archived Product Direction And Demand Validation](roadmap/product-direction-and-demand-validation.md) |
| Plan committed product work | [NSH Migration Roadmap](roadmap/roadmap-lifeos.md); [FinanceOS Roadmap](roadmap/roadmap-finance.md) is archived |

## Domain Sources In The Frozen Client

Domain SSOTs retain business contracts used for parity. Dart code roots below
are current Flutter implementation authorities, not destinations for new features.

| Domain | Status | Code root | Sync prefix | SSOT |
|---|---|---|---|---|
| FinanceOS | Always on | `apps/mobile/lib/features/finance/` | `fin:` | [FinanceOS](domains/financeos-domain.md) |
| HealthOS | User opt-in | `apps/mobile/lib/features/health/` | `health:` | [HealthOS](domains/healthos-domain.md), [Garmin Integration](domains/garmin-integration.md) |
| KnowledgeOS | User opt-in | `apps/mobile/lib/features/knowledge/` | `know:` | [KnowledgeOS](domains/knowledgeos-domain.md) |
| ExecutionOS | User opt-in | `apps/mobile/lib/features/execution/` | `exec:` | [ExecutionOS](domains/executionos-domain.md) |

The production registry is
`apps/mobile/lib/app/domain_packs.dart`. Add a domain by adding a real domain
package and one `DomainPack` entry for app composition. A new domain identity
also requires deliberate opt-in and client/backend sync namespace registration;
see [LifeOS Shell](architecture/lifeos-shell.md#adding-or-changing-a-domain).
Do not scatter one-off switches through bootstrap, router, command palette,
or AI tool aggregation.

## Current Code Map

New client: `apps/nsh-client/`; shared recognition: `crates/health-core/`;
in-process runtime source: `third_party/agent-runtime/`. Other target crates
are introduced by the migration phases. The following is the frozen Flutter
and existing backend implementation map.

```text
apps/mobile/lib/
  app/                  bootstrap, router, domain packs, shell chrome
  core/                 domain-neutral AI, auth, sync, persistence, shell
  design_system/        tokens, themes, charts, reusable widgets
  features/
    finance/            FinanceOS composition, tools, data root, and slices
    health/             HealthOS data, UI, AI tools, agents
    knowledge/          KnowledgeOS notes, decisions, UI, AI tools
    execution/          ExecutionOS data, UI, AI tools, agents
  l10n/                 generated localizations and ARB sources
```

```text
apps/backend/src/
  lib.rs                Worker router
  auth/                 JWT, password hashing, middleware
  routes/               health, auth, me, sync
  sync/                 generic row-state sync store
  error.rs              coded JSON errors
```

## Maintenance Policy

Documents describe the current product and implementation only. When a
protocol, migration plan, audit, or handoff note is superseded, update its
active SSOT and remove the obsolete document and navigation entry. The archived
Finance roadmap and product-direction study are retained by the explicit NSH
migration decision; their historical priorities are not active delivery gates.
