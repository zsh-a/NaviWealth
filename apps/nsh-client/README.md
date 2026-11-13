# NaviWealth native client (NSH)

NaviWealth's native client, written in Rust on [NSH](https://github.com/longbridge/nsh)
0.5.0. Its first page is HealthOS meal logging: choose a photo of a meal, allow
it to be sent to your own vision model, review the estimated foods and amounts,
and save; Today shows the day's energy and macronutrients. Manual entry works
without any account. Design standards and the motion inventory: `DESIGN.md`.

Everything stays on the device: meals in `naviwealth.sqlite` and photos in the
app's data directory, the API key under its own storage key. Photos go straight from the device to the base
URL you configure (Anthropic Messages API or an OpenAI-compatible Chat
Completions API); there is no NaviWealth relay.

```text
src/
  domain/   host-owned meals/account and shared health-core domain exports
  data/     device storage, photos, local time, thin NSH fetch Transport
  ui/       the app's styled components over nsh-base, and its tokens
  pages/    Today, the meal review (photo, consent, editor), Settings
  i18n/     English and Chinese copy
  preview.rs  desktop-only preview seeding for design review
tests/flows.rs  user flows on the real engine, headless
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
`edit` and `settings`; `NW_PREVIEW_PHOTOS` lists photos for the seeded meals;
`NW_PREVIEW_EDITOR=1` opens the first food's editor once results arrive.
