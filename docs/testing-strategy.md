# NaviWealth — Testing Strategy (Production-Grade Delivery)

**Status:** Active SSOT for test architecture. Owns the test pyramid, the
Task spine, the CI gate design, and the burn-down roadmap. Read this
before adding a new test *layer* or changing a CI test gate.

Related: `docs/sync-protocol-tests.md` (sync case matrix), `docs/sync-e2e-manual.md`
(manual multi-device checklist), `docs/web-compat-matrix.md` (browser support),
`docs/visual-baseline/README.md` (golden contract).

---

## 1. Principle: test Tasks, not Pages

The durable unit of testing is a **user task**, not a screen. UI will be
refactored often (responsive layout work is ongoing); a test bound to a
*page's* widget tree breaks on every refactor, while a test bound to a
*task* ("view net worth", "add an account") survives as long as the task
exists. We invest in a small, stable spine of task-level tests and keep
the bulk of coverage cheap and fast at the unit/widget level.

We are **not** in the "90% flaky E2E" anti-pattern. The base is already
strong and unit-heavy — the right shape. This strategy keeps that base
and fills the missing edges (real integration, contracts-as-code, web
smoke enforcement, observability) rather than rebalancing for its own
sake.

## 2. The pyramid (target shape)

```
         AI exploratory + semantic   ~1%   nightly, non-blocking
        Flow / Task (Page Objects)   ~4%   10–15 journeys, test/flow + integration_test
       Contract (Dart↔Rust↔wire)     ~5%   schema-driven, blocking
      Golden (visual regression)     ~5%   expanded surfaces + breakpoints, Linux-pinned
     Integration (real Drift chain)  ~10%  UI→repo→Drift→domain, real connection
    Unit + Widget (the base)         ~75%  KEEP — ~1,765 unit + ~365 widget today
```

Percentages are directional, not quotas. The base stays unit-heavy.

## 3. The Task spine (the stable contract)

These ~12 journeys are the flow-test backbone. Each one earns: a flow
test (`test/flow/` now, `integration_test/` on-device later), a Page
Object, and a golden of its primary surface.

| # | Task (cn) | Task (en) | Primary surface |
|---|-----------|-----------|-----------------|
| 1 | 查看净资产 | View net worth | Home / Today |
| 2 | 添加账户 | Add account | Wealth → account editor |
| 3 | 添加交易 | Add transaction | Investment → trade entry |
| 4 | 导入账单/CSV | Import CSV / statement | Ingest |
| 5 | 多端同步 | Multi-device sync | (protocol — see §6) |
| 6 | AI 问答 | Ask the AI | AI chat |
| 7 | 执行资产分析 | Run portfolio analysis | Analytics |
| 8 | 再平衡 | Rebalance | Rebalance execution |
| 9 | 期权收入计划 | Plan options income | Options income |
| 10 | 生成 FIRE 报告 | Generate FIRE report | FIRE dashboard |
| 11 | 本地加密备份/恢复 | Encrypted backup / restore | Settings → backup |
| 12 | 导出 | Export | Settings → export |

Task #1 is implemented as the seed: `test/flow/net_worth_flow_test.dart`.

## 4. Layers — what each is for and how to write it

### Unit + Widget (base, ~75%) — KEEP
`flutter test`, in-memory data via `makeTestDatabase()`. Override the data
layer in tests, never wrap providers in static `AsyncValue`. This is where
form logic, money/FX, domain services, and individual widgets are proven.

### Integration (real chain, ~10%)
Exercises **repository → real Drift → read model** with a real
`AppDatabase` (in-memory, SQLCipher bypassed), so writes and stream reads
are real. `test/integration/support/integration_env.dart` wires a real DB
into the production provider graph (`appDatabaseProvider` overridden),
faking only the non-deterministic edges — auth (`AuthLocalOnly` → Noop
outbox) and the HLC stamper (`makeStubStamper()`, the sanctioned seam).
Everything downstream is real: `accountsStreamProvider`,
`dashboardSnapshotProvider`, the `DashboardAggregator`.

Seeds (`test/integration/`, tagged `integration`, headless):
- `account_net_worth_integration_test.dart` — creates an account through
  the real repository, asserts it surfaces through the live stream, and
  that the net-worth read model resolves to zero for an empty ledger.
- `liability_net_worth_integration_test.dart` — the read model *reacts*
  on the negative side: a 120k CNY loan written through the real repository
  flows through the generated amortization schedule → `LiabilitySummary` →
  `DashboardAggregator`, driving net worth to -120k.
- `asset_net_worth_integration_test.dart` — the positive side: a 50k CNY
  term deposit records an append-only valuation observation that flows
  through the prices table → `ManualAssetValuation` → aggregator, raising
  net worth to +50k.

Together the three integration tests prove the net-worth read model both
resolves (empty) and moves in both directions through the real data layer.

### Flow / Task (Page Objects, ~4%)
`test/flow/` — boots the real `NaviWealthApp` (real router, shell, widgets)
with the data layer stubbed to deterministic streams, and drives a
multi-screen task through **Page Objects** (`test/flow/support/page_objects.dart`).

```dart
// Selectors live in the Page Object; the Task reads like a user story.
final shell = AppShell(tester)..expectMounted();
await shell.openTab('Wealth');
await shell.openTab('Today');
HomePage(tester).expectLanded();
```

When the layout is refactored, only the Page Object changes; the Task
body does not. Use a bounded `settle()` pump, never `pumpAndSettle`
(stream/timer surfaces can hang).

### Contract (Dart↔Rust↔wire, ~5%)
The client and the Rust Worker share a wire format but no generated
types. Today: `test/core/ai/contracts/contracts_roundtrip_test.dart`
(ContextPack snake_case stability) + `tool/check-enum-mirror.sh`
(grep-based Dart↔Rust enum sync). Target: promote the enum mirror to a
generated SSOT and add a `sync-v2` wire roundtrip asserted against the
**actual Rust serializer output** (golden JSON), not a hand-written copy.

### Golden (visual, ~5%)
`test/golden/` via golden_toolkit, Linux-pinned (`flutter_test_config.dart`
skips comparison off Linux; CI `golden-regression` job is the source of
truth). 16 surfaces × {dark, colorblind} today. Expand to every Task's
primary surface and add responsive breakpoints (phone/tablet/web) ahead
of layout refactors.

### Sync protocol E2E (best-in-class — keep)
`test/e2e/sync_e2e_test.dart` + `SyncCluster`/`VirtualDevice` simulate
multi-device convergence with deterministic time. 70 documented cases in
`docs/sync-protocol-tests.md`. This is the canonical Task #5 coverage.

### AI exploratory + semantic (~1%, nightly, non-blocking)
Drive the app from natural-language Tasks (Computer-Use style), screenshot
each surface, and have a vision model assert "net worth + allocation +
account list visible; no overlap/truncation." Catches layout breakage the
deterministic layers can't. Strictly non-blocking.

## 5. CI gate design

Target: **< 12 min** of blocking PR checks; heavy/flaky-prone work nightly.

```
PR  ├─ analyze --fatal-infos + boundary lints      (mobile.yml, existing)
    ├─ build_runner freshness + l10n parity         (existing)
    ├─ flutter test (unit + widget + flow + integ.)  ~3 min   flow/integ run here today
    ├─ golden regression (Linux-pinned)             ~30 s    (existing)
    ├─ cargo test (backend, native host)            ~1 min   ← ADDED
    ├─ contract tests                               ~30 s
    └─ web smoke (chromium)                         ~2 min   ← ADDED (web-smoke.yml)
Nightly ├─ web smoke full matrix (Firefox/WebKit/OPFS)       ← ADDED
        └─ AI exploratory + semantic                         (future)
```

**Known-failing ratchet.** `tool/check-known-failing-tests.sh` pins the
failing-test footprint (design-system API rot, ~50 files). It is now a
**monotonic ratchet**: a new red file fails CI (regression), and a file
that is fixed but still listed *also* fails CI (forcing the allowlist to
shrink). The footprint may only ever decrease. Burn it to zero is a
standing goal; see §7.

## 6. On-device integration (`integration_test/`) — the next layer

`test/flow/` runs headless under `flutter test` and stubs the data layer.
It does **not** exercise SQLCipher, the platform secure-storage key path,
or a real on-device Drift connection. The on-device layer closes that gap:

1. Add the `integration_test` dev dependency to `apps/mobile/pubspec.yaml`.
2. Create `apps/mobile/integration_test/` with the same Page Objects
   (promote `test/flow/support/` to a shared location).
3. Boot with a **real** `AppDatabase` (override `appDatabaseProvider` with a
   shared instance), seed via real repositories, assert rendered outcomes.
4. Run on an emulator in a dedicated, possibly nightly, CI job (slower;
   keep off the fast PR path unless it stays under budget).

This is where Task #11 (backup/restore) and the SQLCipher PRAGMA path get
real coverage.

## 7. Roadmap

**P0 — close CI holes (done in this change set):**
- ✅ Backend tests run in CI — `cargo test` (native host) added to `backend.yml`.
  The 11 JWT-domain / sync-LWW tests now gate PRs.
- ✅ Web smoke wired up — `web-smoke.yml`: chromium on PRs, full matrix nightly.
- ✅ Known-failing gate is now a monotonic ratchet (fixed-but-listed fails CI).
- ✅ Flow layer seeded — `test/flow/` with Page Object Model + Task #1.
- ✅ Integration layer seeded — `test/integration/` real-Drift harness +
  account-persistence test + value-moving liability → net-worth test.
- Both new layers run inside the existing `flutter test` job (tagged `flow`
  / `integration` in `dart_test.yaml`); no emulator required.

**P1 — fill the missing layers:**
- Grow `test/flow/` from 1 → the 12 Tasks in §3.
- ✅ Net-worth read model covered both directions (assets, liabilities);
  next: securities trades (holdings → net worth) through the real chain.
- Stand up on-device `integration_test/` (§6) for the SQLCipher boot path.
- Contracts-as-code: generated enum SSOT + `sync-v2` wire roundtrip vs the
  Rust serializer.
- Expand golden coverage to each Task surface + responsive breakpoints.
- Burn down `tool/known-failing-tests.txt` toward empty.

**P2 — modern differentiators:**
- State-machine traversal tests over `ConventionalAsyncNotifier` states
  (Initial→Loading→Loaded→Error) for sync / import / AI-chat graphs.
- AI exploratory + semantic (vision) validation, nightly, non-blocking.

## 8. Conventions

- Flow Page Objects own selectors; flow tests own outcome assertions.
- Tag flow tests `flow` so the suite can be split from the unit gate later.
- Never `pumpAndSettle` a streaming surface — use a bounded pump.
- Money asserted as `Decimal`/`Money`, never `double`.
- Coverage gate (`codecov.yml`): project 60%, patch 70%; generated files excluded.
