# NaviWealth — Testing Strategy (Production-Grade Delivery)

**Status:** Active SSOT for test architecture. Owns the test pyramid, the
Task spine, the CI gate design, and current coverage/gaps. Read this
before adding a new test *layer* or changing a CI test gate.

Related: `docs/sync/sync-protocol-tests.md` (sync case matrix), `docs/sync/sync-e2e-manual.md`
(manual multi-device checklist), `docs/development/web-compat-matrix.md` (browser support),
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
       Flow / Task (Page Objects)   ~4%   17 journeys, test/flow + integration_test
       Contract (Dart↔Rust↔wire)     ~5%   schema-driven, blocking
      Golden (visual regression)     ~5%   expanded surfaces + breakpoints, Linux-pinned
     Integration (real Drift chain)  ~10%  UI→repo→Drift→domain, real connection
    Unit + Widget (the base)         ~75%  KEEP — ~1,765 unit + ~365 widget today
```

Percentages are directional, not quotas. The base stays unit-heavy.

## 3. The Task spine (the stable contract)

These 17 journeys are the stable product-test backbone. Coverage can use a
headless flow, protocol E2E, on-device integration, or a combination appropriate
to the task. Page Objects and primary-surface goldens are added where the UI is
part of the durable contract; test-file count is not the journey count.

| # | Task (cn) | Task (en) | Primary surface |
|---|-----------|-----------|-----------------|
| 1 | 查看净资产 | View net worth | Home / Today |
| 2 | 添加账户 | Add account | Wealth → account editor |
| 3 | 添加交易 | Add transaction | Investment → trade entry |
| 4 | 账户间转账 | Transfer between accounts | Activity → transfer entry |
| 5 | 导入账单/CSV | Import CSV / statement | Ingest |
| 6 | 管理月度预算 | Manage monthly budget | Plan → Budget |
| 7 | 多端同步 | Multi-device sync | Sync protocol/status |
| 8 | AI 问答 | Ask the AI | AI sheet/chat |
| 9 | 执行资产分析 | Run portfolio analysis | Analytics |
| 10 | 再平衡 | Rebalance | Rebalance execution |
| 11 | 期权收入计划 | Plan options income | Options income |
| 12 | 生成 FIRE 报告 | Generate FIRE report | FIRE dashboard |
| 13 | 本地加密备份/恢复 | Encrypted backup / restore | Settings → backup |
| 14 | 导出 | Export | Settings → export |
| 15 | 启用可选域 | Enable optional domain | Settings → Domain management |
| 16 | 捕获知识笔记 | Capture Knowledge note | KnowledgeOS → Inbox |
| 17 | 处理 Life 信号并闭环 | Act on a Life signal | Life → Execution Today → Review |

The repository currently has 18 `test/flow/*_test.dart` files. They are not a
second task inventory: `navigation_flow_test.dart` is an auxiliary shell route
smoke, backup/export use separate flows, and Task 17 has separate Health and
Finance/Knowledge evidence scenarios. Task 7 is primarily proven by Sync v3
contract and deterministic multi-device E2E coverage rather than a page flow.

## 4. Layers — what each is for and how to write it

### Unit + Widget (base, ~75%) — KEEP
`flutter test`, in-memory data via `makeTestDatabase()`. Override the data
layer in tests, never wrap providers in static `AsyncValue`. This is where
form logic, money/FX, domain services, and individual widgets are proven.

### Integration (real chain, ~10%)
Exercises **repository → real Drift → read model** with a real
`AppDatabase` (unkeyed in-memory, production encryption bootstrap bypassed), so
writes and stream reads are real. `test/integration/support/integration_env.dart` wires a real DB
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

- `securities_net_worth_integration_test.dart` — the deepest input path:
  a buy recorded as double-entry postings is reconstructed into a holding
  by `HoldingService` from the ledger, valued by a fixed-price fake
  resolver (offline, deterministic), and folded into net worth (+2000).

Together the four integration tests prove the net-worth read model resolves
(empty) and moves in every direction — manual assets, liabilities, and
ledger-reconstructed securities — through the real data layer.

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

Current flow mapping:

| Tasks | Flow coverage |
|---|---|
| 1–6 | `net_worth`, `add_account`, `add_transaction`, `transfer`, `import_statement`, `budget` |
| 8–12 | `ai_chat`, `portfolio_analysis`, `rebalance`, `options_income`, `fire_report` |
| 13–16 | `restore_backup`, `export_backup`, `domain_opt_in`, `knowledge_capture` |
| 17 | `life_execution_loop`, `life_finance_knowledge_execution` |

`navigation_flow_test.dart` is an auxiliary Finance shell smoke. Keep selectors
inside Page Objects and outcomes inside the task test. Do not create a new flow
just to mirror a page when an existing durable journey already covers it.

### Contract (Dart↔Rust↔wire, ~5%)
The client and the Rust Worker share a wire format but no generated
types. Today: `test/core/ai/contracts/contracts_roundtrip_test.dart`
(ContextPack snake_case stability) + `tool/check-ai-contract-wire-enums.sh`.
The script gates the mobile-local AI enum wire manifest
(`docs/fixtures/ai_contract_wire_enums.json`) against
`apps/mobile/tool/dump_ai_contract_wire_enums.dart`, so enum wire strings are
generated from Dart code instead of inferred by grep. The `sync-v3` shared
fixtures are partly serializer-owned too: `tool/check-sync-wire-fixtures.sh`
compares the
server tombstone fixture consumed by Dart against the backend
`dump-sync-wire-fixture` binary, which emits the **actual Rust
`RowChange` serializer output**. The client-push fixture is Dart-owned:
`tool/check-sync-client-wire-fixtures.sh` compares it against
`apps/mobile/tool/dump_sync_wire_fixture.dart`, which emits the actual
`RowChange.toJson()` output and the full client `/sync` request envelope.
The Rust gate also covers the full server `/sync` response envelope, including
edge-case envelopes for empty pages, `more` pagination, and no-accepted-row
responses. Keep the enum manifest and sync fixture set complete as the contract
surface evolves.

### Golden (visual, ~5%)
`test/golden/` uses Flutter's native `matchesGoldenFile` matcher through the
repository's deterministic harness. Comparison remains Linux-pinned (other
hosts still pump the surfaces; CI `golden-regression` is the source of truth).
17 golden test files currently produce 68 PNG baselines; page
surfaces primarily run dark + colorblind variants, while AI primitive
goldens use component-scoped light surfaces. Expand to every Task's
primary surface and add responsive breakpoints (phone/tablet/web) ahead
of layout refactors.

### Sync protocol E2E (best-in-class — keep)
`test/e2e/sync_e2e_test.dart` + `SyncCluster`/`VirtualDevice` simulate
multi-device convergence with deterministic time. The current blocking bundle
also includes `test/e2e/finance_ledger_e2e_test.dart`, so protocol behavior and
Finance ledger convergence are proven together. `sync_e2e_test.dart` carries
the P1-G E2E-1..5 markers; `docs/sync/sync-protocol-tests.md` remains the broader
case matrix. This is the canonical Task #7 coverage.

`test/e2e/agent_runtime_finance_memory_e2e_test.dart` is a gated real-LLM
runtime scenario. It is present in the suite by default, but the provider-backed
path only runs when `RUN_REAL_LLM_E2E=1` and `E2E_LLM_API_KEY` are set. The
scenario exercises a 14-day agent-runtime validation task that combines
FinanceOS budget checks, ExecutionOS planning/progress proposals, KnowledgeOS
capture, memory recall/write, ChatTurn tool continuation, and FRB/native LLM
streaming. The domain tool specs are selected from the same FinanceOS,
ExecutionOS, and KnowledgeOS registrations used by `DomainPack` composition,
while the test dispatcher supplies deterministic scenario data. Use
`E2E_LLM_PROVIDER`, `E2E_LLM_MODEL`, `E2E_LLM_BASE_URL`,
`E2E_LIFEOS_NATIVE_LIBRARY_PATH`, `E2E_LLM_MAX_TOOL_ROUNDS`, and
`E2E_LLM_TIMEOUT_SECONDS` to pin the provider/model/runtime for manual release
gates or nightly smoke runs. The provider-backed test has a 10-minute
Flutter test timeout; `E2E_LLM_TIMEOUT_SECONDS` controls each turn's stream
timeout inside that outer test window. `test/e2e/agent_runtime_e2e_support_test.dart`
keeps the reusable real-LLM gate and DomainPack tool-subset export behavior
pinned without calling a provider. When the real provider path runs, the test
prints live `[real-llm-e2e]` progress lines for turn start, tool calls/results,
LLM spans, usage, text-character counts, errors, and done events without dumping
full prompts, tool payloads, or provider secrets.

### AI exploratory + semantic (~1%, nightly, non-blocking)
`.github/workflows/ai-semantic.yml` runs the deterministic surrogate nightly
and on manual dispatch via `apps/mobile/tool/check-ai-semantic-surfaces.sh`.
That surrogate renders the net-worth, allocation, and account-list AI surfaces
at phone width, asserts the key facts are visible, checks the semantics tree for
machine-readable labels, and fails on layout exceptions. The same workflow has a
non-blocking `AI_VISION_AGENT_WEBHOOK_URL` hook for an external screenshot +
vision-model validator. The deterministic job writes
`ai-semantic-vision-artifacts` (PNG screenshot + manifest); the webhook payload
includes the run URL, artifact API URL, and manifest so the external service can
assert "net worth + allocation + account list visible; no overlap/truncation."
Catches layout breakage the deterministic layers can't. Strictly non-blocking.

The blocking deterministic AI quality layer remains part of ordinary Flutter
tests. `memory_answer_quality_eval_test.dart` prints a privacy-safe JSON
aggregate containing pass rate and forbidden/missing claim/evidence failure
counts. Agent outcome cases bind every expected evidence type to an exact route
or dynamic route family; the evaluator rejects cross-workflow destinations.
`router_test.dart` opens every action route and a representative path from each
evidence route family through the production router, so declared destinations
must resolve rather than merely resemble paths.

## 5. CI gate design

Target: **< 12 min** of blocking PR checks; heavy/flaky-prone work nightly.

```
PR  ├─ analyze --fatal-infos + boundary lints      (mobile.yml, existing)
    ├─ build_runner freshness + l10n parity         (existing)
    ├─ flutter test (4 shards; unit/widget/flow/integ.)       flow/integ run here today
    ├─ golden regression (Linux-pinned)             ~30 s    (existing)
    ├─ cargo test (backend, native host)            ~1 min   ← ADDED
    ├─ contract tests                               ~30 s
    ├─ native ASR pinned-WAV regression             speech changes, macOS
    └─ web smoke (chromium)                         ~2 min   ← ADDED (web-smoke.yml)
Nightly ├─ web smoke full matrix (Firefox/WebKit/OPFS)       ← ADDED
        ├─ AI semantic surrogate                             ← ADDED (ai-semantic.yml)
        └─ external AI vision-agent webhook + screenshot artifacts ← OPTIONAL
Weekly ─ native ASR pinned model/WAV exact-transcript smoke
```

**Zero-failure unit/widget gate.** `mobile.yml` distributes
`flutter test --coverage --reporter=expanded --exclude-tags=golden` across four
deterministic shards with bounded concurrency. There is no known-failing allowlist:
any non-golden test failure fails CI. Each shard always uploads its
machine-readable JSON event stream for seven days, so a timeout or runner
failure retains the last completed test and error events instead of leaving
only an incomplete console log.
Golden PNG comparison remains isolated in the Linux-pinned
`golden-regression` job.

**Native ASR regression gate.** `.github/workflows/asr-native-smoke.yml` runs
on speech-runtime dependency changes, every Monday, and by manual dispatch. It
downloads model and Mandarin WAV fixtures pinned by SHA-256, loads the actual
macOS `sherpa_onnx` dynamic libraries, and requires an exact transcript from
the production streaming recognizer configuration. The runner emits audio
duration, inference duration, and real-time factor without logging transcript
content as diagnostics. Run the same gate locally from `apps/mobile/` with
`tool/run-asr-native-smoke.sh <cache-dir>`.

## 6. On-device integration (`integration_test/`)

`test/flow/` runs headless under `flutter test` and stubs the data layer.
It does **not** exercise the platform secure-storage key path or a real
on-device Drift connection. Focused native file tests exercise SQLCipher on
the host; the on-device layer closes the packaged-platform gap:

✅ Seeded. `apps/mobile/integration_test/database_boot_integration_test.dart`
opens the **real** file-backed `AppDatabase` through `openAppConnection()`
(SQLCipher PRAGMA + path_provider +
`createInBackground` + on-disk migration to schemaVersion). It requires a
non-plaintext file header, rejects a wrong key, and proves a write survives a
full close/reopen cycle — the production connection every headless test
bypasses via `NativeDatabase.memory`. Its Android-only secure-storage case then
uses the production `FlutterSecureKeyStore` and key resolver, proves the
random 256-bit key survives a new store instance, rejects a missing key beside
encrypted bytes, restores the original key, and reopens the same database.
`apps/mobile/integration_test/backup_restore_integration_test.dart` then boots
the real app shell with that file-backed DB, drives Settings → Backup &
Restore through Page Objects, and restores encrypted bytes through
`BackupService` into the same on-disk database. Its failure case forces a row
insert error after the destructive transaction has started, closes the
database, reopens the same file, and proves both the previous account and its
outbox pointer survived the durable rollback.
Successful export and restore also emit `core.backup.*.completed` diagnostic
events with only archive schema version, full/domain scope, table count, total
row count, byte count where applicable, duration, and outcome. `RestoreResult`
exposes the same aggregate through `toDiagnosticJson()`; table names, row ids,
and payload values are deliberately absent and covered by a privacy assertion.
The same suite pins the generic backup's portable money contract with a
cross-currency liability: ISO currency remains `USD`, and principal, interest
rate, and monthly payment remain exact decimal strings through decrypt and
restore. Machine values must never contain currency symbols, grouping
separators, or locale-dependent display text.
`backup_process_interruption_integration_test.dart` adds the destructive
Android case as a two-process protocol. Its interrupt phase restores a large,
valid archive and the workflow waits for the production log emitted after the
transactional wipe, then sends `adb shell am force-stop`. A separately compiled
verify phase reopens the same app database and requires the previous account
and outbox pointer to be intact. The first phase uses Flutter's
`--no-uninstall` option so the fresh process observes the same application data;
the workflow fails if restore commits before the force-stop arrives. The
runner binds every invocation to the explicit `adb` serial, requires the app
to have a live PID at the destructive-wipe marker, and verifies that PID is
gone after `am force-stop`. The fresh process must emit a dedicated rollback
evidence marker after both account and outbox assertions; a skipped verifier
therefore cannot create a false green run.
`apps/mobile/integration_test/journal_repository_integration_test.dart` covers
a high-value non-UI write path: `JournalEntryRepository.create()` writes a
balanced journal entry, postings, and Drift-backed outbox pointers through the
same production file-backed connection, then proves they survive close/reopen.
The `integration_test` dev dependency is wired in `pubspec.yaml`.

Because it needs a real device, it runs via the `integration-device.yml`
workflow on an Android emulator (nightly + manual + PRs touching the
harness, backup, Sync, or persistence code), not the unit-test VM. The workflow
retains a machine-readable event stream, the ordinary integration log, a
privacy-safe database-encryption evidence JSON, the process-interruption log,
and its separate interruption evidence JSON. `run-android-integration.sh`
fails even after a nominally green Flutter run unless dedicated markers prove
SQLCipher availability, encrypted bytes, correct/wrong-key behavior, plaintext
migration, Android Keystore persistence and fail-closed behavior, successful
backup restore, and durable failed-restore rollback. Both summaries contain
only platform, API level, commit, timestamp, fixed booleans, and—in the
interruption case—the exit status and fixed preserved account/outbox counts.
Run the ordinary suite locally with
`bash tool/run-android-integration.sh <android-device>` and the forced-stop
case with `bash tool/run-android-backup-interruption.sh`; neither can run on the
headless `flutter test` host.

`database_encryption_test.dart` also creates real files with the bundled
SQLCipher library. It pins correct-key reopen, wrong-key byte preservation,
plaintext export migration, valid and corrupt interrupted-swap recovery, key
loss fail-closed behavior, and the exact reset artifact allowlist. Widget tests
pin the root recovery gate: only missing/invalid/wrong-key states offer a
destructive reset, while migration and unknown failures preserve local bytes.

## 7. Current Coverage And Known Gaps

Current baseline:

- Backend tests, Web smoke, non-golden Flutter tests, Linux-pinned goldens,
  contract fixtures, and boundary lints are blocking CI checks.
- Headless flows cover the 17-task inventory with auxiliary route smoke where
  useful.
- Real-Drift integration covers net worth through manual assets, liabilities,
  and ledger-reconstructed securities.
- Android on-device integration owns database encryption, boot/migration/reopen,
  backup/restore, and a journal repository write. A green packaged emulator run
  remains required release evidence for newly added SQLCipher assertions.
- Sync v3 request/response fixtures are generated from the Dart/Rust
  serializers, including pagination and accepted-row edge cases.
- State-machine tests cover conventional async state, chat streaming,
  ingestion, Sync retry/progress, and diagnostic providers.
- The nightly AI semantic surrogate verifies selected finance surfaces and can
  hand artifacts to an optional external vision validator.
- Managed speech unit/widget tests cover exclusive sessions, startup and stream
  failures, maximum duration, background finalization, user-edit protection,
  transcript-free diagnostics, and repeated-session cleanup. A pinned native
  ASR inference smoke covers the Dart-to-native model path on macOS.

Known coverage gaps are descriptive, not a second product roadmap:

- iOS native build/load smoke is not present in CI.
- Android SQLCipher packaging and Keystore behavior still require the emulator
  integration gate; host native tests do not substitute for device evidence.
- Goldens and on-device tests should deepen existing durable journeys when a
  real rendering or platform risk is identified.
- Runtime skips remain limited by `testing_infrastructure_contract_test.dart`
  to platform/native/artifact dependency gates; product regressions must not
  create a failure allowlist.

## 8. Conventions

- Flow Page Objects own selectors; flow tests own outcome assertions.
- Tag flow tests `flow` so the suite can be split from the unit gate later.
- Never `pumpAndSettle` a streaming surface — use a bounded pump.
- Money asserted as `Decimal`/`Money`, never `double`.
- Coverage gate (`codecov.yml`): project 60%, patch 70%; generated files excluded.
