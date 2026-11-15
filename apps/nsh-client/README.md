# NaviWealth native client (NSH)

NaviWealth's native client, written in Rust on [NSH](https://github.com/longbridge/nsh)
0.5.0. Its first page is HealthOS meal logging: choose a photo of a meal, allow
it to be sent to your own vision model, review the estimated foods and amounts,
and save. The home has four tabs: Today (spending, intake and vitals), Records
(all history), Assets (accounts, book balances and net worth), and Review
(the week or month). The capture button accepts a description or image and
keeps a draft for confirmation. Settings keep each change as it is made;
manual entry and account management work without a model account. Design
standards and the motion inventory: `DESIGN.md`.

Meals, weights and Garmin days live on the device in
`naviwealth.sqlite`, photos in the app's data directory, the model and Garmin
keys under their own storage keys. Optional encrypted backups go to the owner's
WebDAV folder. Garmin data comes read-only from Garmin's
Personal API with the user's own key. Photos go straight from the device to the base
URL you configure (Anthropic Messages API or an OpenAI-compatible Chat
Completions API); there is no NaviWealth relay.

```text
src/
  domain/   host-owned meals/account and shared health domain exports
  data/     device storage, photos, local time, thin NSH fetch Transport
  ui/       the app's styled components over nsh-base, and its tokens
  pages/    the home (Today, Records, Assets, Review tabs, capture sheet), meal
            editing, Settings
  i18n/     English and Chinese copy
  preview.rs  desktop-only preview seeding for design review
tests/      headless meal, weight, Garmin, review and backup flows
```

Meal recognition, catalog nutrition, photo normalization and destination-bound
consent live in `../../crates/navi-health`. Provider wire
formats live in `../../third_party/agent-runtime/crates/llm-protocol`; request
policy lives in `llm-client`. NSH supplies its platform fetch transport rather
than the reqwest adapter. NSH 0.5.0 returns whole response bodies; recognition does not require
streaming. Each saved estimate records its model and prompt version.

## Commands

```sh
cargo test                                  # unit tests and headless flows
cargo clippy --all-targets -- -D warnings
cargo fmt --check
nsh run                                     # GTK desktop window (phone-sized)
nsh run --target android                    # emulator/device dev host: build, debug-sign, install, launch
nsh package --target android --abi arm64-v8a   # device APK; needs the Android SDK, NDK and a JDK
nsh package --target android --abi x86_64   # x86_64 emulator APK; --run also installs and launches
```

Debugging on Android from WSL2 against a Windows-side emulator (adb over
mirrored loopback, SDK layout, pitfalls): see *NSH Android debugging from
WSL2* in `../../docs/development/local-development.md`.

The Android release APK is built by the manual GitHub Actions workflow
`nsh client` (`.github/workflows/nsh-client.yml`), uploaded as an artifact and
signed with the repository's fixed Android release key (`KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`). `tool/sign-nsh-apk.sh`
re-signs the NSH package using separate store/key passwords from environment
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

Settings → Backup accepts an HTTPS WebDAV folder (for example Jianguoyun,
Nextcloud or Synology), account, app password and a backup passphrase of at
least eight characters. Save and back up applies immediately. With this set
up, opening or resuming the app makes one backup per local calendar day; this
is a foreground task, not an Android scheduled background job. Manual backups
can be made any time. Each file has a new timestamped name and a conditional
PUT prevents replacing an existing file. No automatic remote deletion occurs.

Backups contain the SQLite database: meals, favorites, notes, weights and
imported Garmin days. Save and back up (by hand) also carries the meal photos
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
Wrong passphrases, changed files, invalid records and newer schemas leave
existing records intact. Settings and credentials stay on this device. Older
daily-name backups remain readable.

WebDAV uses a Rust `ureq` adapter on a blocking worker, since NSH 0.5's
Android `HttpURLConnection` and default headless transport restrict WebDAV
extension methods. TLS uses WebPKI roots; redirects never carry credentials
onward. Plain HTTP is limited to loopback for isolated tests. The backup flows
start their own HTTP server and exercise real PUT/MKCOL/PROPFIND/GET requests;
they need no live service or personal key. Local file export is not
implemented: NSH 0.5.0 has no save or share dialog on Android.

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
Statement import and budgets are subsequent increments. The initial holdings
increment is described below.

Desktop previews accept `NW_PREVIEW=account,meals,finance,light` (or `dark`) and
`NW_PREVIEW_ROUTE=transaction` / `transaction-new` for the editor, in addition
to `records` and `capture`. These seed synthetic entries only in the selected
preview data directory. Headless tests verify behavior; they are not Android
device evidence.


## Text and image capture

The global capture button opens a single description/image composer. The
owner's model returns money, meal or body-weight drafts; a short correction
updates the complete draft without creating a chat history. Manual entry is a
secondary disclosure. A purchase with a price does not imply food consumption.

- `domain/capture.rs` composes the envelope and delegates money, nutrition and
  weight validation to their owning domains. `finance::recognition`
  rejects unsupported currencies, imprecise money and wrong account kinds;
  missing fields remain editable, unconfirmed values.
- `data/capture.rs` keeps input/results in SQLite `capture_drafts` (schema 8),
  runs recognition under the app root, and atomically consumes the draft while
  writing its whole batch. Neither recognition nor correction writes records.
  Database failures retain the draft for retry, with no partial batch.
- Consent covers input text, the attached image and ledger account names;
  old photo-only trust does not grant the broader consent. The model account
  fingerprint scopes remembered consent. There is no backend or agent loop.
- Today and Records expose the same drafts. Interrupted runs can be retried
  after restart. Photos are re-encoded before use; inputs are never logged.
- Manual money has in-sheet selection views, a calendar, secondary details,
  and last-confirmed choices. Task sheets keep their action above the keyboard:
  they plan for it when they open, so it lifts the whole sheet natively
  without resizing it.

`tests/capture.rs` exercises natural-language correction, missing-account
blocking, atomic multi-domain confirmation, a real SQLite failure and retry,
restart, and invalid model output. The existing meal/draft flows now use the
unified composer; finance tests retain exact posting/balance assertions.
Desktop visual previews include `capture`, `capture-ready`, `capture-missing`,
`transaction` and `transaction-new`. GTK previews are not Android evidence.

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
draft when leaving a picker. Saving a new account stays on Assets and offers
Check balance in the confirmation notice.
The global capture action is a 56-point ink circle with a line plus, centered
beside the dock. Its accessible name remains New entry / 新记录.
Asset changes opens the full 30-day dated valuation chart and basis notes;
it explicitly distinguishes recorded value changes from investment returns.
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
inspected from all timelines. Corrections use another balance check.

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
to CNY using dated Frankfurter ECB rates or manual rates under Manage → Exchange
rates. Same-day manual quotes/rates take priority. Missing rates leave currencies
visibly excluded from the known total; incomplete historical rates prevent a
misleading full trend. Schema 14 includes exchange rates in backups. Other
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

Successful foreground quote/rate updates also backfill the last 30 days.
Asset changes offers a manual retry. Fetches are single-flight and bounded to
one year plus a ten-day prior-price warm-up per request, with a six-hour success TTL and five-minute failure TTL;
only used foreign currencies are fetched. A ten-day price/FX warm-up permits prior
published rates across weekends without using future rates. Empty responses
remain missing data, not a coverage guarantee. No minute/tick history or
corporate-action-adjusted return series is implemented.

Manage → Price history lists daily closes and saved corrections, with OHLC,
source and revisions on expansion. Holding details offer a filtered entry.
A changed binding clears only its active network marks: the old observations
and symbol-keyed daily bars remain in the archive. Migration records existing
marks/rates as baselines at migration time, never inventing original fetch times.
Unchanged values add no audit revision. Manual FX rates keep same-day priority.

Asset changes separates Recalculated (current ledger plus dated marks/rates)
from Recorded (immutable observations at the shown instant). Automatic capture
runs once per local day after a successful refresh, or on foreground entry for
cash-only portfolios without a network request. Manual capture appends another
observation. A snapshot copies native balances, positions, prices, actual rates,
calculation inputs and integrity checksums; later edits never rewrite it.
Missing FX is explicit and prevents a partial net-worth chart. Recorded values
are not end-of-day closing values; past observations are never fabricated.

Backups include all three new tables. Migration, exact roundtrip, malformed
history/audit/snapshot rejection and atomic restore are checked alongside
revision precedence, manual overrides and immutable valuation tests. Live
public TLS checks cover CN 510300, HK 00700, US AAPL/BRK.B and both FX pairs;
Android platform behavior still requires device verification.

Desktop preview: add `history` to the existing `holdings,multicurrency,fx`
flags and use `NW_PREVIEW_ROUTE=price-history` or `asset-history`.
