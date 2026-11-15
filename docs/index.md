# NaviWealth Documentation

NaviWealth is a local-first personal finance and health app for one Android
phone. The client is NSH (Rust); business truth lives in the `finance-core`
and `health-core` crates, and the `third_party/agent-runtime` submodule
supplies provider-neutral LLM protocol and client code. There is no backend,
no sync and no account system; local backups only.
[ADR 0001](architecture/adr/0001-nsh-client-migration.md) records the NSH
direction, [ADR 0002](architecture/adr/0002-personal-local-scope.md) narrows
it to a personal local-only app defined by
[Product Scope](product/product-scope.md), and
[ADR 0003](architecture/adr/0003-flutter-retirement.md) records the Flutter
and Sync backend retirement. The [roadmap](roadmap/roadmap-lifeos.md) owns
delivery gates.

This documentation uses a docs-as-code structure:

- Architecture ADRs define direction and scope decisions.
- Product Scope and the roadmap own what is built and in which order.
- `AGENTS.md` / `CLAUDE.md` is the compact AI-agent operating guide.
- `llms.txt` is the LLM-friendly public entry point.

## Start Here

| Need | Read |
|---|---|
| Route an Agent task to the minimum SSOT set | [Agent Task Map](agent-map.md) |
| Change client direction | [ADR 0001](architecture/adr/0001-nsh-client-migration.md), [ADR 0002](architecture/adr/0002-personal-local-scope.md), [ADR 0003](architecture/adr/0003-flutter-retirement.md), [LifeOS Roadmap](roadmap/roadmap-lifeos.md) |
| Understand what is built | [Product Scope](product/product-scope.md) |
| Work on the NSH client | [`apps/nsh-client/README.md`](../apps/nsh-client/README.md), [Local Development](development/local-development.md) |
| Work on finance truth | `crates/finance-core/` (tests are the executable contract) |
| Work on health truth | `crates/health-core/` (tests are the executable contract) |
| Work on the Rust agent runtime | [Agent Runtime Current Architecture](architecture/agent-runtime-current.md) |
| Refresh the securities catalog | [`tool/asset_catalog/README.md`](../tool/asset_catalog/README.md) |
| Review historical product hypotheses | [Archived Product Direction And Demand Validation](roadmap/product-direction-and-demand-validation.md) |
| Plan committed product work | [NSH Roadmap](roadmap/roadmap-lifeos.md); the [FinanceOS Roadmap](roadmap/roadmap-finance.md) is archived |

## Current Code Map

```text
apps/nsh-client/           NSH (Rust) client: UI, storage, pages, headless tests
crates/finance-core/       double-entry ledger, holdings, catalog truth
crates/health-core/        meal recognition, nutrition, Garmin parsing
third_party/agent-runtime/ llm-protocol, llm-client (submodule)
third_party/market-data-rs/ market-data SDK (Tencent quotes)
assets/catalog/            committed securities catalog bundle
tool/asset_catalog/        catalog build, validation and publish pipeline
```

## Maintenance Policy

Documents describe the current product and implementation only. When a
document is superseded, update its active SSOT and remove the obsolete
document and navigation entry. The archived Finance roadmap and
product-direction study are retained historical context; their priorities are
not active delivery gates. Retired Flutter-era documents remain reachable at
the `flutter-final` tag.
