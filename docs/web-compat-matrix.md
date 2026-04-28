# Web — Cross-Browser Compatibility Matrix

NaviWealth ships a Flutter Web build (`apps/mobile/web/`) that is exercised
both as a regular SPA and installed as a PWA. The browser/OS combinations
below define what we consider supported, what we explicitly degrade on, and
the hand-tested checklist that gates each release.

The companion automated smoke (`apps/mobile/web_smoke/`, see below) covers
Chromium / WebKit / Firefox on Linux runners; the manual checklist covers
the platform-specific bits that headless runners can't reach (real Safari,
real iOS Safari, "Add to Home Screen" install).

Parent task: [FIR-35](../README.md). This doc is the FIR-40 deliverable.

---

## 1. Support tiers

We use three tiers. Treat the tier as the SLA for any new web feature: if
you can't make it work on a Tier 1 browser, the feature isn't done.

| Tier  | Meaning                                                                  | Browsers                                                       |
| ----- | ------------------------------------------------------------------------ | -------------------------------------------------------------- |
| **1** | Fully supported. Bug = release blocker.                                   | Chrome (latest, Win/macOS), Edge (latest, Win), Safari (latest, macOS), Safari iOS (latest two majors) |
| **2** | Supported with a documented degraded path. Bug = high-priority but shippable. | Firefox (latest, Win/macOS) — degraded persistence (see §4.1) |
| **3** | Best-effort only. Bug = nice to fix, not blocking.                        | Chrome / Edge previous-major; Firefox ESR; Safari N-2          |

We do **not** support: any IE, Opera Mini, in-app webviews on Android
(WeChat, etc.), or browsers older than the tiers above. The app should
still load (no blank screen), but no other guarantees.

## 2. The matrix

| Browser        | OS         | Persistence (Drift)                     | PWA install         | Service Worker | Key worries                                                                                  |
| -------------- | ---------- | ---------------------------------------- | ------------------- | -------------- | -------------------------------------------------------------------------------------------- |
| Chrome / Edge  | Windows    | OPFS via worker (preferred)              | Yes (omnibox)       | Yes            | Baseline. If something doesn't work here, it's a bug, not a compat issue.                    |
| Chrome         | macOS      | OPFS via worker                          | Yes (omnibox)       | Yes            | Baseline.                                                                                    |
| Safari         | macOS 14+  | OPFS via worker                           | Yes (Sonoma+ "Add to Dock") | Yes            | OPFS quota differs from Chromium; private mode falls back to in-memory.                      |
| Safari         | iOS 17+    | OPFS via worker (where available) → IndexedDB | Yes (Share → Add to Home) | Limited (no background sync, no push without user gesture) | Aggressive eviction after 7 days unused; no SW background fetch; keyboard focus quirks.       |
| Firefox        | Win/macOS  | **IndexedDB fallback** (OPFS not supported in workers as of FF 124) | Yes (extension/add-to-home varies) | Yes | Slower writes than OPFS; fallback path must stay green. See §4.1.                            |

`Persistence (Drift)` rows reflect what `WasmDatabase.open` selects in
practice today (see `apps/mobile/lib/data/db/connection_web.dart`). The
choice is logged in debug builds — verify it on a real device when in doubt.

## 3. Manual smoke checklist

Run this against a release build (`flutter build web --release` followed
by `tool/setup-drift-web.sh`, or the `mobile-web-build` artifact from the
`mobile` workflow) before each release.

For each browser/OS row in §2, walk the checklist below. Mark ✅ / ❌ /
N/A in the release issue.

### 3.1 First paint & shell

- [ ] Page loads without console errors (only the drift-impl info log is
      acceptable).
- [ ] `flutter_bootstrap.js` finishes within ~5 s on a warm cache (cold-cache
      timing is tracked separately in FIR-39 / first-paint budget).
- [ ] Splash transitions cleanly into the home page; no flash of unstyled
      content.
- [ ] Chinese glyphs render with the subsetted font; if the subset is
      missing a glyph, the system fallback is used (no tofu □□).

### 3.2 Authentication

- [ ] Sign-in flow completes; tokens land in storage (check `localStorage` /
      `IndexedDB` per platform, never plain cookies).
- [ ] Refresh after sign-in keeps the user signed in (no surprise sign-out).
- [ ] Sign-out clears the session **and** the local Drift DB (verify the
      `naviwealth` IndexedDB / OPFS entry is gone).

### 3.3 Drift persistence

- [ ] Add an asset → reload tab → asset still there.
- [ ] Watch the debug log line `drift web: opened "naviwealth" via …` and
      record the implementation chosen (OPFS, sharedIndexedDb, etc.).
- [ ] On Firefox, confirm the chosen impl is `sharedIndexedDb` /
      `unsafeIndexedDb`, not OPFS.
- [ ] On iOS Safari, force-quit the PWA, wait, reopen → data still present
      (this is the path that gets evicted; see §4.2).
- [ ] In a private/incognito window, the app loads but persistence is
      in-memory only and a banner / toast warns about it.

### 3.4 PWA install (manual only — no headless coverage)

- [ ] **Chrome / Edge desktop**: install via omnibox icon → app launches as
      its own window with the manifest theme color and icon.
- [ ] **iOS Safari**: Share → Add to Home Screen → icon shows the maskable
      512px asset, not the 192px favicon. Launching from Home enters
      standalone mode (no Safari chrome).
- [ ] **macOS Safari (Sonoma+)**: File → Add to Dock → app launches as a
      separate Dock entry.
- [ ] After install, opening the installed app while offline shows the
      cached shell, not the browser's offline page.

### 3.5 go_router URL behaviour (PathUrlStrategy)

- [ ] Direct hit on `/assets`, `/analytics`, `/settings` from a fresh tab
      loads the right tab (no `#/` in the URL).
- [ ] Browser **Back** from `/settings` returns to whichever tab was
      previously active, then to the home page; never to `about:blank`.
- [ ] Browser **Forward** restores the same destination.
- [ ] Hard refresh on a deep link (e.g. `/assets/123`) re-renders the same
      page. If we have asset detail routes, this is the one that breaks
      first when someone forgets to register a route.
- [ ] `Cmd/Ctrl+L` → edit the URL → enter: navigates without full reload
      where router can handle it.

### 3.6 Keyboard / desktop ergonomics

- [ ] `Tab` traverses focusable controls in visual order; focus ring is
      visible.
- [ ] `Esc` closes modal sheets / dialogs.
- [ ] On Safari iOS, opening a numeric input does **not** zoom the viewport
      (we set `font-size: 16px` on inputs to suppress this).
- [ ] On Safari iOS PWA, the on-screen keyboard does not push fixed
      elements off-screen (known quirk — see §4.2).

### 3.7 Fonts

- [ ] Latin-only screens use the small Latin subset (~50 KB).
- [ ] Chinese-heavy screens lazy-load the CJK subset; first paint isn't
      blocked on it.
- [ ] When the CJK subset 404s (simulate by blocking the request), the
      page falls back to the system font instead of showing tofu.

## 4. Known issues / accepted limitations

### 4.1 Firefox: no OPFS in dedicated workers

Drift's `WasmDatabase.open` probes for OPFS in a worker; Firefox stable
(through 124) doesn't expose `navigator.storage.getDirectory()` inside
dedicated workers. We fall through to **shared IndexedDB**, which is the
intended Tier 2 path. Symptoms to expect on Firefox:

- The debug log shows `via sharedIndexedDb` (or `unsafeIndexedDb` if shared
  workers also misbehave).
- Bulk imports are noticeably slower than Chromium. This is acceptable;
  the app remains correct.
- Quota: IndexedDB quotas are soft on FF (group-based). Don't rely on
  `StorageManager.estimate()` returning the same numbers as Chrome.

If a release ever sees Firefox pick `inMemory`, that's a regression — file
a blocker. The smoke test asserts the chosen impl is one of
`{sharedIndexedDb, unsafeIndexedDb, opfsLocks, opfsShared}`.

### 4.2 iOS Safari: PWA storage eviction

iOS Safari evicts website data after **7 days of non-use**, including
data installed through Add to Home. There is no API to opt out
(`navigator.storage.persist()` returns `false` on iOS). For NaviWealth this
means:

- Sync must be able to rehydrate from server on first launch after
  eviction. The "first run on a clean device" code path is therefore part
  of the iOS PWA happy path, not an edge case.
- Encryption keys stored only in IndexedDB will also disappear; treat them
  as cache, not source of truth.

We do not consider this a bug. We do consider a missing rehydrate-on-empty
path a bug.

### 4.3 iOS Safari: no background Service Worker

Background Sync, Periodic Background Sync, and Push without a user gesture
don't work on iOS. Anything that needs them must degrade:

- Sync only runs while the PWA is in the foreground.
- "Refresh quotes" notifications are not delivered when the app is
  closed — the dashboard refreshes on next foreground.

### 4.4 Safari (all): IndexedDB quota in private mode

Private-mode Safari reports a tiny IndexedDB quota and may refuse OPFS.
`WasmDatabase.open` will fall back to `inMemory`. The app loads, but:

- A toast must warn the user that data won't persist across reload.
- We don't crash on `QuotaExceededError`; writes that overflow degrade
  to in-memory and the toast escalates.

### 4.5 Edge cases that are **not** supported

- Browsers without Web Workers (none of our tier-1/2 browsers; listed for
  completeness). The app refuses to start with a clear error message.
- Browsers without `BigInt` (same).
- Mobile webviews embedded in chat apps: not tested, not supported.
  Detect and show "open in browser" CTA where possible.

## 5. Smoke automation

`apps/mobile/web_smoke/` holds the Playwright project that exercises the
critical paths above on Chromium, WebKit, and Firefox. It runs on the
`web-smoke` GitHub Actions workflow (nightly + manual dispatch).

What it does cover (headless):

- App loads without console errors.
- Bottom nav navigates between Home / Assets / Analytics / Settings, and
  the URL matches `PathUrlStrategy` (no `#/`).
- Browser back/forward returns to the correct route.
- Hard refresh on a deep-link route re-renders the same page.
- Drift opens an implementation in
  `{opfsLocks, opfsShared, sharedIndexedDb, unsafeIndexedDb, inMemory}` and
  the chosen impl is logged.
- Manifest + service worker are reachable (200, valid JSON, scope correct).

What it can't cover (and why the manual checklist still exists):

- Real iOS Safari (no headless WebKit-on-iOS available on Linux runners).
- "Add to Home Screen" install + launch.
- Real font rendering — the bot doesn't have the user's font cache.
- Authentication that requires a working backend; we use a mocked auth
  shim for the smoke run.

See `apps/mobile/web_smoke/README.md` for how to run it locally.
