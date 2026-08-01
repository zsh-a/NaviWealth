# Agent Task Map

Status: active documentation router.

Use this page to load the smallest authoritative context for a task. It is a
router, not a second source of product or architecture truth.

## Task Routing

| Task | Read first | Code authority | Minimum verification |
|---|---|---|---|
| Change architecture or cross-domain ownership | [Architecture Northstar](architecture/lifeos-architecture-northstar.md), [LifeOS Shell](architecture/lifeos-shell.md) | `apps/mobile/lib/core/lifeos/domain_pack.dart`, `apps/mobile/lib/app/domain_packs.dart` | Architecture lint scripts in the Shell SSOT |
| Add or change a domain | [LifeOS Shell](architecture/lifeos-shell.md), owning domain SSOT | Owning `apps/mobile/lib/app/domain_packs/*_pack.dart`, `apps/mobile/lib/features/<domain>/` | Domain composition, router, and opt-in tests |
| Change FinanceOS behavior | [FinanceOS](domains/financeos-domain.md), then the relevant Finance topic SSOT | `apps/mobile/lib/features/finance/` | Focused repository/tool/widget tests |
| Change a domain Agent | [Agent Experience](ai/agent-experience.md), owning domain SSOT | Owning `apps/mobile/lib/features/<domain>/agents/`, `DomainPack.agentBuilder` | Agent unit tests, outcome corpus, composition test |
| Change AI runtime or interaction | [AI Architecture](ai/ai-architecture.md), [AI Protocol](ai/ai-protocol.md), [Agent Runtime](architecture/agent-runtime-current.md) | `apps/mobile/lib/core/ai/`, `apps/mobile/lib/app/agent_runtime/`, `apps/mobile/native/lifeos_native/` | AI wire-enum and FRB-entrypoint gates |
| Add or change an AI tool | [AI Architecture](ai/ai-architecture.md), owning domain SSOT | Domain tool barrel and `DomainPack` descriptors | Tool tests and device degradation contract |
| Change persistence or a synced table | [Sync v3](sync/sync-v3.md), owning domain SSOT | `apps/mobile/lib/core/persistence/`, `apps/mobile/lib/core/sync/sync_table_registry.dart` | Sync fixtures, repository tests, architecture lints |
| Change backup or destructive data management | [LifeOS Shell](architecture/lifeos-shell.md), owning domain SSOT | `apps/mobile/lib/core/backup/`, `apps/mobile/lib/core/data_management/` | Restore atomicity and data-management tests |
| Change Web behavior | [Web Compatibility](development/web-compat-matrix.md), [Web Routing](development/web-routing.md) | Web adapters, router, `web_smoke/` | Release web build and focused Playwright smoke |
| Change test architecture or CI coverage | [Testing Strategy](development/testing-strategy.md) | Tests and `.github/workflows/` | The affected local command plus CI-equivalent gate |
| Plan product work | Relevant roadmap only after reading the owning SSOT | `roadmap/roadmap-lifeos.md` or `roadmap/roadmap-finance.md` | Exit evidence stated in the roadmap |

## Source-Of-Truth Rules

- Code inventory comes from registries and tests, not copied Markdown lists.
- Architecture documents own invariants; domain documents own business
  behavior; protocol documents own wire formats; roadmaps own unfinished
  sequencing only.
- When two documents overlap, follow the document whose contract explicitly
  says it owns the topic. If neither does, resolve ownership before adding a
  third description.
- `Last reviewed` is maintenance metadata, not proof of authority. Prefer the
  declared code authority and executable contracts.
- Read runbooks only when executing their workflow; they are not architecture
  inputs.

## Domain Routing

| Domain | Entry SSOT | Topic SSOTs |
|---|---|---|
| FinanceOS | [FinanceOS](domains/financeos-domain.md) | [Income Strategy](domains/income-strategy.md), [Options Income](domains/options-income.md), [Portfolio Strategy Groups](domains/portfolio-strategy-groups.md), [Market Data Providers](domains/market-data-providers.md) |
| HealthOS | [HealthOS](domains/healthos-domain.md) | [Garmin Integration](domains/garmin-integration-plan.md) |
| KnowledgeOS | [KnowledgeOS](domains/knowledgeos-domain.md) | — |
| ExecutionOS | [ExecutionOS](domains/executionos-domain.md) | — |

## Global Verification

For architecture-affecting mobile changes, run the lint gates listed in
[LifeOS Shell](architecture/lifeos-shell.md#ci-gates). For exact commands and
test-layer selection, use [Testing Strategy](development/testing-strategy.md).
Do not run every suite by default when a focused executable contract covers the
change.
