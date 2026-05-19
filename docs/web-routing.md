# Web Routing — Manual Verification Checklist

Behavior contract for the Flutter web build's go_router setup. Automated coverage lives in `apps/mobile/test/app/router_test.dart` and `apps/mobile/web_smoke/tests/router.spec.ts`; this doc covers platform-glue behaviors that only manifest in a real browser (history stack, hard refresh, address-bar deep links).

Tracking issues: FIR-43 (this verification), FIR-14 (initial setup), FIR-40 (cross-browser matrix).

## Setup

```bash
cd apps/mobile
flutter build web --release
cd build/web && python3 -m http.server 8080
# open http://localhost:8080/
```

Repeat on each browser in the FIR-40 matrix (Chrome, Safari, Edge, Firefox; macOS + iOS Safari at minimum).

## Routes in scope

Four primary tabs in display order (see `apps/mobile/lib/app/route_paths.dart::kPrimaryTabPaths`):

| Path | Tab | Notes |
|------|-----|-------|
| `/` | Home | Default landing; index 0 |
| `/activity` | Activity | Index 1 |
| `/accounts` | Accounts | Index 2 |
| `/settings` | Settings | Index 3 |

There is **no `/ai` tab**. AI is not a destination: it lives in the command-palette
overlay and inline capsules; chat history is read-only under `/settings/ai-history`.
The former `/ai/insights/*` dashboards (FIRE / Rebalance / Analytics) are
deterministic and now live under `/accounts/*`.

Common deep links (sample — `route_paths.dart` is the full list):

- `/accounts/asset/<id>`, `/accounts/physical/<id>`, `/accounts/liabilities/<id>` — detail pages
- `/accounts/{fire,rebalance,analytics}` — plan dashboards (formerly `/ai/insights/*`)
- `/activity/expenses`, `/activity/expenses/<id>`, `/activity/trade`, `/activity/transfer`
- `/settings/{devices,fx-rates,backup,logs,sync,ai-history}`
- `/login` (with optional `?redirect=`)

## Checklist

For each item: tick **Pass** if behavior matches; otherwise file a follow-up linked to FIR-43.

### A. Tab navigation pushes browser history

1. Open `/`. Click **Activity** → URL becomes `/activity`, page renders Activity.
2. Click **Accounts** → URL becomes `/accounts`, page renders Accounts.
3. Browser **Back** → URL returns to `/activity`, Activity tab highlighted.
4. Browser **Back** again → URL returns to `/`, Home renders, Home highlighted.
5. **Forward** twice → walks back to `/accounts`, each step renders the matching page.

Expected: every tab tap creates exactly one new history entry. Back/Forward never skip an entry and never strand the URL on a non-matching page.

### B. Address-bar deep links

For each URL: paste into a fresh tab, press Enter, confirm the listed page renders without flashing through `/` first. Bottom-nav highlight must match the URL on the first frame.

- [ ] `/activity`
- [ ] `/accounts`
- [ ] `/settings`
- [ ] `/accounts/asset/<known-id>` — asset detail
- [ ] `/activity/expenses` — expense list
- [ ] `/accounts/fire` — FIRE plan dashboard
- [ ] `/settings/ai-history` — read-only chat history
- [ ] `/settings/devices`

### C. Hard refresh (F5 / ⌘R)

1. Navigate to `/accounts/analytics` via tabs/links.
2. Hard-refresh.

Expected:
- Same page re-renders; URL stays put.
- Riverpod state resets (in-memory toggles back to defaults). Durable preferences (`SharedPreferences`: theme, market-color mode) survive.
- Routes that store domain state in the URL (e.g. asset detail IDs, query params) restore from the URL on first paint.

Repeat at `/`, `/activity`, `/accounts`, `/settings`.

### D. 404 / unknown paths

Paste `http://localhost:8080/nope` and Enter.

Expected: a branded `RouteErrorPage` (see `apps/mobile/lib/app/route_error_page.dart`) with a link back to `/`. No crash, no blank screen.

### E. Authenticated routes

With `BYPASS_AUTH=false` (production / staging build):

- [ ] Refreshing on a protected route while signed out redirects to `/login?redirect=<original>`.
- [ ] After signing in, the user lands back on the original `redirect`, not the default `/`.
- [ ] Browser back from `/login` does not loop the user back into the redirect.

## Triage rules

- Routing bug → fix in FIR-43.
- Missing **feature** (e.g. a route doesn't exist yet) → file under the relevant feature epic; don't expand FIR-43.
- Browser-specific regression (Safari only, etc.) → attach to FIR-40 with the failing checklist item ID.
