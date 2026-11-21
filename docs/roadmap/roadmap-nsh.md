# NSH Client Roadmap

Status: active sequencing SSOT; replaces the previous Now/Next plans.

Last reviewed: 2026-11-15.

## Contract And Baseline

[Product Scope](../product/product-scope.md) owns what is built;
[Personal Local Scope](../architecture/personal-local-scope.md) owns the
scope policy. This roadmap owns delivery order and gates.

Flutter (`apps/mobile`) and the Sync v3 backend are retired (2026-11-15); their source is
archived at the `flutter-final` tag and is not a parity target. The NSH 0.5.0
meal client and shared `navi-health` are the seed. Phases are dependency
gates, not dates.

## Phase 0 — Freeze And Decisions (done)

Product Scope and Personal Local Scope record
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
   Keystore (Personal Local Scope decision 5); the API key stays in app-private KV.
   Implemented in `apps/nsh-client/src/data/db.rs` with headless restart and
   migration flows; remaining evidence is an Android APK build (CI) and a
   device upgrade from a KV build.
2. **Meal logging polish.** Remove friction observed in daily use. Candidates,
   chosen by actual use rather than all built: camera capture besides the
   library, several views per meal as `navi-health` already supports, quick
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
   daily summaries into `navi-health` and show them on Today. Product Scope's
   Garmin list shrinks to what the API really provides. Verified on
   2026-11-13 with a real garmin.cn key: `POST …/personal-api-key/token`
   with `Authorization: ApiKey` returns a plain-text JWT (24 h, five read
   scopes); the global host answers 404 for a China key; daily summaries,
   sleep summaries and HRV ranges of 90 days work. Implemented: parsing in
   `health::garmin`, pulls and the `garmin_days` table in the NSH
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

## Phase 2 — Flutter Health Import (canceled)

Canceled 2026-11-15: Flutter retires directly after archiving its
backup; no data is imported. The owner keeps the full Flutter backup export
and the cloud D1 archive as historical records.

## Phase 3 — Ledger (double-entry)

Started before the (now canceled) Flutter import by the owner's choice
(2026-11-14): statements bring months of history at once.

- Scope: `navi-finance` double-entry journal (accounts of five types,
  balanced postings in CNY minor units, derived balances), statement import
  as the main input, cross-source duplicates, balance checks, an optional
  monthly budget, the Assets tab, and screenshot drafts last.
- Steps, each shippable:
  1. `navi-finance`: money, accounts, transactions and postings with the
     zero-sum invariant, balances, duplicate matching, mapping rules; the
     Alipay, WeChat XLSX and CMB parsers ported from Flutter.
     Implemented in `crates/navi-finance`: the three corpus fixtures match
     the Flutter parsers row for row; rows keep payee, item, provider type,
     payment method and reference for mapping. The original corpus parser
     contract stays pinned; the ledger-review path additionally retains refunds,
     transfers and repayments for explicit classification and counter-account
     correction instead of silently posting them as spending.
  2. SQLite tables (accounts, transactions, postings, mapping rules) in the
     client, restored with backups; manual entry; Records and Today show
     spending.
     Implemented: `navi-storage` owns neutral SQLite opening, migrations,
     snapshots and atomic table replacement; `navi-finance` owns the ledger
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
     Implemented: local CSV/XLSX/text files open a durable SQLite review with
     account creation/mapping, row selection, category/direction corrections,
     explicit transfer counterparties and refund review. Duplicate and skipped
     reasons remain visible; possible duplicates start unselected. Schema 11
     keeps the review across restart. Confirmation rechecks the journal and
     atomically posts selected rows plus mapping rules; a stale review must
     be confirmed again. No model or backend receives statement files.
  4. Review: spending by expense account against the period before, the
     monthly budget.
     Implemented: recorded-spending total, largest categories and transaction
     drill-down/editing. Partial current weeks/months compare the same elapsed
     days of the previous period; missing previous records remain explicit.
     Remaining: the optional monthly budget.
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
     editor has in-sheet pickers, a calendar and fixed actions. Structured
     statement files use the separate deterministic review in step 3.
     Remaining: real-model quality and
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
- Catalog and quote increment implemented (2026-11-15): offline code/name/pinyin
  lookup uses the securities catalog, downloaded from the rolling release;
  the picker checks automatically, daily after success and after a short cooldown on failure.
  Schema 12 separates replaceable listing data from explicit holding bindings.
  Existing manual holdings require confirmation; links preserve internal ids,
  accounts, labels, trades and cost. This first catalog increment supported
  mainland CNY stocks/ETFs; the multi-currency increment below extends it.
  Compressed/content hashes, schema, size, header count and checksum are verified
  before atomic catalog replacement; failures retain the offline catalog.
- Tencent is the single quote provider, through the shared market-data SDK.
  Foreground refresh checks each requested symbol or currency at most once per five minutes. Schema 13 stores dated provider marks separately from manual marks.
  Manual prices win on the same or newer day; stale/previous-close marks retain
  their provenance. Failed refreshes keep prior prices, and a changed binding
  atomically archives marks for the previous symbol before clearing the active
  cache, without touching manual data.
  Holdings, journal and net-worth calculations share the effective dated marks.
- Multi-currency increment implemented (2026-11-15): initial markets are
  mainland China, Hong Kong and US stocks/ETFs in CNY, HKD and USD. Account
  identity includes currency; holdings derive immutable currency from their
  accounts. Native trade prices, fees, cost and gains remain exact, with
  matching-currency cash settlement. Cross-currency transfers require both
  native amounts and balance each currency separately. Schema 14 adds dated
  HKD/CNY and USD/CNY rates to validated local backups. Manual rates take
  precedence over network observations on the same day. CNY overview conversion
  uses rates known by the valuation date; missing currencies are explicitly
  excluded from known value, and incomplete history is not plotted as complete.
  Other foreign markets/currencies and crypto remain unsupported.
- Historical observations increment implemented (2026-11-15): schema 15 keeps
  immutable raw OHLCV revisions and transactional price/FX audit; schema 16
  keeps immutable valuation observations. CN/HK/US daily history and HKD/USD
  reference rates backfill 30 days automatically, including when current quotes fail, with
  per-market dates, bounded requests and durable throttling. Daily closes and
  intraday marks retain distinct provenance; same-day manual values win.
  Rebinding preserves archived observations. Asset changes separates current
  recalculation from observations captured at an actual instant, with missing
  FX explicit. Audit records and valuation observations participate in validated
  atomic backup/restore; provider quotes and daily bars are excluded as
  re-fetchable caches. Tests cover baseline migration, record roundtrip, malformed
  backups, revision precedence and capture immutability. These are daily prices and observed
  valuations, not minute/tick bars, adjusted returns or retroactive snapshots.
- Remaining: Android TLS/physical-device, system Back, keyboard
  and migration verification. Android TLS and physical-device behavior remain
  unverified. AI trade recognition is not included; the existing
  capture rejects trades. This increment does not close the full phase.
- Scope: securities catalog, trades (buy, sell, dividend, fee), derived
  positions, average cost and gains, one quote provider, FX and
  net worth on Assets.
- Exit: derived positions match hand-computed fixtures, including partial
  sells and dividends; quote failures leave last prices marked stale.

## Phase 5 — Full Review, Archive, Retire Flutter

Updated 2026-11-15: the finance import is cut; Flutter retires
directly after archiving.

- Done in the repository (2026-11-15): `apps/mobile`, `apps/backend`, their CI
  and Flutter-only tooling removed; source archived at the `flutter-final`
  tag; securities catalog moved to `assets/catalog/`.
- Owner-side archive, before uninstalling the Flutter app: export the full
  in-app backup and keep it in two places; export the cloud D1 database
  (`npx wrangler d1 export naviwealth --remote --output=d1-archive.sql`; database
  id `77b6d007-be46-432a-a0f6-8c74e3124997`, Worker `naviwealth-backend`); then
  delete the Worker and D1.
- Remaining: complete Review with spending and net worth.
- Exit: restore from an NSH export on a clean install succeeds; two weeks of
  NSH as the only app.

## Remaining increments

Recommended sequence; this is planning, not a claim these items are implemented.

1. **Prove the daily Android path.** Upgrade from the released 0.6.0 APK on a
   physical device; verify migration to the current schema, real statement picking,
   mixed currency settlement, CN/HK/US TLS refresh, background/resume and keyboard/Back
   behavior. Restore an encrypted backup into a clean install and compare
   balances, quantities, prices and recorded valuations. Supply a native local
   export/share path so recovery does not require WebDAV configuration.
2. **Close one financial month.** Extend the existing Review with recorded
   spending, net-worth change and a drill-down explaining deposits/withdrawals,
   price changes, FX and balance adjustments. State missing data instead of
   labeling all net-worth movement as investment return. Keep four tabs and
   expose detail on demand; a monthly budget is lower priority.
3. **Weight body composition and the scale link.** Built ahead of the radio
   (implemented): `bodycomp` estimation in `navi-health` (Segal/Deurenberg
   from impedance, ported from the AFU-WL reference tool, fixture-tested), a
   per-day `body_metrics` table with backup validation, the Settings body
   profile (height, birth date, sex) and goal weight, BMI display, Review's 30/90-day
   windows and body-fat line.

   **Implemented 2026-11-18, physical acceptance pending:** a small TSX root
   mounts the existing Rust App and a scale sheet. An app-owned Kotlin/Gradle
   host exposes six session-scoped BLE operations through `host.call` and sends
   bounded events. The original build pinned NSH 0.5.0 Java classes and consumer rules,
   and packages the app-linked mixed `libnsh.so`, never the embedding archive's
   generic native library. `tool/build-nsh-android-host.sh` is the release build
   path; package id and signing policy stay unchanged.

   - Foreground scans request Android permissions on explicit user action,
     including precise location: a physical comparison revealed the target
     in 49 ms after removing `neverForLocation` and granting location.
     Location coordinates are never read. Scans
     expire, and stop with GATT on background/destruction. Session generations
     fence cancelled callbacks; writes are serialized with deadlines. The last
     successfully initialized scale is remembered in device-local preferences
     for one automatic connection attempt when the measurement sheet opens.
     A retained draft instead opens for review. There is no background service
     or reconnect loop. Dynamic readings update before a stable draft exists.
   - Birth date supplies current completed age, frozen with every measurement;
     legacy entered ages are retained honestly until replaced. Display-only
     BMI and estimated fat/fat-free/muscle/water masses reuse the measurement's
     captured profile and model version; preference changes never rewrite saved readings.
   - Algorithm selection supports legacy Segal plus experimental Wu 2015
     and Sun 2003. The default is device-local; switching a reviewed draft
     preserves original evidence, rotates its token and resets replacement
     confirmation. New algorithms have explicit applicability guards and
     versioned provenance, with legacy validation preserved. Sun uses its
     independent TBW equation; muscle remains approximate. Experimental
     device calibration and numerical accuracy are not physical acceptance
     evidence. Review keeps body-fat trends separate by algorithm.
   - `navi-health::scale` validates advertisement identity, packet lengths,
     checksums, stable weight and ADC evidence, preserving original grams.
     Rust creates profile/time commands. Missing valid impedance gives a
     weight-only draft; no BMI fallback is labeled as impedance-derived fat.
   - Rust owns the review token and persists completed drafts locally.
     Confirmation atomically writes weight, optional composition and provenance.
     Same-day replacement requires explicit confirmation and rejects intervening
     edits. Delete/Undo and backups reconcile measuring evidence; live sessions
     and unfinished drafts never leave the device in an exported backup.
   - Evidence: protocol fixtures and malformed/out-of-order cases; mixed
     TSX-to-Rust-to-host headless flows; storage rollback, replacement, Undo
     and backup tests; Android JVM session fencing, strict lint and actual
     arm64 APK assembly. A side-by-side emulator build opens the retained
     Rust pages and the TSX sheet. These are development evidence only.

   **Physical evidence 2026-11-18:** after correcting scan permissions, the
   AFU-WL-TZ-A1 was discovered in 49 ms and completed a DF/08 session with
   live/stable D5 and D6 impedance. The owner confirmed weight and body
   composition on screen. This is one successful foreground measurement.

   **Physical evidence 2026-11-19:** time-only initialization could leave
   the scale weighing without entering impedance measurement. Sending DF/08
   followed by the current D0 profile with impedance enabled restored the
   automatic transition in one real-phone session. Stable D5 was followed
   by D6 7.652 s later; the owner confirmed the scale's measuring sequence
   and the app's composition result. Repeated reconnect/cold-start behavior
   still needs separate verification; see the [Android host evidence](../../apps/nsh-client/android/README.md).

   **Remaining exit gates:** compare physical AFU-WL weight/impedance with the
   scale display and reference capture; verify protocol versions and profile
   initialization, permission denial/revocation, Bluetooth toggles and pause/
   resume on a real phone. Verify a signed in-place upgrade from the previous
   standalone APK preserves SQLite, photos and preferences, plus Back, picker,
   sharing, networking and encrypted restore. No physical-device gate is
   closed by emulator or headless tests.

   Protocol wire examples are independently implemented from the
   [AFU-WL reference](https://github.com/Mzdyl/ant-afu-welland-scale);
   [NSH 0.6.1 embedding](https://github.com/longbridge/nsh/blob/v0.6.1/docs/dev/embedding.md)
   defines the mixed Host Channel boundary.

4. **Conversational capture thread.** Implemented ahead of its gates
   ([capture conversation](../architecture/capture-conversation.md)): the
   composer's text or photo opens the thread as the first message; results,
   structured questions with tap-first options and corrections are turns
   inside the capture sheet, with the input pinned above the keyboard and
   confirm fixed. Requests carry the real message history; questions carry
   text and options in the client-local schema (`PROMPT_VERSION` bump); the
   transcript persists with the draft in `capture_drafts`. Confirmation,
   consent, draft durability and backup exclusion are unchanged. Product
   Scope's Interaction Model and `apps/nsh-client/DESIGN.md` describe the
   thread. Headless flows cover chip answering, multi-turn correction,
   reopen after restart and degraded bare-string questions. Image evidence now
   accepts up to four images per draft, including image-only follow-up turns;
   text-preserving PNG/JPEG preparation, per-turn replay and unresolved-question
   confirmation blocking are covered by headless tests. Decisions now use the
   single `ask_user` tool with editable options, explicit submission and durable
   tool-result continuation; no automatic tool loop runs. Remaining:
   real-model quality and Android keyboard/device verification.

## Operating Rules

- Product Scope decides features; a new feature needs a daily or weekly
  question and, for a new record type, a removal or written reason.
- Keep domain truth in `navi-finance` / `navi-health`; the UI only presents
  and confirms. New crates need a current caller.
- Pin NSH 0.6.1 behind local UI adapters; upgrade only with device evidence.
- Record headless tests and Android device evidence separately.
