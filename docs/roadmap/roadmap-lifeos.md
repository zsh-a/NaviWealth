# NSH Client Roadmap

Status: active sequencing SSOT; replaces the previous Now/Next plans.

Last reviewed: 2026-11-14.

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
   Implemented: favorites (save from a meal's page; the capture sheet
   lists them; tap logs with Undo, Edit removes with Undo, no long press)
   replace "log again today"; camera capture is the system picker's own.
3. **Weight.** Manual entry and a trend line, checked against an `nsh-base`
   plot proof (gaps, touch inspection, dark theme). Implemented: one entry per
   day in SQLite, a Today card with the weekly change and a 30-day line drawn
   by `nsh-base` `plot`/`line` (days without an entry are gaps), and a sheet
   to log, correct or delete (with Undo). Since the tab redesign the weight is
   a Today vital and a row in Records; the trend lives on Review. Dark theme
   and on-device rendering still need a look.
4. **Garmin Personal API.** Verify against Garmin's own docs and a real key
   (token exchange; sleep, resting HR, steps, HRV, stress, Body Battery and
   weight fields; history backfill; rate limits; revocation), then import
   daily summaries into `health-core` and show them on Today. Product Scope's
   Garmin list shrinks to what the API really provides. Verified on
   2026-11-13 with a real garmin.cn key: `POST …/personal-api-key/token`
   with `Authorization: ApiKey` returns a plain-text JWT (24 h, five read
   scopes); the global host answers 404 for a China key; daily summaries,
   sleep summaries and HRV ranges of 90 days work. Implemented: parsing in
   `health_core::garmin`, pulls and the `garmin_days` table in the NSH
   client, a Today card and a Settings key field. Remaining: rate limits are
   undocumented and unobserved; Garmin scale weight is untested.
5. **Health review and backup.** Weekly intake, macros, weight and Garmin
   averages on Review; automatic local backups and encrypted export/restore
   through a user-picked location. Implemented: seven-day health review with
   previous weeks; encrypted SQLite backups to an owner-configured WebDAV
   folder, once per day on open/resume and manually; confirmed restore with
   schema/record validation and transactional replacement. Timestamped files
   preserve previous backups. Backups made by hand carry meal photos; the
   daily one and credentials are without them. Real HTTP
   headless flows cover folder creation, upload, listing, restoration, errors
   and cross-day resume. Remaining: Android device verification and local
   file export (NSH 0.5.0 has no save or share dialog on Android). The implementation contract is in
   `apps/nsh-client/README.md`, “Health review and backups”.

6. **Tabs and capture (Product Scope, Interaction Model).** Implemented:
   the home with Today, Records and Review tabs beside one capture button;
   the capture sheet (photo meal, weight, favorites, manual); Today shows
   only today; Records lists every day with its total and filters; a meal's
   date chip moves it to another day. Recognition drafts: a photo's
   recognition runs under the app's root, leaving the review page keeps it
   as a draft (SQLite `meal_drafts`, not in backups) pinned on Today and
   atop Records; it can be confirmed, discarded with Undo, or tried again
   after a restart cut it short. Review: this week or this calendar month
   (stepping back), the daily average with its change from the period
   before, a bar per day against the goal line (amber past it, ink today),
   weight change and line, Garmin averages. Personal notes are stored by date, saved while typing and included in
   encrypted backups. Remaining: Android device verification.

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

## Phase 3 — Ledger (double-entry)

Started before Phase 2 by the owner's choice (2026-11-14): statements can
bring months of history at once, so the ledger does not wait for the
Flutter import.

- Scope: `finance-core` double-entry journal (accounts of five types,
  balanced postings in CNY minor units, derived balances), statement import
  as the main input, cross-source duplicates, balance checks, an optional
  monthly budget, the Assets tab, and screenshot drafts last.
- Steps, each shippable:
  1. `finance-core`: money, accounts, transactions and postings with the
     zero-sum invariant, balances, duplicate matching, mapping rules; the
     Alipay, WeChat XLSX and CMB parsers ported from Flutter.
     Implemented in `crates/finance-core`: the three corpus fixtures match
     the Flutter parsers row for row; rows keep payee, item, provider type,
     payment method and reference for mapping. Refunds, transfers and card
     repayments are still skipped as the Flutter parsers did; step 3 turns
     them into transfers and reversals and updates the manifests.
  2. SQLite tables (accounts, transactions, postings, mapping rules) in the
     client, restored with backups; manual entry; Records and Today show
     spending.
     Implemented: `lifeos-core` owns neutral SQLite opening, migrations,
     snapshots and atomic table replacement; `finance-core` owns the ledger
     repository. The capture sheet adds expense, income and transfer entries,
     with account creation, edits, guarded dismissal and delete/Undo. Today
     shows spending and mixed records; Records adds a Transactions filter and
     opens transaction-only dates from its calendar. Schema 7 backups include
     accounts, transactions, postings and mapping rules; older Health-only
     backups preserve the current ledger. Disk-open failures block startup
     instead of accepting records into memory. Remaining: Android device
     upgrade, editor/keyboard and mixed-domain backup/restore verification.
  3. Statement import: file picker, account and category mapping asked once,
     the review page, confirmation.
  4. Review: spending by expense account against the period before, the
     monthly budget.
  5. Assets tab: asset and liability balances, net worth, balance checks.
     Implemented by owner request (2026-11-14): fourth tab, account details,
     standalone account creation/rename, book net worth and 30-day trend,
     dated balance previews and atomic opening/adjustment confirmation.
     Zero-difference observations are retained without artificial postings;
     schema 9 backs up balance observations. Rename updates journal, mappings
     and recognition-draft references together. Remaining: Android device,
     system Back and real IME verification. Initial holdings are tracked below.
  6. Text/image capture into recognition drafts (brought forward by the owner
     on 2026-11-14). Implemented: one composer for money, meals and weight,
     natural-language corrections, shared durable drafts, explicit consent and
     atomic batch confirmation. Manual entry is secondary and its money
     editor has in-sheet pickers, a calendar and fixed actions. Statement
     import in step 3 remains pending. Remaining: real-model quality and
     Android keyboard/device verification.
- Exit: every transaction balances (property tests); exact money and
  rounding tests; statement corpus fixtures pass with pinned
  accepted/rejected counts; importing a statement twice adds nothing;
  nothing is saved without confirmation.

## Phase 4 — Holdings

- Initial increment implemented at the owner's request (2026-11-15), keeping
  capture simple: manually named CNY securities, existing-position opening,
  buy/sell/dividend with optional fees, exact moving-average cost and gains,
  atomic cash/journal updates, dated manual prices and valuation-aware net worth.
  Holdings are inline on Assets with one detail page and compact task sheets.
  The simplified overview groups cash accounts, open holdings and debts;
  Manage contains creation/closed history, while Asset changes owns the trend.
  Schema 10 backups validate positions against generated journal postings;
  unsafe deletion/backdated trades roll back. Core fixtures, headless flows,
  restart/restore and GTK light/dark small-screen checks cover this increment.
  Android device, system Back and real IME verification remain outstanding.
- Remaining: catalog lookup, a quote provider, FX and allocation. AI trade
  recognition is not included in this increment; the existing capture rejects
  trades. This initial implementation does not close the full phase.
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
