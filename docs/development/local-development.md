# Local Development Guide

End-to-end setup for running NaviWealth locally (backend + Flutter app).

NaviWealth is a Personal LifeOS with FinanceOS always on and HealthOS,
KnowledgeOS, and ExecutionOS available as opt-in domains. AI runs device-only
with user-supplied LLM keys — no backend AI relay. See
[`lifeos-architecture-northstar.md`](../architecture/lifeos-architecture-northstar.md)
for boundaries and [`ai-architecture.md`](../ai/ai-architecture.md) for the
device AI design.

---

## Prerequisites

- Rust + `wasm32-unknown-unknown`: `rustup target add wasm32-unknown-unknown`
- Wrangler: `npm i -g wrangler`
- Flutter SDK
- Xcode (iOS / macOS), Android Studio (Android)

---

## 1. Backend

```bash
cd apps/backend
cargo check --target wasm32-unknown-unknown          # build check
echo "JWT_SECRET=$(openssl rand -hex 32)" > .dev.vars # local secret (gitignored)
wrangler d1 migrations apply naviwealth --local      # init local SQLite
../../tool/register-user/register.sh --email you@example.com --execute --local
wrangler dev                                         # serves http://127.0.0.1:8787
```

Verify: `curl http://127.0.0.1:8787/health`.

---

## 2. Flutter app

```bash
cd apps/mobile
flutter pub get
```

One-time web setup (only if targeting `-d chrome` / building web):

```bash
apps/mobile/tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
apps/mobile/tool/build-cn-fonts.sh     # CN font subsets
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

Entitlement changes require a full rebuild (`flutter clean && flutter run`); hot restart won't pick them up.

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
| macOS desktop | `flutter run -d macos` |
| iOS Simulator | `flutter run -d iPhone` |
| Android emulator | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787` |
| Physical device | `flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:8787` |
| Web (Chrome) | `flutter run -d chrome` |

`API_BASE_URL` defaults to `http://127.0.0.1:8787` (see `apps/mobile/lib/core/config/app_config.dart`). `BYPASS_AUTH` defaults to `false`; for an auth-free dev loop pass `--dart-define=BYPASS_AUTH=true`.

After login, the debug console should show `Backend health check: 200 OK` and `NaviWealth bootstrap complete (dev)`.

---

## 5. Common issues

| Symptom | Cause / Fix |
|---------|-------------|
| `Connection failed` / `Operation not permitted` (macOS) | Missing `network.client` entitlement → add it, `flutter clean && flutter run`. |
| `Connection failed` (Android emulator) | Using `127.0.0.1` — use `10.0.2.2`. |
| `Connection failed` (physical device) | Using `127.0.0.1` — use the host's LAN IP. |
| `Keychain error -34018` (macOS) | Missing `keychain-access-groups` entitlement → add and full rebuild. |
| `JWT_SECRET unbound` | `apps/backend/.dev.vars` missing → recreate, restart `wrangler dev`. |
| `no such table: users` | Run `wrangler d1 migrations apply naviwealth --local`. |
| CORS error (web) | Backend not running, or stale build → restart `wrangler dev`. |

---

## 6. Local DB inspection

```bash
cd apps/backend
wrangler d1 execute naviwealth --local --command "SELECT * FROM users;"
```
