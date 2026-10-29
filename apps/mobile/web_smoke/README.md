# `web_smoke` — Cross-Browser Smoke for the Flutter Web Build

The bootstrap loads bundled CanvasKit assets from the app origin, and Flutter's
default font family reuses bundled Inter. The boot suite blocks external
requests and requires zero external startup requests or console errors.

Automated companion to [`docs/development/web-compat-matrix.md`](../../../docs/development/web-compat-matrix.md) (FIR-40). Runs Playwright against the production-shaped Flutter web bundle on **Chromium, WebKit, and Firefox**, asserting things that have silently regressed before:

- Accounts created through the UI survive a hard reload.
- Knowledge notes written in either of two tabs are readable by the other.
- Optional domains start disabled; enabling them permits Knowledge/Execution
  capture, concrete detail links, and reload with the saved content intact.
- Workspace navigation and browser back/forward render the expected content.
- Wealth time ranges support pointer and keyboard selection after recording a
  real cash balance, retaining selection and focus across phone/desktop resizing.
- `PathUrlStrategy` routes resolve as direct hits and after reload.
- Core Finance routes stay free of document-level horizontal overflow at
  390, 840, 1200, and 1600px viewport widths.
- `manifest.json` and Drift's web assets (`sqlite3.wasm`, `drift_worker.dart.js`) are reachable.
- The boot flow doesn't leak console errors or unhandled page errors.

Out of scope:

- Real-backend login and cloud sync (the suite uses production local-only mode).
- PWA installation, real font rendering, and native keyboard/platform quirks.
- Perf benchmarks (first-paint budgets live in FIR-39).
- Real iOS Safari (not reachable from a Linux runner).

The responsive viewport matrix runs once in Chromium; the existing boot,
routing, persistence, and PWA suites continue to run in all three browser
engines so breakpoint coverage does not multiply the cross-browser runtime.
Document-width assertions detect host-page overflow; the responsive Flutter
goldens cover layout inside the canvas.

## Local run

From `apps/mobile/`:

```bash
# 1. Build the web bundle and install the generated Drift root assets.
bash tool/build-web.sh --release

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

Each test has a fresh browser context with the production `app.mode.v1`
preference set to `local_only`, and a fixed English browser locale. Auth route
guards remain enabled. Domain preferences and records are created through the
actual UI and repositories; no backend, mocked auth, direct database seeding,
or test-only application bridge is needed. Flutter's accessibility placeholder
enables role/text locators. A mounted canvas alone never proves business success.

The harness boots a tiny static server (`serve.mjs`) that points at
`../build/web` and falls back to `index.html` for SPA routes. Set
`WEB_SMOKE_BASE_URL=https://staging.example.com` to skip the local server
and run against a deployed build instead.

## CI

Mobile CI calls the reusable `web-smoke` workflow
(`.github/workflows/web-smoke.yml`) for pull requests and `main`. It builds once
with the production API URL and source SHA, checks the bundled catalog bytes,
and runs Chromium. On `main`, the passing bundle is uploaded as `mobile-web-build`;
Pages deploys those exact bytes after static checks, test shards, and full
goldens also succeed. Weekly and manually dispatched runs execute the same
build with Chromium, Firefox, and WebKit.

PRs and `main` set `WEB_SMOKE_RESPONSIVE=compact`: `/wealth/accounts` and
`/plan/rebalance` at 390px and 1200px (four app boots). Weekly/manual runs use
`full`: all five Finance routes at all four widths (20 boots). Direct-hit,
refresh/history, storage, and PWA suites run in both modes. Local runs default
to `full`; set `WEB_SMOKE_RESPONSIVE=compact` to reproduce the PR gate.

## Adding a check

Each `tests/*.spec.ts` follows the same shape:

1. `attachConsoleSpy(page)` before the first navigation.
2. Import `test` from `_app.ts`; use `openApp(page, route)` for a new document,
   or `enableFlutterSemantics(page)` after reload.
3. Await concrete content, saved values, or navigation results with role/text
   locators. For text input, `enterText` sends keyboard input to Flutter's
   focused editor rather than mutating its accessibility mirror.
4. End with `await expectNoConsoleErrors(spy)` so an unrelated `.dart` exception still trips this suite.

Persistence is proven by reading saved content after reload or in another tab.
Storage-origin existence is insufficient, and missing data must fail rather
than skip. These tests do not infer which Drift backend the browser selected.
