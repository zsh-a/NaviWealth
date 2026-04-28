# `web_smoke` — Cross-Browser Smoke for the Flutter Web Build

Automated companion to [`docs/web-compat-matrix.md`](../../../docs/web-compat-matrix.md)
(FIR-40). Runs Playwright against the production-shaped Flutter web bundle
on **Chromium, WebKit, and Firefox**, and asserts the things that have
silently regressed before:

- Drift opens a persistent storage backend (and on Firefox, that backend
  is not OPFS).
- `PathUrlStrategy` routes resolve as direct hits and after reload.
- `manifest.json` and Drift's web assets (`sqlite3.wasm`,
  `drift_worker.dart.js`) are reachable from the served bundle.
- The boot flow doesn't leak console errors or unhandled page errors.

What this **isn't**:

- A user-flow E2E. Flutter renders into a canvas; without enabling
  semantics, Playwright can't reach widgets by text or role. The flows
  that need a real human (PWA install, font fallback, keyboard quirks)
  live in the manual checklist.
- A perf benchmark. First-paint budgets live with FIR-39.
- An iOS test. Real iOS Safari isn't reachable from a Linux runner.

## Local run

From `apps/mobile/`:

```bash
# 1. Build the web bundle and materialize Drift assets.
tool/setup-drift-web.sh
flutter build web --release

# 2. Install Playwright browsers (one-time).
cd web_smoke
npm install
npm run install-browsers

# 3. Run the smoke against the static build above.
npm test                    # all three projects
npm run test:firefox        # one project
```

The harness boots a tiny static server (`serve.mjs`) that points at
`../build/web` and falls back to `index.html` for SPA routes. Set
`WEB_SMOKE_BASE_URL=https://staging.example.com` to skip the local server
and run against a deployed build instead.

## CI

The `web-smoke` workflow runs nightly (and on manual dispatch) — see
`.github/workflows/web-smoke.yml`. It downloads the `mobile-web-build`
artifact produced by the `mobile` workflow on the same commit, then runs
the three browser projects in a matrix so a Firefox-only failure (the
most common shape) doesn't block Chromium / WebKit results.

## Adding a check

Each `tests/*.spec.ts` file follows the same shape:

1. `attachConsoleSpy(page)` before the first navigation.
2. `await page.goto(...)` then `waitForFlutterReady(page)` so we don't
   race the first frame.
3. Assert the invariant.
4. End with `await expectNoConsoleErrors(spy)` so a regression in
   unrelated code (e.g. a missed `.dart` exception) shows up here.

If you need to assert on a Drift-internal invariant, prefer
`detectDriftImpl` over re-implementing the IndexedDB/OPFS probe inline —
the helper centralizes the brittle storage-API calls.
