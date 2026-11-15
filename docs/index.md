# NaviWealth Documentation

NaviWealth is a local-first personal finance and health app for one Android
phone. The client is NSH (Rust); business truth lives in the `navi-finance`
and `navi-health` crates, and the `third_party/agent-runtime` submodule
supplies provider-neutral LLM protocol and client code. There is no backend,
no sync and no account system; local backups only.
[Personal Local Scope](architecture/personal-local-scope.md) records the
scope decisions behind the personal, local-only app defined by
[Product Scope](product/product-scope.md); the [roadmap](roadmap/roadmap-nsh.md)
owns delivery gates.

This documentation uses a docs-as-code structure:

- Architecture ADRs define direction and scope decisions.
- Product Scope and the roadmap own what is built and in which order.
- `AGENTS.md` / `CLAUDE.md` is the compact AI-agent operating guide.
- `llms.txt` is the LLM-friendly public entry point.

## Start Here

| Need | Read |
|---|---|
| Route an Agent task to the minimum SSOT set | [Agent Task Map](agent-map.md) |
| Change client direction | [Personal Local Scope](architecture/personal-local-scope.md), [NSH Roadmap](roadmap/roadmap-nsh.md) |
| Understand what is built | [Product Scope](product/product-scope.md) |
| Work on the NSH client | [`apps/nsh-client/README.md`](../apps/nsh-client/README.md), [Local Development](development/local-development.md) |
| Work on finance truth | `crates/navi-finance/` (tests are the executable contract) |
| Work on health truth | `crates/navi-health/` (tests are the executable contract) |
| Work on the Rust agent runtime | [Agent Runtime Current Architecture](architecture/agent-runtime-current.md) |
| Refresh the securities catalog | [`tool/asset_catalog/README.md`](../tool/asset_catalog/README.md) |
| Plan committed product work | [NSH Roadmap](roadmap/roadmap-nsh.md) |

## Current Code Map

```text
apps/nsh-client/           NSH (Rust) client: UI, storage, pages, headless tests
crates/navi-finance/       double-entry ledger, holdings, catalog truth
crates/navi-health/        meal recognition, nutrition, Garmin parsing
third_party/agent-runtime/ llm-protocol, llm-client (submodule)
third_party/market-data-rs/ market-data SDK (Tencent quotes)
tool/asset_catalog/        catalog sources, build, validation and publish pipeline
```

## Maintenance Policy

Documents describe the current product and implementation only. When a
document is superseded, update its active SSOT and remove the obsolete
document and navigation entry. Retired Flutter-era documents remain reachable
at the `flutter-final` tag.
