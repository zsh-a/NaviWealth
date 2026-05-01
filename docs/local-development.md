# Local Development Guide

Setup guide for running NaviWealth locally (backend + Flutter app).

---

## Prerequisites

- Rust + `wasm32-unknown-unknown` target: `rustup target add wasm32-unknown-unknown`
- Wrangler CLI: `npm i -g wrangler`
- Flutter SDK
- Xcode (for iOS/macOS), Android Studio (for Android)

---

## 1. Backend Setup

### 1.1 Install dependencies & build

```bash
cd apps/backend
cargo check --target wasm32-unknown-unknown
```

### 1.2 Create local secrets

Create `.dev.vars` in `apps/backend/` (already gitignored):

```
JWT_SECRET=<any-dev-secret>
```

### 1.3 Initialize local database

```bash
cd apps/backend
wrangler d1 migrations apply naviwealth --local
```

This creates the local SQLite database with all tables (users, devices, sync, ai_rate_limit).

### 1.4 Register a local user

```bash
tool/register-user/register.sh --email you@example.com --execute --local
```

### 1.5 Start the backend

```bash
cd apps/backend
wrangler dev
```

Backend runs at `http://127.0.0.1:8787`. Verify: `curl http://127.0.0.1:8787/health`.

---

## 2. Flutter App Setup

### 2.1 Install dependencies

```bash
cd apps/mobile
flutter pub get
```

### 2.2 One-time web setup (if targeting web)

```bash
tool/setup-drift-web.sh
tool/build-cn-fonts.sh
```

---

## 3. Platform-Specific Configuration

### 3.1 macOS

**Network entitlement** — macOS App Sandbox blocks outbound network by default.

File: `macos/Runner/DebugProfile.entitlements` must include:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

**Keychain entitlement** — `flutter_secure_storage` needs Keychain access:

```xml
<key>com.apple.security.keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)*</string>
</array>
```

Both entitlements are required in `DebugProfile.entitlements` and `Release.entitlements`.

### 3.2 iOS

**Allow HTTP (non-HTTPS)** — Required for local dev against `http://` backend.

File: `ios/Runner/Info.plist` must include:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

> Note: For production, replace with `NSExceptionDomains` to restrict to specific hosts.

### 3.3 Android

**Internet permission** — Required for all network access.

File: `android/app/src/main/AndroidManifest.xml` must include (before `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### 3.4 Web

No additional configuration needed. CORS on the backend handles cross-origin requests.

For different ports (e.g. `localhost:50507` → `127.0.0.1:8787`), the backend's CORS headers allow the request.

---

## 4. Run the App

### macOS desktop

```bash
cd apps/mobile
flutter run -d macos
```

### iOS Simulator

```bash
flutter run -d iPhone
```

### Android Emulator

Android emulator uses `10.0.2.2` to reach the host machine's localhost:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787
```

### Physical Device (iOS/Android)

Use your computer's LAN IP:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8787
```

### Web (Chrome)

```bash
flutter run -d chrome
```

---

## 5. Verifying the Setup

After login, the debug console should show:

```
API_BASE_URL: http://127.0.0.1:8787
Backend health check: 200 OK
NaviWealth bootstrap complete (dev)
```

If you see connection errors, see troubleshooting below.

---

## 6. Common Issues

### "Connection failed" / "Operation not permitted"

- **macOS**: Missing `com.apple.security.network.client` entitlement. Add it and do a full rebuild (`flutter clean && flutter run`).
- **Android emulator**: Using `127.0.0.1` instead of `10.0.2.2`.
- **Physical device**: Using `127.0.0.1` instead of LAN IP.

### "Keychain error -34018"

- **macOS**: Missing `com.apple.security.keychain-access-groups` entitlement. Add it and do a full rebuild (`flutter clean && flutter run`). Hot restart does not refresh entitlements.

### "JWT_SECRET unbound"

- `apps/backend/.dev.vars` is missing. Create it with `JWT_SECRET=<value>` and restart `wrangler dev`.

### "no such table: users"

- Local D1 database not initialized. Run: `wrangler d1 migrations apply naviwealth --local`

### CORS error (web)

- Backend is not running, or running an old version without CORS headers. Restart `wrangler dev`.

### "A required entitlement isn't present" (Keychain)

- Entitlements changes require a **full rebuild**, not hot restart:
  ```bash
  flutter clean
  flutter run -d macos
  ```

---

## 7. Useful Commands

```bash
# Backend
cd apps/backend
wrangler dev                                    # start local backend
wrangler d1 migrations apply naviwealth --local # apply migrations
wrangler d1 execute naviwealth --local --command "SELECT * FROM users;"

# Register user
tool/register-user/register.sh --email you@example.com --execute --local

# Flutter
cd apps/mobile
flutter pub get
flutter test                                    # unit + widget tests
flutter analyze --fatal-infos                   # static analysis
flutter run -d macos                            # macOS desktop
flutter run -d chrome                           # web dev
flutter clean                                   # clean build cache
```
