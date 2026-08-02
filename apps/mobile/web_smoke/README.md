# `web_smoke` — Cross-Browser Smoke for the Flutter Web Build

Automated companion to [`docs/development/web-compat-matrix.md`](../../../docs/development/web-compat-matrix.md) (FIR-40). Runs Playwright against the production-shaped Flutter web bundle on **Chromium, WebKit, and Firefox**, asserting things that have silently regressed before:

- Drift opens a persistent storage backend (and on Firefox, that backend is not OPFS).
- `PathUrlStrategy` routes resolve as direct hits and after reload.
- Core Finance routes stay free of document-level horizontal overflow at
  390, 840, 1200, and 1600px viewport widths.
- `manifest.json` and Drift's web assets (`sqlite3.wasm`, `drift_worker.dart.js`) are reachable.
- The boot flow doesn't leak console errors or unhandled page errors.

Out of scope:

- User-flow E2E (Flutter renders into a canvas; flows needing a real human — PWA install, font fallback, keyboard quirks — live in the manual checklist).
- Perf benchmarks (first-paint budgets live in FIR-39).
- Real iOS Safari (not reachable from a Linux runner).

The responsive viewport matrix runs once in Chromium; the existing boot,
routing, persistence, and PWA suites continue to run in all three browser
engines so breakpoint coverage does not multiply the cross-browser runtime.

## Local run

From `apps/mobile/`:

```bash
# 1. Build the web bundle and install the generated Drift root assets.
bash tool/build-web.sh --release --dart-define=BYPASS_AUTH=true

# 2. Install Playwright browsers (one-time).
cd web_smoke
npm ci
npm run install-browsers

# 3. Run the smoke against the static build above.
npm test                    # all three projects
npm run test:firefox        # one project
```

If the Playwright-managed Chromium bundle is unavailable but the host already
has Chromium, set `WEB_SMOKE_CHROMIUM_EXECUTABLE=/path/to/chromium` for the
Chromium project. CI continues to use Playwright's pinned browser by default.

The harness boots a tiny static server (`serve.mjs`) that points at
`../build/web` and falls back to `index.html` for SPA routes. Set
`WEB_SMOKE_BASE_URL=https://staging.example.com` to skip the local server
and run against a deployed build instead.

## CI

The `web-smoke` workflow (`.github/workflows/web-smoke.yml`) runs Chromium for
pull requests that touch Web-relevant paths. Weekly and manually dispatched
runs execute the Chromium, Firefox, and WebKit projects. The workflow builds
its own production-shaped Flutter Web bundle so every smoke run verifies the
same commit without depending on a separate workflow artifact.

## Adding a check

Each `tests/*.spec.ts` follows the same shape:

1. `attachConsoleSpy(page)` before the first navigation.
2. `await page.goto(...)` then `waitForFlutterReady(page)` to avoid racing the first frame.
3. Assert the invariant.
4. End with `await expectNoConsoleErrors(spy)` so an unrelated `.dart` exception still trips this suite.

For Drift internals, prefer `detectDriftImpl` over re-implementing the IndexedDB/OPFS probe inline — the helper centralizes the brittle storage-API calls.
