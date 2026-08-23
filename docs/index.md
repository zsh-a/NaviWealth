# NaviWealth Documentation

NaviWealth is a local-first Personal LifeOS. FinanceOS is always on; HealthOS,
KnowledgeOS, and ExecutionOS are opt-in domains registered through the LifeOS
shell. The app targets iOS, Android, and Web. Device AI is native-only; Web
has no AI runtime and no Health platform integration.

This documentation uses a docs-as-code structure:

- Architecture documents define boundaries and extension seams.
- Domain SSOTs define business behavior owned by each domain.
- Reference documents describe active wire protocols and runtime contracts.
- Roadmaps describe current sequencing only. Superseded plans and protocols
  are removed instead of retained as compatibility documentation.
- `AGENTS.md` / `CLAUDE.md` is the compact AI-agent operating guide.
- `llms.txt` is the LLM-friendly public entry point.

## Start Here

| Need | Read |
|---|---|
| Route an Agent task to the minimum SSOT set | [Agent Task Map](agent-map.md) |
| Change architecture or cross-domain code | [Architecture Northstar](architecture/lifeos-architecture-northstar.md), [LifeOS Shell](architecture/lifeos-shell.md) |
| Add or modify a domain | [LifeOS Shell](architecture/lifeos-shell.md), then the owning domain SSOT |
| Work on device AI | [Device AI Architecture](ai/ai-architecture.md), [Runtime Event Contract](ai/ai-protocol.md), [Agent Experience](ai/agent-experience.md) |
| Plan Personal Memory V1 | [Personal Memory V1 Implementation Plan](ai/personal-memory-implementation-plan.md), then confirm sequencing in the [LifeOS Roadmap](roadmap/roadmap-lifeos.md) |
| Work on Rust agent runtime | [Agent Runtime Current Architecture](architecture/agent-runtime-current.md) |
| Work on sync | [Sync v3 Protocol](sync/sync-v3.md), [Protocol Test Catalogue](sync/sync-protocol-tests.md) |
| Add business diagnostics | [Structured Logging](development/logging.md) |
| Run or test locally | [Local Development](development/local-development.md), [Testing Strategy](development/testing-strategy.md) |
| Validate product direction | [Product Direction And Demand Validation](roadmap/product-direction-and-demand-validation.md) |
| Plan committed product work | [LifeOS Roadmap](roadmap/roadmap-lifeos.md), [FinanceOS Roadmap](roadmap/roadmap-finance.md) |

## Active Domain Sources

| Domain | Status | Code root | Sync prefix | SSOT |
|---|---|---|---|---|
| FinanceOS | Always on | `apps/mobile/lib/features/finance/` | `fin:` | [FinanceOS](domains/financeos-domain.md) |
| HealthOS | User opt-in | `apps/mobile/lib/features/health/` | `health:` | [HealthOS](domains/healthos-domain.md), [Garmin Integration](domains/garmin-integration-plan.md) |
| KnowledgeOS | User opt-in | `apps/mobile/lib/features/knowledge/` | `know:` | [KnowledgeOS](domains/knowledgeos-domain.md) |
| ExecutionOS | User opt-in | `apps/mobile/lib/features/execution/` | `exec:` | [ExecutionOS](domains/executionos-domain.md) |

The production registry is
`apps/mobile/lib/app/domain_packs.dart`. Add a domain by adding a real domain
package and one `DomainPack` entry; do not scatter one-off switches through
bootstrap, router, command palette, or AI tool aggregation.

## Current Code Map

```text
apps/mobile/lib/
  app/                  bootstrap, router, domain packs, shell chrome
  core/                 domain-neutral AI, auth, sync, persistence, shell
  design_system/        tokens, themes, charts, reusable widgets
  features/
    finance/            FinanceOS composition, tools, data root, and slices
    health/             HealthOS data, UI, AI tools, agents
    knowledge/          KnowledgeOS data, UI, AI tools, agents
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
  hlc.rs                Hybrid Logical Clock
```

## Maintenance Policy

Documents describe the current product and implementation only. When a
protocol, migration plan, audit, or handoff note is superseded, update its
active SSOT and remove the obsolete document and navigation entry.
