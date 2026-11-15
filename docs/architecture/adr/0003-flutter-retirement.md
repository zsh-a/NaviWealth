# ADR 0003: Retire Flutter And The Sync Backend Directly

Status: accepted.

Date: 2026-11-15.

## Context

[ADR 0001](0001-nsh-client-migration.md) planned a phased migration with a
one-time Flutter data import through Sync v3;
[ADR 0002](0002-personal-local-scope.md) reduced the NSH client to a personal,
local-only app. The owner then decided the remaining migration machinery is
not worth its cost:

- The owner records fewer than ten trades a year, so broker statement import
  stays out of scope and holdings remain manual entry.
- Displaying allocation by asset class and currency on Assets answers no
  daily or weekly question (Product Scope rule 1) and is removed from the
  holdings target.
- Importing Flutter data into NSH is cut. The Flutter app is archived and
  retired directly; its full in-app backup export and the server-side D1
  database are the archives.

## Decision

- Archive the pre-retirement state at the `flutter-final` git tag, then
  remove `apps/mobile`, `apps/backend`, their CI workflows and Flutter-only
  tooling and docs from `main`.
- Move the securities catalog bundle from `apps/mobile/assets/catalog/` to
  `assets/catalog/`; the NSH client, the `finance-core` tests, the catalog
  build tool and the `securities-catalog` workflow read the new location.
- Keep `third_party/agent-runtime` (`llm-protocol`, `llm-client`) and
  `third_party/market-data-rs`; the NSH client and the domain crates use
  them.
- The NSH client stays local-only: no Sync, no login, no backend calls;
  local backups only.

## Cloud Resources (owner-side)

The Sync v3 deployment still exists in the owner's Cloudflare account. To
archive its server-side copy and then remove it:

```bash
npx wrangler d1 export naviwealth --remote --output=d1-archive.sql
```

The D1 database id is `77b6d007-be46-432a-a0f6-8c74e3124997` and the Worker
is `naviwealth-backend`; the ids are recorded here because
`apps/backend/wrangler.toml` is retired with the repository code. Export the
database, then delete the Worker and the D1 database through the Cloudflare
dashboard or `wrangler`.

## Consequences

- `main` describes only the NSH client and its Rust crates.
- Historical Flutter code, the Sync v3 backend, and the removed feature docs
  remain reachable at the `flutter-final` tag; they are not maintained.
- The rules that referenced the frozen Flutter client (parity, bug fixes) no
  longer apply; [Product Scope](../../product/product-scope.md) and the
  [roadmap](../../roadmap/roadmap-lifeos.md) are the only product SSOTs.
