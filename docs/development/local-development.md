# Local Development Guide

Rust environment setup for the native client and domain cores, followed by
the maintenance setup for the frozen backend + Flutter app.

## Rust environment (native client and domain cores)

The repository defaults to the rolling `nightly` channel in
`rust-toolchain.toml`, matching the NSH client. It installs rustfmt, Clippy,
Android arm64 and the backend's Wasm target using the minimal profile. CI uses
these files too. Run `rtk rustup update nightly` to refresh nightly locally;
keep the root and NSH channel settings aligned. For an exact compiler
reproduction, record `rustc -Vv` and select the corresponding dated nightly
with `cargo +nightly-YYYY-MM-DD`. `rust-version` in package manifests is a
minimum supported version, not the selected development channel.
Third-party submodules retain their own toolchain files.

From the repository root:

```bash
rtk rustup toolchain install
rtk rustup show active-toolchain
rtk git submodule update --init --recursive
rtk cargo fmt --manifest-path crates/finance-core/Cargo.toml --all -- --check
rtk cargo clippy --manifest-path crates/finance-core/Cargo.toml --all-targets --locked -- -D warnings
rtk cargo test --manifest-path crates/finance-core/Cargo.toml --locked
```

Repeat the last three commands for `crates/health-core/Cargo.toml` and
`apps/nsh-client/Cargo.toml`. These are independent Cargo workspaces; there is
no root `Cargo.toml`. CI checks both domain cores on relevant pushes and PRs;
the NSH workflow remains manually dispatched. Keep each workspace's
`Cargo.lock` committed and use `--locked` for checks. Dependency updates are
explicit `cargo update` changes reviewed with their lockfile diffs.

The NSH Linux host needs Clang/libclang, GTK 4 and GStreamer development
packages (Ubuntu: `clang libclang-dev libgtk-4-dev libgstreamer1.0-dev
libgstreamer-plugins-base1.0-dev`). Android packaging additionally needs Java
17, the Android SDK, NDK and NSH CLI; see the pinned versions in
`.github/workflows/nsh-client.yml`.

`.cargo/config.toml` provides backtraces and debug logs for first-party crates
while respecting existing `RUST_BACKTRACE` and `RUST_LOG` environment values.
Development and test builds retain line tables to limit disk usage. For
debugger variable inspection, set `CARGO_PROFILE_DEV_DEBUG=2`; for compiler
diagnostics, use `rtk cargo build -vv --manifest-path <path>`. Release profiles
remain owned by each application manifest.

Cargo discovers configuration from the command's current directory, not the
`--manifest-path` directory. Run backend commands from `apps/backend` so its
Wasm-specific rustflags are loaded. Toolchain selection also follows the
current directory; enter a third-party submodule to use its own pin.
Avoid global target/linker flags or `target-cpu=native` in shared config;
let NSH configure Android linking and Cargo select parallelism. Optional
machine-specific caches can be enabled with `RUSTC_WRAPPER=sccache` after
installing sccache. See the official [Cargo configuration reference](https://doc.rust-lang.org/cargo/reference/config.html)
and [rustup toolchain selection](https://rust-lang.github.io/rustup/overrides.html).

## Frozen Flutter and backend maintenance

NaviWealth is a Personal LifeOS with FinanceOS always on and HealthOS,
KnowledgeOS, and ExecutionOS available as opt-in domains. AI runs device-only
with user-supplied LLM keys — no backend AI relay. See
[`lifeos-architecture-northstar.md`](../architecture/lifeos-architecture-northstar.md)
for boundaries and [`ai-architecture.md`](../ai/ai-architecture.md) for the
device AI design.

---

## Prerequisites

- Rust + `wasm32-unknown-unknown`: `rtk rustup target add wasm32-unknown-unknown`
- Wrangler: `rtk npm i -g wrangler`
- Flutter SDK
- RTK command wrapper (repository commands use `rtk`)
- Xcode (iOS / macOS), Android Studio (Android)

---

## 1. Backend

From the repository root:

```bash
cd apps/backend
rtk cargo check --target wasm32-unknown-unknown
rtk proxy echo "JWT_SECRET=$(rtk proxy openssl rand -hex 32)" > .dev.vars
rtk wrangler d1 migrations apply naviwealth --local
rtk wrangler dev  # serves http://127.0.0.1:8787
```

`.dev.vars` is gitignored and holds the local secret. Keep `wrangler dev`
running in this terminal. Verify with `rtk curl http://127.0.0.1:8787/health`,
then create the first account
from the mobile app's registration screen. Registration uses the same
`POST /auth/register` path in local and production environments.

---

## 2. Flutter app

Open a second terminal at the repository root:

```bash
cd apps/mobile
rtk flutter pub get
```

One-time web setup (only if targeting `-d chrome` / building web):

```bash
rtk ./tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
rtk ./tool/build-cn-fonts.sh     # CN font subsets
rtk ./tool/build-latin-fonts.sh  # Latin font assets
```

---

## 3. Platform-specific config

### macOS — App Sandbox blocks network and Keychain by default

`macos/Runner/{DebugProfile,Release}.entitlements` must include:

```xml
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)*</string></array>
```

Entitlement changes require a full rebuild (`rtk flutter clean && rtk flutter run`); hot restart won't pick them up.

### iOS — allow HTTP for local backend

`ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

> Production: replace with `NSExceptionDomains` to whitelist specific hosts.

### Android — internet permission

`android/app/src/main/AndroidManifest.xml` (before `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### Web — none. Backend CORS handles cross-origin.

---

## 4. Run

| Target | Command |
|--------|---------|
| macOS desktop (development) | `rtk flutter run -d macos` |
| iOS Simulator | `rtk flutter run -d <simulator-device-id>` |
| Android emulator | `rtk flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787` |
| Physical device | `rtk flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:8787` |
| Web (Chrome) | `rtk flutter run -d chrome` |

`API_BASE_URL` defaults to `http://127.0.0.1:8787` (see `apps/mobile/lib/core/config/app_config.dart`). `BYPASS_AUTH` defaults to `false`; for an auth-free dev loop pass `--dart-define=BYPASS_AUTH=true`.

Use `rtk flutter devices` to obtain the simulator/device id. Startup logs
include `NaviWealth critical bootstrap complete` and, in debug builds,
`API_BASE_URL`. Authentication, network diagnostics, and domain background work
start after first paint; the startup message does not prove backend connectivity.
Verify registration/sign-in against the running local backend.

---

## 5. Common issues

| Symptom | Cause / Fix |
|---------|-------------|
| `Connection failed` / `Operation not permitted` (macOS) | Missing `network.client` entitlement → add it, `rtk flutter clean && rtk flutter run`. |
| `Connection failed` (Android emulator) | Using `127.0.0.1` — use `10.0.2.2`. |
| `Connection failed` (physical device) | Using `127.0.0.1` — use the host's LAN IP. |
| `Keychain error -34018` (macOS) | Missing `keychain-access-groups` entitlement → add and full rebuild. |
| `JWT_SECRET unbound` | `apps/backend/.dev.vars` missing → recreate, restart `wrangler dev`. |
| `no such table: users` | Run `rtk wrangler d1 migrations apply naviwealth --local` from `apps/backend`. |
| CORS error (web) | Backend not running, or stale build → restart `wrangler dev`. |

---

## 6. Local DB inspection

From the repository root in another terminal:

```bash
cd apps/backend
rtk wrangler d1 execute naviwealth --local --command "SELECT * FROM users;"
```
