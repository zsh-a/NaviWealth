# NaviWealth native client (NSH)

NaviWealth's native client, written in Rust on [NSH](https://github.com/longbridge/nsh)
0.5.0. Its first page is HealthOS meal logging: choose a photo of a meal, allow
it to be sent to your own vision model, review the estimated foods and amounts,
and save; Today shows the day's energy and macronutrients. Manual entry works
without any account. Design standards and the motion inventory: `DESIGN.md`.

Meals, weights and Garmin days live on the device in
`naviwealth.sqlite`, photos in the app's data directory, the model and Garmin
keys under their own storage keys. Optional encrypted backups go to the owner's
WebDAV folder. Garmin data comes read-only from Garmin's
Personal API with the user's own key. Photos go straight from the device to the base
URL you configure (Anthropic Messages API or an OpenAI-compatible Chat
Completions API); there is no NaviWealth relay.

```text
src/
  domain/   host-owned meals/account and shared health-core domain exports
  data/     device storage, photos, local time, thin NSH fetch Transport
  ui/       the app's styled components over nsh-base, and its tokens
  pages/    Today, meal editing, weekly health review, Settings
  i18n/     English and Chinese copy
  preview.rs  desktop-only preview seeding for design review
tests/      headless meal, weight, Garmin, review and backup flows
```

Meal recognition, catalog nutrition, photo normalization and destination-bound
consent live in `../../crates/health-core`, shared with Flutter. Provider wire
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
nsh package --target android --abi arm64-v8a   # needs the Android SDK, NDK and a JDK
```

The Android debug APK is built by the manual GitHub Actions workflow
`nsh client` (`.github/workflows/nsh-client.yml`), uploaded as an artifact and
signed with the debug key.

## Health review and backups

The chart action on Today opens seven days ending today, with earlier weeks
one step back. Intake and macros average only days with logged meals; missing
days are unknown. Weight compares the first and last measurements in the window.
Garmin averages each measurement over the days that contain it.

Settings → Backup accepts an HTTPS WebDAV folder (for example Jianguoyun,
Nextcloud or Synology), account, app password and a backup passphrase of at
least eight characters. Save and back up applies immediately. With this set
up, opening or resuming the app makes one backup per local calendar day; this
is a foreground task, not an Android scheduled background job. Manual backups
can be made any time. Each file has a new timestamped name and a conditional
PUT prevents replacing an existing file. No automatic remote deletion occurs.

Backups contain the SQLite database: meals, weights and imported Garmin days.
**Photos, model/Garmin keys, settings, WebDAV credentials and the passphrase
are excluded.** The passphrase is kept in app-private storage and must also be
saved elsewhere to restore on a fresh install. The `NWBK` format uses Argon2id
(32 MiB, three passes) and XChaCha20-Poly1305 with an authenticated header.

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
they need no live service or personal key. System-picker file export and
photo archives are not implemented in this increment.

## Desktop previews

`src/preview.rs` (not compiled for phones) seeds a fresh data directory from
environment variables, so each state can be opened and captured without the
picker or a real account:

```sh
XDG_DATA_HOME=$(mktemp -d) \
NW_PREVIEW=account,trust,meals,goal NW_PREVIEW_BASE_URL=http://127.0.0.1:8799/v1 \
NW_PREVIEW_ROUTE=new:/path/to/meal.jpg cargo run
```

`NW_PREVIEW` also takes `dark`/`light`; `NW_PREVIEW_ROUTE` takes `manual`,
`edit`, `settings` and `review`; `NW_PREVIEW_PHOTOS` lists photos for the seeded meals;
`NW_PREVIEW_EDITOR=1` opens the first food's editor once results arrive.
