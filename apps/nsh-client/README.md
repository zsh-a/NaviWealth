# NaviWealth native client (NSH)

NaviWealth's native client, with Rust pages and a small TSX hardware entry on [NSH](https://github.com/longbridge/nsh)
0.6.1. Capture turns a description or photos into reviewable transaction, meal,
weight, trade, balance, security price or review note drafts using the owner's model. The home has four tabs: Today
(spending, intake and vitals), Records (all history), Assets (accounts, book balances and net worth), and Review
(the week or month, with recorded spending and the attributed net-worth
change). The capture button accepts a description or image and
keeps a draft for confirmation. Settings keep each change as it is made;
manual entry and account management work without a model account. Design
standards and the motion inventory: `DESIGN.md`.

Meals, weights and Garmin days live on the device in
`naviwealth.sqlite`, photos in the app's data directory, the model and Garmin
keys under their own storage keys. Optional encrypted backups go to the owner's
WebDAV folder. Garmin data comes read-only from Garmin's
Personal API with the user's own key. Photos go straight from the device to the base
URL you configure (Anthropic Messages, OpenAI Chat
Completions, or OpenAI Responses); there is no NaviWealth relay.

```text
src/
  domain/   host account/capture composition and shared health re-exports
  data/     device storage, photos, local time and device network adapters
  ui/       the app's styled components over nsh-base, and its tokens
  pages/    the home (Today, Records, Assets, Review tabs, capture sheet), meal
            editing, Settings
  i18n/     English and Chinese copy
  preview.rs  desktop-only preview seeding for design review
App.tsx     mixed entry mounting the retained Rust App and scale sheet
tsx/        scale interaction and localized copy; no protocol or domain math
android/    Kotlin foreground BLE host and permissions, pinned NSH Java runtime
tests/      headless meal, weight, Garmin, review, backup and mixed scale flows
```

Meals, favorites, validation, repositories, nutrition, health-review calculations,
photo normalization and destination-bound consent live in `../../crates/navi-health`.
The client adapts those contracts to reactive signals and composes capture and
scale transactions with device-local evidence. Provider wire
formats live in `../../third_party/agent-runtime/crates/llm-protocol`; request
policy lives in `llm-client`. Unified capture uses the native `llm-reqwest` transport for streaming.
Single-meal recognition and the connection test use NSH platform fetch. Each saved estimate records its model and prompt version.

## Commands

```sh
cargo test                                  # unit tests and headless flows
cargo clippy --all-targets -- -D warnings
cargo fmt --check
nsh run                                     # GTK desktop window (phone-sized)
nsh run --target android                    # emulator/device dev host: build, debug-sign, install, launch
nsh check                                   # mixed TSX/native type check
nsh test tests/scale-mixed.test.ts           # mixed scale flow with local host fixtures
nsh test tests/share-mixed.test.ts           # shares from other apps through the TSX entry
bash ../../tool/build-nsh-android-host.sh release # app-owned Android host, unsigned arm64 APK
bash ../../tool/build-nsh-android-host.sh debug   # side-by-side com.naviwealth.app.bledev APK
```

From `apps/nsh-client`, install the local TS formatter with `npm ci` and run
`npm run format` before committing. `npm run format:check` runs the same check as
release CI. Both commands cover `App.tsx`, `tsx/`, `tests/scale-mixed.test.ts` and `tests/share-mixed.test.ts`.
Run `nsh check` for the native bridge and TSX type check.

Debugging on Android from WSL2 against a Windows-side emulator (adb over
mirrored loopback, SDK layout, pitfalls): see *NSH Android debugging from
WSL2* in `../../docs/development/local-development.md`.

The Android release APK is built by the manual GitHub Actions workflow
`nsh client` (`.github/workflows/nsh-client.yml`), uploaded as an artifact and
signed with the repository's fixed Android release key (`KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`). `tool/sign-nsh-apk.sh`
signs the app-owned Gradle host package using separate store/key passwords from environment
variables, verifies its certificate against the keystore, rejects debug
certificates, and removes temporary key material on exit. Missing secrets or
failed verification fail the build; only the signed APK is uploaded.

From v0.2.1 (build 4), releases keep this certificate for future in-place
updates. Older debug-signed APKs use different certificates and cannot be
overwritten by this release; preserve their data before migrating. Android
device upgrade and restore acceptance remains separate from CI signing checks.

The workflow's `diagnostics` input builds a diagnostic APK instead
(`NW_DIAG=1` at build time, artifact named `…-diagnostic-…`). Its Settings end
with keyboard diagnostics: shows, keyboard height, window and safe-area
changes, and late frames during the last keyboard motion. Release builds
compile none of it.

## AFU-WL scale

Body profile includes an **Estimation algorithm** preference for new scale
sessions: Segal BIA (legacy default), Wu 2015 (experimental), and Sun 2003
(experimental). The scale sheet exposes the current choice and can recalculate
an unsaved measurement from its original grams, ADCs and frozen profile.
This changes only the draft, rotates its review token, and never reconnects,
changes the default, or rewrites history. Failed recalculation keeps the old
review intact. Out-of-range experimental models offer another algorithm or
explicit weight-only saving rather than silently using Segal. Sun estimates
water independently; muscle remains a coarse proportional estimate.
The device's converted input is not verified against these models' original
measurement setup. Wu is limited to adults aged 18–75, 39–125.5 kg, BMI
15.9–43.1; Sun is limited to adults aged 18–94. Confirmed model versions
survive backup/restore, and Review plots each algorithm separately.

Connect scale is available in Settings, Today’s Body metrics overview and the
manual weight editor. Today shows a full-width dated weight, weekly change,
body fat and BMI; composition joins only on that weight’s day. Garmin vitals
use a separate equal-width row. The overview reveals muscle, water, goals and
original measurement details without crowding the daily summary. Complete
height, date of birth and sex first. Birth date supplies completed age on
the local measurement date; legacy entered ages remain labelled until replaced.
Enable system Location and allow precise location
and Nearby devices when prompted; these permissions are needed to receive
this scale's Bluetooth advertisements, without reading location coordinates.
On first use, lightly tap the AFU-WL to wake it, scan
and select it. After a successful connection and initialization, the app remembers
the scale on this device. Next time, wake it and open the measurement sheet:
it makes one foreground connection attempt without scanning. A failed attempt
offers **Connect saved scale** or **Find another scale**. A retained draft takes
priority and opens for review without reconnecting. Step onto the scale when
prompted; live readings update without creating a save token until stable.
Closing or backgrounding disconnects; there is no background reconnect loop.
Review weight and optional impedance-derived composition before explicitly
confirming the measurement. Rust validates identity and packets,
creates profile/time commands and owns review tokens. Same-day replacement has
a second confirmation; closing keeps a completed local draft, while Discard
removes it. Manual weight changes and Undo reconcile composition and provenance.
BLE data stays on-device and never enters a model request.
Measurement details derive BMI, fat mass, fat-free mass, muscle mass and water
mass from that measurement's original grams, captured profile and estimates.
These are display-only and do not change stored evidence or old algorithms.
They are not guaranteed to match the manufacturer's proprietary composition
model; unknown visceral-fat/body-age/protein scores are not fabricated.

Use NSH CLI **0.6.1** for mixed checks and builds. The host build script pins the
matching Java inputs and extracts the app-linked native library from the NSH
mixed package. Plain `nsh run --target android` uses the generic development
host and does not provide these BLE handlers. The production unsigned APK is
`android/app/build/outputs/apk/release/app-release-unsigned.apk`; signing remains
in CI. Physical scale and signed upgrade acceptance remain open in the roadmap.

## Health review and backups

The Review tab shows a locale-aligned calendar week (Monday for Chinese and
ISO locales) or a calendar month, up to today, with earlier periods one step back; the daily average is compared
with the period before and each day's bar with the goal. Intake and macros average only days with logged meals; missing
days are unknown. Weight change compares trailing seven-calendar-day means at the period's start
and end; Today uses the same comparison seven days apart. Each mean requires
at least three measured days and a measurement in the last three days. Sparse
or stale windows and gaps longer than a week produce no delta. Missing days
are never filled in. Records All shows the day's weight as a chip in its header that opens the editor;
the Weight filter keeps individual measurements without deltas.
Garmin averages each measurement over the days that contain it.

Settings → Backup also accepts an HTTPS WebDAV folder (for example Jianguoyun,
Nextcloud or Synology), account, app password and a backup passphrase of at
least eight characters. Save and back up applies immediately. With this set
up, opening or resuming the app makes one backup per local calendar day; this
is a foreground task, not an Android scheduled background job. Manual backups
can be made any time. Each file has a new timestamped name and a conditional
PUT prevents replacing an existing file. No automatic remote deletion occurs.

Backups contain confirmed meals, favorites, notes, weights, composition and
scale provenance, imported Garmin days, the ledger, holdings, dated manual
prices/FX, price audit and valuation observations. Recognition threads, meal
review drafts, scale drafts and local revision guards are excluded. Provider
quotes and daily bars are excluded as re-fetchable caches. Statement-import
reviews remain part of the finance backup contract. Save and back up
(by hand) also carries the meal photos
of meals and favorites, named `…-photos.nwbk` and marked "With photos" in the
restore list; the daily automatic backup leaves photos out so it stays small.
Restoring writes back the photos a backup carries and keeps photos already on
the device. **Model/Garmin keys, settings, WebDAV credentials and the
passphrase are excluded.** The passphrase is kept in app-private storage and must also be
saved elsewhere to restore on a fresh install. The `NWBK` format uses Argon2id
(32 MiB, three passes) and XChaCha20-Poly1305 with an authenticated header.
Version 2 encrypts a bundle (database plus photos); version 1 files, the
database alone, still restore.

Restore lists the ten newest files and asks before replacing records. Decryption,
schema and record validation happen before one transaction replaces the data.
Photos are written and synced first without overwriting existing files. A
same-name photo with different contents receives a new name in the restored
records. Photo or database failure removes newly staged files and preserves
current records and photos. A process crash can leave unreferenced files for
the next orphan sweep; SQLite and the filesystem are not one transaction.
Wrong passphrases, changed files, invalid records and newer schemas leave
existing records intact. Settings and credentials stay on this device. Older
daily-name backups remain readable.

WebDAV uses a Rust `ureq` adapter on a blocking worker for the required
HTTP extension methods. TLS uses WebPKI roots; redirects never carry credentials
onward. Plain HTTP is limited to loopback for isolated tests. The backup flows
start their own HTTP server and exercise real PUT/MKCOL/PROPFIND/GET requests;
they need no live service or personal key.

Backup files need no WebDAV. The backup page leads with the passphrase, then
Export backup file and Restore from file…, each using the typed passphrase or
else the kept one. Export seals the same `NWBK` bundle (meal photos optional,
on by default) into the app's `exports` folder, keeping only the newest file,
and hands it to the system share sheet (`share` capability, NSH's
`FilesProvider`); without a share sheet, as on desktops, a save dialog writes a
copy. A dismissed sheet is not an export; a completed one is shown as Last
exported on the page and, while automatic backups are off, on the Settings row.
A typed passphrase that sealed an export becomes the kept one; one that opened a
restored file is kept only when none was, so a restore never changes the
passphrase later backups use. A picked file is decrypted and validated before the
same atomic replacement as a WebDAV restore. `tests/backup_file.rs` covers share
and save, fresh-install restore, missing passphrases, wrong passphrases and
malformed files. Android share-sheet behavior still needs device evidence.

## Desktop previews

`src/preview.rs` (not compiled for phones) seeds a fresh data directory from
environment variables, so each state can be opened and captured without the
picker or a real account:

```sh
XDG_DATA_HOME=$(mktemp -d) \
NW_PREVIEW=account,trust,meals,goal NW_PREVIEW_BASE_URL=http://127.0.0.1:8799/v1 \
NW_PREVIEW_ROUTE=new:/path/to/meal.jpg cargo run
```

`NW_PREVIEW` also takes `dark`/`light`, `drafts` (two recognition drafts) and `favorites` (the first seeded meals
saved as favorites); `NW_PREVIEW_ROUTE` takes `manual`,
`edit`, `settings`, `model`, `review`, `review-month`, `records`, `records-jump`, `records-day` and `capture`; `NW_PREVIEW_PHOTOS` lists photos for the seeded meals;
`NW_PREVIEW_EDITOR=1` opens the first food's editor once results arrive.

Review notes are single lines (up to 280 characters), saved automatically on
their date. Review shows the latest note in its week or month for editing and
earlier notes above it. Clear the field to remove a note. Notes survive restart
and are included in encrypted backups.


## Ledger: manual records and storage

The capture sheet's **Log transaction** action records an expense, income or
transfer. Amounts are exact CNY, HKD or USD minor units; more than two decimal places are
rejected. Choose a category and an asset/liability account, or name a new own
account within the draft. No account or posting is written until Save succeeds.
The sheet edits the date/time, payee and note; dismissal asks before discarding
changes. Existing rows open the editor; Delete offers Undo.
Each own account has one currency. Cross-currency transfers record both sent
and received amounts and balance each currency separately. Spending remains
in its original currency in Today, Records and Review.

Today combines meals and transactions in time order and shows today's spending
beside intake once the ledger has records. Income and transfers do not count as
spending. Records groups both kinds by date, offers a Money filter, and
its calendar includes days containing only transactions.

`crates/navi-storage` provides neutral SQLite opening, versioned migrations,
snapshots and atomic table replacement. `finance::repository` owns account,
transaction, posting and mapping-rule SQL, validation and confirmed writes. The
client's `data::finance` only mirrors successfully committed records into UI
signals. Opening an unreadable/unwritable or newer database blocks startup;
only a headless host without a data directory uses memory storage.

Schema 7 adds the financial tables. New encrypted backups restore Health and
Finance together, rejecting unbalanced entries, missing account references and
invalid source identities before replacing current rows. Health-only backups
(schema 1–6) restore Health while preserving the current ledger. Restore remains
explicitly confirmed. Balances and spending are derived, never stored as truth.
Statement import is implemented; the optional monthly budget remains planned.
The initial holdings increment is described below.

Desktop previews accept `NW_PREVIEW=account,meals,finance,light` (or `dark`) and
`NW_PREVIEW_ROUTE=transaction` / `transaction-new` for the editor, in addition
to `records` and `capture`. These seed synthetic entries only in the selected
preview data directory. Headless tests verify behavior; they are not Android
device evidence.


## Model API protocols

Settings → Recognition model uses one form with a compact API protocol picker:
Anthropic,
OpenAI Chat (`/chat/completions`) and OpenAI Responses (`/responses`). The URL
is the API base (for example `https://api.openai.com/v1`); the chosen protocol
appends its endpoint. The owner supplies the model name. Existing Chat profiles
keep their persisted identity; a protocol change requires fresh recognition
consent, while typed custom URLs, model names and keys are preserved.

Responses uses `store: false` and sends the locally kept input history. Native
output items, including encrypted reasoning and function calls, stay with the
draft and replay before the matching `function_call_output`. It does not rely
on server-stored conversations or `previous_response_id`. Images are input
image items, and the same draft/confirmation rules apply to all three APIs.
Unified capture supports Responses streaming and checks the terminal event before enabling review. Connection tests use the selected protocol's own endpoint.
Desktop previews accept `NW_PREVIEW=account,responses,light` and
`NW_PREVIEW_ROUTE=model` to inspect the selected protocol.

## Text and image capture

The global capture button opens a single description/image composer. The
owner's model can draft transactions, meals, weight, trades, actual balances,
manual security prices and review notes. Corrections include the current edited
records and can refine a mixed batch. Manual entry is a
secondary disclosure. A purchase with a price does not imply food consumption.

- `ask_user` is the only model tool: it suspends recognition for owner decisions,
  each with a reason, required flag and unselected choices with descriptions.
  Choices are durable, editable and submitted together. Text and supporting
  images can answer too. The call ID and original assistant blocks are kept
  for a matching tool-result continuation; no automatic tool loop runs. Final
  model JSON contains records and a nullable navigation destination. Legacy stored question turns remain readable.
- `domain/capture.rs` composes the envelope and delegates money, nutrition and
  weight validation to their owning domains. `finance::recognition`
  rejects unsupported currencies, imprecise money and wrong account kinds;
  missing fields remain editable, unconfirmed values.
- `data/capture.rs` keeps input/results in SQLite `capture_drafts` (schema 8),
  runs recognition under the app root, and atomically consumes the draft while
  writing its whole batch. Neither recognition nor correction writes records.
  Database failures retain the draft for retry, with no partial batch. The receipt
  offers View and an atomic Undo that checks for intervening edits.
- Consent covers input text, attached images and ledger account names;
  old photo-only trust does not grant the broader consent. The model account
  fingerprint scopes remembered consent. Typing previews have an independent
  opt-in and optional model name at the same endpoint. Previews send text
  after a typing pause. Photos accompany an explicitly submitted turn. A
  separate option includes recent transactions, meals, weight, favorite
  meals and held security identities. Both settings default off.
- Provider events can expose provisional cards during a request. After the
  terminal reply the owner can inspect field evidence, approve a suggested
  account, edit a value or remove an individual card.
- Today and Records expose the same drafts. Interrupted runs can be retried
  after restart. Capture accepts up to four images per draft, including image-only follow-up
  answers. Images stay with their original owner turn during history replay;
  unsent evidence is removable and survives closing. Capture normalization
  preserves up to a 4096 px edge / four megapixels / 2 MiB per image, preferring
  lossless PNG and using high-quality JPEG when necessary. Pending model
  questions, unresolved tool continuations and unsent evidence block confirmation.
  Inputs are never logged.
- Manual money has in-sheet selection views, a calendar, secondary details,
  and last-confirmed choices. Task sheets keep their action above the keyboard:
  they plan for it when they open, so it lifts the whole sheet natively
  without resizing it.

`tests/capture.rs` exercises natural-language correction, missing-account
blocking, atomic multi-domain confirmation, a real SQLite failure and retry,
restart, and invalid model output. The existing meal/draft flows now use the
unified composer; finance tests retain exact posting/balance assertions.
Desktop visual previews include `capture`, `capture-ready`, `capture-missing`,
`capture-ask` (a pending tool decision),
`transaction` and `transaction-new`. Set `NW_PREVIEW_CAPTURE_IMAGES` to colon-separated
image paths with `capture-ready` to inspect staged evidence. GTK previews are
not Android evidence.

## Accounts and Assets

Assets leads with one light overview surface: net worth uses a prominent whole
amount with quieter currency/decimals, followed by two compact asset/debt totals.
The exact complete amount remains available to assistive technology. Below it, cash
accounts, open holdings and debts form a flat list with neutral type icons and
spacing instead of repeated dividers. Rows show names and amounts; unverified
accounts and manual-price/cost valuation status remain visible. Quantity,
unit cost and normal balance-check dates live in details. Amounts use digit
grouping for scanning. Without holdings, totals use book balances.

Manage opens account/holding creation and closed-holding history. Fully closed
positions leave the overview automatically and return after another purchase.
Account and holding creation replace the content of the same management sheet;
security search stays inside the holding task. Back preserves the current
draft when leaving a picker. A new account stays on Assets with a persistent
Set opening balance action until it has a posting or balance check. An account
with a confirmed zero displays its zero balance.
The global capture action is a 56-point ink circle with a line plus, centered
beside the dock. Its accessible name remains New entry / 新记录.
Opening a change amount carries the overview’s start and end dates into the
chart and opens the breakdown. The ordinary 30-day window includes today. Valuation basis expands for details on how
backdated entries, prices and balance adjustments change the estimates.
Account details show dated entries, with older entries loaded in batches.
The owner can create asset/liability accounts and rename them without merging
accounts. Renaming updates postings, import mappings, balance observations and
saved recognition references together; a running recognition must finish first.

Balance checking asks only for the actual balance/debt and date. Positive debt
means money owed; negative debt means a credit balance. A separate preview shows
the book value, actual value and difference before confirmation. The domain
repository recomputes the expected balance inside the transaction and rejects a
stale preview. It writes a balanced opening/adjustment entry against equity and a
balance observation atomically. Zero difference saves only the observation;
balance checks never change income/spending. Confirmed balance entries can be
inspected and revoked from all timelines. Revocation and Undo remove or restore
their postings and balance observations atomically. Corrections use another
balance check. Ordinary transactions expose Delete on the editor's main header,
with a saved-record confirmation and retryable Undo; a changed record or account
cannot be overwritten by an old confirmation or Undo action.

Schema 9 adds `finance_balance_checks` to encrypted backup/restore and validation.
`finance::assets` owns book totals and debt presentation;
`finance::holdings` replaces security book cost with dated market values.
The NSH pages only display those values.

Previews: `NW_PREVIEW=account,meals,finance,assets,light` with
`NW_PREVIEW_ROUTE=assets`, `assets-manage`, `asset-history`, `asset-account`, or
`asset-balance`; `assets-empty`
with only `NW_PREVIEW=light` checks the empty state. `NW_PREVIEW_WIDTH` and
`NW_PREVIEW_HEIGHT` set the desktop viewport. GTK light/dark captures and
headless 360×640/1.3 text-scale/simulated-IME checks are development evidence;
Android device and real keyboard verification remain outstanding.

## Simple holdings

Holdings live inside Assets, with no additional tab. Add an existing position
using a name/code, quantity and unit cost, or record a purchase against a cash
account. A holding opens its quantity, remaining cost, unrealized gain and
trade history. Buy, sell and cash dividend share one compact editor; date and
fees are secondary details. Deleting a trade requires confirmation and replays
later trades; a deletion or backdated sale that would oversell is rejected.

The supported markets are mainland China, Hong Kong and the US, with CNY, HKD
and USD accounts and holdings. Offline catalog search supports code, name,
pinyin and aliases; verified catalog updates come from GitHub Releases.
Manual holdings remain available. Trades settle through matching-currency cash
accounts; a holding's currency stays fixed after creation.

Tencent provides dated quotes. Unpriced positions explicitly use native cost;
known prices replace cost and are never applied to earlier days. Assets converts
to CNY using dated rates. Frankfurter ECB rates update automatically and can be inspected under Manage → Prices & rates. Same-day manual quotes/rates take priority. Missing rates leave currencies
visibly excluded from the known total; historical dates with missing rates appear as gaps
in the trend, with the affected currencies and dates shown for the selected window. Schema 14 includes exchange rates in backups. Other
currencies and crypto are not supported; AI trade recognition remains excluded.

`finance::holdings` owns six-decimal integer quantities/prices, cent rounding,
moving-average cost, realized gains, dividends and journal postings. Buy fees
enter cost; sale/dividend fees reduce proceeds. Existing positions do not deduct
cash. Trade and cash writes commit together. Internal security cost accounts
cannot be selected or altered as cash accounts. Account renaming also updates
trade references. Schema 10 includes securities, trades and prices in encrypted
backups; restore rejects disagreement between trades and generated journal rows.

Meaningful checks cover partial/full sales, dividends/fees, cash rename,
historical valuation, failed writes/retry, unsafe history edits, restart and
backup validation. GTK previews use `NW_PREVIEW=account,meals,finance,assets,holdings,light`
and routes `holdings`, `holding`, `holding-new`, `holding-trade`, `holding-price`.
`closed-holdings` seeds a liquidated holding for the history page; adding
`unpriced` to the preview flags leaves positions visibly valued at cost.
These previews and headless checks are not Android device evidence.


## Price history and recorded valuations

Schemas 15–16 add local immutable raw daily OHLCV revisions, quote/FX audit
records and observed valuation snapshots. Tencent supplies unadjusted daily
bars for mainland China, Hong Kong and US listings; Frankfurter ECB supplies
dated HKD/CNY and USD/CNY reference rates. Values remain integer millionths,
with native currency retained. The day is the market's local trading date.
Unfinished current-market days are excluded conservatively, even after the
session closes; current quotes remain separately labeled. Historical raw daily
closes supersede same-day intraday marks; same-day manual prices take priority.

While the app is active, opening it, resuming, adding a required currency or binding,
and a five-minute timer schedule the required quotes and rates. Opening Prices & rates
also requests both supported foreign rates. A single worker coalesces requests and
backfills the last 30 days independently of current quote success. Fetches are single-flight and bounded to
one year plus a ten-day prior-price warm-up per request, with a six-hour success TTL and five-minute failure TTL;
FX requests cover portfolio currencies and the pairs displayed in the rates view. A ten-day price/FX warm-up permits prior
published rates across weekends without using future rates. Empty responses
remain missing data, not a coverage guarantee. No minute/tick history or
corporate-action-adjusted return series is implemented.

Manage → Prices & rates brings current exchange rates, daily closes and saved changes
into one page. Select a currency pair to inspect its dated trend. Opening this view also requests
recent history for both supported pairs. Holdings show their observed unit prices
in the trading currency below quantity, cost and unrealized gain. A single
quote shows its value and provenance. Trades can create and select a cash
account in their own currency. Dividend amounts and unit prices keep separate
draft values. The full charts support dragging, keyboard inspection
and switching date windows. Recent windows end today, including for a stale
quote. All reaches the earliest available history. The overview independently
compares today's valuation with the valuation exactly 30 days ago. Expand a daily close for OHLC,
source and revisions. Holding details open the same page filtered to the security.
A changed binding clears only its active network marks: the old observations
and symbol-keyed daily bars remain in the archive. Migration records existing
marks/rates as baselines at migration time, never inventing original fetch times.
Unchanged values add no audit revision. Manual FX rates keep same-day priority.

Asset changes has two views, Historical estimates (current ledger and dated
prices and rates) and Net worth snapshots (observations at the shown instant). Automatic capture
runs once per local day when the ledger has transactions or trades, using the
stored observations available after the foreground quote check. Cash-only CNY
portfolios are captured locally. A snapshot copies native balances, positions, prices, actual rates,
calculation inputs and integrity checksums; later edits never rewrite it.
Missing FX leaves a gap on the chart. Schema 19 indexes the existing snapshot
rows for daily lookups and chronological paging. The history view reads 30
summaries per page and loads the full observation when its row expands.
Quote refreshes and history backfills publish holdings and FX together.
Opening a database and restoring a backup still validate the complete ledger. Recorded values
are not end-of-day closing values; past observations are never fabricated.

Backups include audit records and valuation observations. Provider daily bars
and current provider quotes are omitted and rebuilt on demand after restore.
Migration, record roundtrip, malformed history/audit/snapshot rejection and
atomic restore are checked alongside revision precedence, manual overrides
and immutable valuation tests. Live
public TLS checks cover CN 510300, HK 00700, US AAPL/BRK.B and both FX pairs;
Android platform behavior still requires device verification.

Desktop preview: add `history` to the existing `holdings,multicurrency,fx`
flags and use `NW_PREVIEW_ROUTE=prices-and-rates` or `asset-history`.
