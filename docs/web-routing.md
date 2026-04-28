# Web Routing — Manual Verification Checklist

Behavior contract for the Flutter web build's go_router setup.
Automated coverage lives in `apps/mobile/test/app/router_test.dart`; this
document covers the platform-glue behaviors that only manifest in a real
browser (history stack, hard refresh, address-bar deep links) and are not
testable from `flutter test`.

Tracking issues: [FIR-43](#) (this verification), [FIR-14](#) (initial setup),
[FIR-40](#) (cross-browser matrix).

## Setup

Build a release web bundle and serve it from a static origin so the path URL
strategy resolves the way it will in production.

```bash
cd apps/mobile
flutter build web --release
cd build/web
python3 -m http.server 8080
# open http://localhost:8080/
```

Repeat the run-through on each browser in the FIR-40 matrix
(Chrome, Safari, Edge, Firefox; macOS + iOS Safari at minimum).

## Routes in scope

| Path          | Page         | Notes                                            |
| ------------- | ------------ | ------------------------------------------------ |
| `/`           | Overview     | Default landing; bottom-nav index 0              |
| `/assets`     | Assets       | Bottom-nav index 1                               |
| `/analytics`  | Analytics    | Bottom-nav index 2                               |
| `/settings`   | Settings     | Bottom-nav index 3                               |

Future deep-link surfaces (not yet built; tracked separately):

- `/assets/<id>` — asset detail page (depends on FIR-5 asset entry feature)
- `/analytics?range=1y` — analytics range as a query param
  (depends on FIR-7 chart container)
- `/login` with `?redirect=...` — depends on FIR-30 client auth

## Checklist

For each item: tick **Pass** if the actual behavior matches the expected
column; otherwise file a follow-up linked to FIR-43.

### A. Bottom-tab navigation pushes browser history

1. Open `/`. Click **Assets** → URL becomes `/assets`, page renders Assets.
2. Click **Analytics** → URL becomes `/analytics`, page renders Analytics.
3. Press the browser **Back** button → URL returns to `/assets`,
   page renders Assets, the Assets tab is highlighted.
4. Press **Back** again → URL returns to `/`, Overview renders,
   Overview tab is highlighted.
5. Press **Forward** twice → URL walks back to `/analytics`,
   each step renders the matching page.

Expected: every tab tap creates exactly one new browser history entry.
Back/Forward never skip an entry and never get stuck on a page that no longer
matches the URL.

### B. Deep-link arrival from the address bar

For each of the routes below: paste the URL into a fresh tab, press Enter,
and confirm the listed page renders without flashing through `/` first.

- [ ] `http://localhost:8080/assets` → Assets
- [ ] `http://localhost:8080/analytics` → Analytics
- [ ] `http://localhost:8080/settings` → Settings
- [ ] `http://localhost:8080/analytics?range=1y` → Analytics
      (the query string is currently ignored; once FIR-7 wires `range`,
      verify the chart honors the param on first paint)

The bottom-nav highlight must match the URL on the first frame.
There must be no visible redirect to `/` before settling.

### C. Hard refresh (F5 / ⌘R)

1. Navigate to `/analytics` via tab.
2. Hard-refresh.

Expected:

- The same page re-renders.
- The URL stays at `/analytics`.
- Riverpod state is reset (any in-memory toggles return to defaults) —
  durable preferences persisted via `SharedPreferences` (theme mode,
  market-color mode) survive because they live on disk.
- Once features that store domain state in the URL ship (FIR-7 `?range=`,
  FIR-5 detail IDs), refresh must restore that state from the URL.

Repeat at `/`, `/assets`, `/settings`.

### D. 404 / unknown paths

Paste `http://localhost:8080/nope` and press Enter.

Expected today: go_router renders its built-in error page (no crash, the
shell may not be visible). This is acceptable as a temporary baseline. Once a
custom `errorBuilder` is added, this checklist gains a step asserting the
branded 404 with a link back to `/`.

### E. Authenticated routes (DEFERRED — needs FIR-30)

Once client-side auth lands:

- [ ] Refreshing on a protected route while signed out redirects to
      `/login?redirect=<original>`.
- [ ] After signing in, the user lands back on the original `redirect`
      target, not the default `/`.
- [ ] Browser back from `/login` does not loop the user back into the
      redirect.

## Triage rules

- Found a routing bug → fix in FIR-43.
- Found a missing **feature** (e.g. `/assets/<id>` doesn't exist yet) →
  file a follow-up under the relevant feature epic; do not expand FIR-43.
- Browser-specific regression (Safari only, etc.) → attach to FIR-40 with
  the failing checklist item ID.
