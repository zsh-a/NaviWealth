# NSH Client Roadmap

Status: active sequencing SSOT; replaces the previous Now/Next plans.

Last reviewed: 2026-11-13.

## Contract And Baseline

[Product Scope](../product/product-scope.md) owns what is built.
[ADR 0002](../architecture/adr/0002-personal-local-scope.md) (personal,
local-only, reduced rewrite) and [ADR 0001](../architecture/adr/0001-nsh-client-migration.md)
(NSH direction, Flutter freeze, Android only) own the architecture. This
roadmap owns delivery order and gates.

Flutter (`apps/mobile`) is frozen: bug fixes only. It is not a parity target.
The NSH 0.5.0 meal client and shared `health-core` are the seed. The archived
[Finance roadmap](roadmap-finance.md) and
[product-direction study](product-direction-and-demand-validation.md) do not
authorize work. Phases are dependency gates, not dates.

## Phase 0 — Freeze And Decisions (done)

ADR 0001 merged with PR #336 on 2026-11-13; Product Scope and ADR 0002 record
the scope reduction. The Agent Runtime submodule points at its `main`.

## Phase 1 — Health Experience On The Meal Client

Polish Health first, starting from the current NSH meal client, until the
owner logs meals and weight only in NSH. Ledger and holdings wait. Only build
the tabs that have content: Today, Records (meals and weight) and a
health-only Review; Assets arrives with Phase 3.

1. **Meal storage in SQLite.** Meals move from NSH KV (5 MB, capped at
   3,000 meals) to `naviwealth.sqlite` in the app's private directory, one
   row per meal, with versioned migrations; legacy KV meals move once in a
   transaction and the entry is removed after commit. No SQLCipher or
   Keystore (ADR 0002 decision 5); the API key stays in app-private KV.
   Implemented in `apps/nsh-client/src/data/db.rs` with headless restart and
   migration flows; remaining evidence is an Android APK build (CI) and a
   device upgrade from a KV build.
2. **Meal logging polish.** Remove friction observed in daily use. Candidates,
   chosen by actual use rather than all built: camera capture besides the
   library, several views per meal as `health-core` already supports, quick
   re-log of recent foods or meals, a daily energy/macro goal, undo after
   delete, and history beyond the four-week strip. Each change keeps the
   existing consent, estimate-review and confirm-before-save rules.
3. **Weight.** Manual entry and a trend line, checked against an `nsh-base`
   plot proof (gaps, touch inspection, dark theme).
4. **Garmin Personal API.** Verify against Garmin's own docs and a real key
   (token exchange; sleep, resting HR, steps, HRV, stress, Body Battery and
   weight fields; history backfill; rate limits; revocation), then import
   daily summaries into `health-core` and show them on Today. Product Scope's
   Garmin list shrinks to what the API really provides.
5. **Health review and backup.** Weekly intake, macros, weight and Garmin
   averages on Review; automatic local backups and encrypted export/restore
   through a user-picked location.

- Exit: the owner uses NSH as the only meal/weight app for two weeks; meals
  survive restart, upgrade and restore; wrong-key or corrupted backups are
  rejected without touching current data; Garmin failures keep the last data
  visible; `nsh-testing` flows and an Android device run pass.

## Phase 2 — Flutter Health Import

- Scope: decide whether Rust can read the Flutter backup archive or whether a
  minimal Flutter exporter is needed; import meals (with photos where present)
  and weight once into NSH.
- Exit: imported meal and weight counts and daily totals match the Flutter
  export; importing twice creates no duplicates.

## Phase 3 — Ledger

- Scope: `finance-core` accounts, transactions, categories, optional monthly
  budget; Alipay, WeChat XLSX and CMB statement import with duplicate review;
  receipt/screenshot recognition drafts in Records; the Assets tab with
  account balances.
- Exit: exact money and rounding tests; statement corpus fixtures pass with
  pinned accepted/rejected counts; nothing is saved without confirmation.

## Phase 4 — Holdings

- Scope: securities catalog, trades (buy, sell, dividend, fee), derived
  positions, average cost and gains, one quote provider, FX, allocation and
  net worth on Assets.
- Exit: derived positions match hand-computed fixtures, including partial
  sells and dividends; quote failures leave last prices marked stale.

## Phase 5 — Full Review, Finance Import, Retire Flutter

- Scope: complete Review with spending and net worth; import kept Finance
  records from Flutter; archive the full Flutter backup; retire Flutter,
  FRB / `lifeos_native`, the Sync v3 backend and their CI.
- Exit: imported balances and position quantities match the Flutter export;
  restore from an NSH export on a clean install succeeds; two weeks of NSH as
  the only app.

## Operating Rules

- Product Scope decides features; a new feature needs a daily or weekly
  question and, for a new record type, a removal or written reason.
- Keep domain truth in `finance-core` / `health-core`; the UI only presents
  and confirms. New crates need a current caller.
- Pin NSH 0.5.0 behind local UI adapters; upgrade only with device evidence.
- Record headless tests and Android device evidence separately.
