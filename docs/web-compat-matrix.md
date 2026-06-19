# Web — Cross-Browser Compatibility Matrix

NaviWealth ships a Flutter Web build (`apps/mobile/web/`) that runs as both a regular SPA and an installable PWA. This matrix defines what's supported, what degrades, and the manual checklist that gates each release.

Headless smoke (`apps/mobile/web_smoke/`) covers Chromium / WebKit / Firefox on Linux runners; the manual checklist covers what those can't reach (real Safari, real iOS Safari, "Add to Home Screen" install).

Parent task: cross-browser compatibility.

---

## 1. Support tiers

| Tier | Meaning | Browsers |
|------|---------|----------|
| **1** | Fully supported. Bug = release blocker. | Chrome (latest, Win/macOS), Edge (latest, Win), Safari (latest, macOS), Safari iOS (latest two majors) |
| **2** | Supported with documented degraded path. Bug = high-priority but shippable. | Firefox (latest, Win/macOS) — degraded persistence (see §4.1) |
| **3** | Best-effort. Bug = nice to fix, not blocking. | Chrome / Edge previous-major; Firefox ESR; Safari N-2 |

Not supported: any IE, Opera Mini, Android in-app webviews (WeChat, etc.), or browsers older than the tiers above. The app should still load (no blank screen), but no other guarantees.

## 2. The matrix

| Browser | OS | Persistence (Drift) | PWA install | SW | Key worries |
|---------|----|----|--|---|----|
| Chrome / Edge | Windows | OPFS (worker) | Yes (omnibox) | Yes | Baseline. |
| Chrome | macOS | OPFS (worker) | Yes (omnibox) | Yes | Baseline. |
| Safari | macOS 14+ | OPFS (worker) | Yes (Sonoma+ "Add to Dock") | Yes | OPFS quota differs from Chromium; private mode falls back to in-memory. |
| Safari | iOS 17+ | OPFS (where avail) → IndexedDB | Share → Add to Home | Limited (no background sync, no push without gesture) | Aggressive eviction after 7 days unused; keyboard focus quirks. |
| Firefox | Win/macOS | **IndexedDB fallback** (no OPFS in workers as of FF 124) | Add-on / add-to-home varies | Yes | Slower writes than OPFS; fallback path must stay green. See §4.1. |

Persistence reflects what `WasmDatabase.open` selects today (see `apps/mobile/lib/data/db/connection_web.dart`). The choice is logged in debug builds — verify on a real device when in doubt.

## 3. Manual smoke checklist

Run against a release build (`flutter build web --release` then `apps/mobile/tool/setup-drift-web.sh`, or the `mobile-web-build` CI artifact) before each release. Walk each browser/OS row in §2; mark ✅ / ❌ / N/A in the release issue.

### 3.1 First paint & shell
- [ ] Page loads with no console errors (drift-impl info log is acceptable).
- [ ] `flutter_bootstrap.js` finishes within ~5 s on warm cache.
- [ ] Splash → home with no flash of unstyled content.
- [ ] Chinese glyphs render via the subsetted font; missing glyphs fall back to system font (no tofu □□).

### 3.2 Authentication
- [ ] Sign-in completes; tokens land in storage (`localStorage` / `IndexedDB`, never plain cookies).
- [ ] Refresh after sign-in keeps the user signed in.
- [ ] Sign-out clears the session **and** the local Drift DB (verify the `naviwealth` IndexedDB / OPFS entry is gone).

### 3.3 Drift persistence
- [ ] Add an asset → reload tab → asset still there.
- [ ] Record the chosen impl from `drift web: opened "naviwealth" via …`.
- [ ] On Firefox: chosen impl is `sharedIndexedDb` / `unsafeIndexedDb`, not OPFS.
- [ ] On iOS Safari PWA: force-quit → reopen → data still present.
- [ ] In private/incognito: app loads, persistence is in-memory only, banner warns the user.

### 3.4 PWA install (manual only)
- [ ] **Chrome / Edge desktop**: omnibox icon → app launches in own window with manifest theme + icon.
- [ ] **iOS Safari**: Share → Add to Home → maskable 512px icon (not the 192px favicon); standalone mode (no Safari chrome).
- [ ] **macOS Safari (Sonoma+)**: File → Add to Dock → separate Dock entry.
- [ ] After install: opening offline shows the cached shell, not the browser's offline page.

### 3.5 go_router URL behaviour (PathUrlStrategy)
- [ ] Direct hit on `/wealth`, `/activity`, `/plan`, `/settings` (the four-tab set; there is no `/ai` tab) from a fresh tab loads the right tab (no `#/`).
- [ ] Browser **Back** from `/settings` returns to the previously active tab, then home; never `about:blank`.
- [ ] Browser **Forward** restores the same destination.
- [ ] Hard refresh on a deep link (e.g. `/wealth/assets/<id>`) re-renders the same page.
- [ ] `Cmd/Ctrl+L` → edit URL → enter: navigates without full reload where router can handle it.

### 3.6 Keyboard / desktop ergonomics
- [ ] `Tab` traverses focusable controls in visual order; focus ring visible.
- [ ] `Esc` closes modal sheets / dialogs.
- [ ] iOS Safari: numeric input does **not** zoom the viewport (we set `font-size: 16px` on inputs).
- [ ] iOS Safari PWA: on-screen keyboard does not push fixed elements off-screen (known quirk — §4.2).

### 3.7 Fonts
- [ ] Latin-only screens use the small Latin subset (~50 KB).
- [ ] Chinese-heavy screens lazy-load the CJK subset; first paint isn't blocked on it.
- [ ] If the CJK subset 404s (block the request), the page falls back to system font — no tofu.

## 4. Known issues / accepted limitations

### 4.1 Firefox — no OPFS in dedicated workers
Drift probes for OPFS in a worker; FF stable (≤124) doesn't expose `navigator.storage.getDirectory()` there. We fall through to **shared IndexedDB** (Tier 2 path). Bulk imports are noticeably slower than Chromium; this is acceptable. If a release ever sees Firefox pick `inMemory`, that's a regression — file a blocker. Smoke asserts the chosen impl is one of `{sharedIndexedDb, unsafeIndexedDb, opfsLocks, opfsShared}`.

### 4.2 iOS Safari — PWA storage eviction
iOS evicts website data after **7 days of non-use**, including PWAs. There is no opt-out (`navigator.storage.persist()` returns `false`). Implications:
- Sync must rehydrate from the server on first launch after eviction. Not an edge case — part of the iOS PWA happy path.
- Encryption keys in IndexedDB also disappear; treat them as cache, not source of truth.

### 4.3 iOS Safari — no background Service Worker
Background Sync, Periodic Background Sync, and Push without a user gesture don't work on iOS. Sync only runs while the PWA is in the foreground; "refresh quotes" notifications are not delivered when closed.

### 4.4 Safari (all) — IndexedDB quota in private mode
Private Safari reports a tiny IndexedDB quota and may refuse OPFS. `WasmDatabase.open` falls back to `inMemory`; the app loads but a toast warns the user that data won't persist. We don't crash on `QuotaExceededError`.

### 4.5 Not supported
- Browsers without Web Workers or `BigInt` — refuses to start with a clear error.
- In-app chat webviews (WeChat, etc.) — show "open in browser" CTA where possible.

## 5. Smoke automation

`apps/mobile/web_smoke/` remains available for manual Playwright checks on Chromium, WebKit, and Firefox. It is no longer part of GitHub Actions CI.

Covered headless:
- App loads with no console errors.
- Bottom nav navigates between tabs; URL matches `PathUrlStrategy` (no `#/`).
- Browser back/forward returns to the correct route.
- Hard refresh on a deep-link route re-renders the same page.
- Drift opens an impl in `{opfsLocks, opfsShared, sharedIndexedDb, unsafeIndexedDb, inMemory}`; chosen impl is logged.
- Manifest + service worker are reachable (200, valid JSON, scope correct).

Not covered (why the manual checklist still exists):
- Real iOS Safari (no headless WebKit-on-iOS available on Linux).
- "Add to Home Screen" install + launch.
- Real font rendering (the bot doesn't share the user's font cache).
- Auth requiring a real backend (smoke uses a mocked auth shim).

See `apps/mobile/web_smoke/README.md` to run it locally.
