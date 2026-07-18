# Garmin Connect Integration

> **Status**: Current implementation reference; Phase 1–2 delivery complete
> **Date**: 2026-06-08
> **Domain**: HealthOS
> **Scope**: Add Garmin Connect as a health data provider — Rust core, Dart shell

---

## 0. Architecture Decision

### Final Architecture: Rust Core + Dart Shell

```text
Flutter / Dart (product shell)
  ├─ 登录 UI / MFA 输入
  ├─ 同步状态展示
  ├─ Health Dashboard
  ├─ HealthKit / Health Connect 权限桥 (platform adapter)
  └─ FRB 调用包装

Rust / lifeos_native (local data core)
  ├─ GarminClient          HTTP + SSO + token + cookie
  ├─ GarminAuthStateMachine  登录 → MFA → 已认证 → 刷新
  ├─ GarminTokenStore       持久化 token / cookie (接口层)
  ├─ GarminRateLimiter      429 backoff + 并发控制
  ├─ GarminEndpointClient   按日期分页拉数据
  ├─ GarminSnapshotMapper   Garmin JSON → HealthSnapshot
  ├─ HealthProvider trait   统一 provider 抽象
  ├─ HealthSyncEngine       cursor + 去重 + 增量同步
  └─ HealthReadModel        归一化后供 Dart 消费的快照
```

### Why Rust, Not Dart

| 维度 | Dart | Rust |
|---|---|---|
| Garmin SSO / OAuth / token refresh | 可以做，但会让 `features/health` 变成协议层 + UI 的混合体 | 天然适合网络协议 + 状态机 |
| Rate limit / retry / backoff | Dart `http` 没有内置重试框架 | `reqwest` + tower middleware，标准化 |
| 后台同步 / CLI / daemon | 依赖 Flutter isolate | Flutter / CLI / daemon 共用同一 core |
| 未来多 provider 统一 | 每个 provider 各写一套 Dart 适配 | `HealthProvider` trait，一个接口 |
| 协议变更维护 | 散在 feature 里 | 集中在 crate 里，snapshot 测试易写 |
| 与 NaviWealth 方向一致 | — | local-first, Rust core, Flutter shell |

### 但 HealthKit / Health Connect 不进 Rust

HealthKit (iOS) 和 Health Connect (Android) 有系统权限弹窗、系统服务依赖、平台 SDK 调用。这些由 Dart `package:health` adapter 负责，Rust 只做归一化：

```text
HealthKit (iOS)     → Dart platform adapter → raw data → Rust normalize → HealthSnapshot
Health Connect (Android) → Dart platform adapter → raw data → Rust normalize → HealthSnapshot
Garmin Connect (HTTP API) → Rust client → Rust normalize → HealthSnapshot
```

---

## 1. Rust Crate Structure

扩展 `apps/mobile/native/lifeos_native/`，新增 `health` 模块：

```
lifeos_native/
  src/
    api/
      mod.rs                 # pub mod embedder + pub mod health
      embedder.rs            # existing
      health/
        mod.rs               # pub mod garmin; pub mod provider; pub mod sync_engine
        provider.rs          # HealthProvider trait + HealthSnapshot types
        garmin/
          mod.rs             # GarminProvider impl
          client.rs          # HTTP client, SSO, cookie jar
          auth.rs            # AuthStateMachine (Login → Mfa → Authenticated → Refreshing)
          token_store.rs     # trait TokenStore + in-memory impl (Dart provides persistence)
          rate_limiter.rs    # Token bucket + 429 exponential backoff
          endpoints.rs       # Garmin API endpoint wrappers
          mapper.rs          # Garmin JSON → HealthSnapshot
        sync_engine.rs       # Cursor management, incremental sync, dedup
```

### 1.1 `Cargo.toml` Dependencies

```toml
[dependencies]
# existing
fastembed = { ... }
anyhow = "1.0.102"
flutter_rust_bridge = "=2.13.0-beta.4"

# new: health / garmin
reqwest = { version = "0.13.4", features = ["json", "cookies", "rustls", "form"], default-features = false }
serde = { version = "1.0.228", features = ["derive"] }
serde_json = "1.0.150"
tokio = { version = "1.52.3", features = ["time", "sync", "macros"] }
chrono = { version = "0.4.45", features = ["serde"] }
uuid = { version = "1.23.2", features = ["v4"] }
```

Note: `reqwest` with the `rustls` feature avoids OpenSSL linking issues on
iOS/Android. The `form` feature is required for Garmin OAuth token exchange.
`tokio` is already transitive via `reqwest`; we expose `time`, `sync`, and
`macros` for the native async bridge tests.

### 1.2 `HealthProvider` Trait

```rust
// lifeos_native/src/api/health/provider.rs

use chrono::NaiveDate;

/// Unified health data provider contract.
/// Every source (Garmin, HealthKit, Health Connect, manual) implements this.
pub trait HealthProvider: Send + Sync {
    /// Provider display name.
    fn name(&self) -> &str;

    /// Check if the provider has valid credentials.
    fn is_authenticated(&self) -> bool;

    /// Sync daily metrics for the given date range (inclusive).
    async fn sync_daily_range(
        &self,
        from: NaiveDate,
        to: NaiveDate,
    ) -> anyhow::Result<HealthSnapshot>;

    /// Sync activity/workout sessions for the given date range.
    async fn sync_activities(
        &self,
        from: NaiveDate,
        to: NaiveDate,
    ) -> anyhow::Result<Vec<ActivityRecord>>;
}

/// Normalized daily health snapshot — provider-agnostic.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct HealthSnapshot {
    pub steps: Vec<DailyMetric>,
    pub sleep_sessions: Vec<SleepSession>,
    pub resting_hr: Vec<DailyMetric>,
    pub hrv: Vec<DailyMetric>,
    pub heart_rate: Vec<DailyMetric>,
    pub active_energy: Vec<DailyMetric>,
    pub vo2_max: Vec<DailyMetric>,
    pub weight: Vec<PointMetric>,
    pub body_fat: Vec<PointMetric>,
    pub floors_climbed: Vec<DailyMetric>,
    pub respiratory_rate: Vec<DailyMetric>,
    // Garmin-specific (stored in payload_json on Dart side)
    pub body_battery: Vec<BodyBatteryDay>,
    pub stress: Vec<DailyMetric>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DailyMetric {
    pub id: String,          // stable: "garmin:steps:2026-06-07"
    pub date: NaiveDate,
    pub value: f64,
    pub unit: String,
    pub source_device: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SleepSession {
    pub id: String,
    pub started_at: String,  // ISO 8601
    pub duration_seconds: u32,
    pub source_device: Option<String>,
    pub stage_histogram_json: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ActivityRecord {
    pub id: String,
    pub activity_type: String,
    pub started_at: String,
    pub duration_seconds: u32,
    pub total_energy_kcal: Option<f64>,
    pub total_distance_meters: Option<f64>,
    pub source_device: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PointMetric {
    pub id: String,
    pub measured_at: String,
    pub value: f64,
    pub unit: String,
    pub source_device: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BodyBatteryDay {
    pub id: String,
    pub date: NaiveDate,
    pub min: u8,
    pub max: u8,
    pub charged: u8,    // overnight charge
    pub drained: u8,    // daytime drain
}
```

### 1.3 `GarminClient` — HTTP + Auth

```rust
// lifeos_native/src/api/health/garmin/client.rs

pub struct GarminClient {
    http: reqwest::Client,
    auth: GarminAuthState,
    token_store: Box<dyn TokenStore>,
    rate_limiter: GarminRateLimiter,
    base_url: String,  // "https://connect.garmin.com"
}

impl GarminClient {
    pub async fn new(token_store: Box<dyn TokenStore>) -> anyhow::Result<Self>;
    pub async fn authenticate(&mut self, email: &str, password: &str) -> anyhow::Result<AuthResult>;
    pub async fn submit_mfa(&mut self, code: &str) -> anyhow::Result<AuthResult>;
    pub async fn refresh_token(&mut self) -> anyhow::Result<()>;
    pub fn is_authenticated(&self) -> bool;

    // Endpoint methods — all rate-limited internally
    pub async fn fetch_daily_summary(&self, date: NaiveDate) -> anyhow::Result<serde_json::Value>;
    pub async fn fetch_steps(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<DailyMetric>>;
    pub async fn fetch_sleep(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<SleepSession>>;
    pub async fn fetch_rhr(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<DailyMetric>>;
    pub async fn fetch_hrv(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<DailyMetric>>;
    pub async fn fetch_activities(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<ActivityRecord>>;
    pub async fn fetch_body_battery(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<BodyBatteryDay>>;
    pub async fn fetch_stress(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<DailyMetric>>;
    pub async fn fetch_weight(&self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<Vec<PointMetric>>;
    pub async fn fetch_vo2_max(&self) -> anyhow::Result<Option<DailyMetric>>;
}
```

### 1.4 `GarminAuthStateMachine`

```rust
// lifeos_native/src/api/health/garmin/auth.rs

#[derive(Debug, Clone, PartialEq)]
pub enum GarminAuthState {
    Unauthenticated,
    PendingMfa { session_ticket: String },
    Authenticated { expires_at: DateTime<Utc> },
    Refreshing,
    Error { message: String },
}

pub enum AuthResult {
    Authenticated,
    MfaRequired,
    Failed(String),
}
```

### 1.5 `TokenStore` Trait

```rust
// lifeos_native/src/api/health/garmin/token_store.rs

#[async_trait]
pub trait TokenStore: Send + Sync {
    async fn load(&self) -> anyhow::Result<Option<StoredSession>>;
    async fn save(&self, session: &StoredSession) -> anyhow::Result<()>;
    async fn clear(&self) -> anyhow::Result<()>;
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct StoredSession {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at: String,  // ISO 8601
    pub cookies: HashMap<String, String>,
}
```

Dart provides the persistence implementation via `flutter_secure_storage`:

```dart
class FlutterSecureTokenStore implements TokenStore {
  // FRB callback bridge: Dart implements TokenStore trait methods
  // Rust calls load/save/clear through the bridge
}
```

### 1.6 `HealthSyncEngine`

```rust
// lifeos_native/src/api/health/sync_engine.rs

pub struct HealthSyncEngine {
    providers: Vec<Box<dyn HealthProvider>>,
    cursor_store: Box<dyn CursorStore>,
}

impl HealthSyncEngine {
    /// Sync all providers for the given range.
    /// Uses cursor to avoid re-fetching already-synced dates.
    pub async fn sync_range(&mut self, from: NaiveDate, to: NaiveDate) -> anyhow::Result<SyncOutcome>;

    /// Sync a single provider.
    pub async fn sync_provider(&mut self, provider_name: &str, from: NaiveDate, to: NaiveDate) -> anyhow::Result<SyncOutcome>;
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct SyncOutcome {
    pub provider: String,
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub metrics_count: usize,
    pub activities_count: usize,
    pub errors: Vec<String>,
    pub duration_ms: u64,
}
```

### 1.7 FRB API Surface

```rust
// lifeos_native/src/api/health/mod.rs — public FRB surface

/// Initialize the Garmin client. Returns serialized auth state.
pub fn garmin_init(token_json: Option<String>) -> Result<String>;

/// Authenticate with Garmin Connect.
pub async fn garmin_authenticate(email: String, password: String) -> Result<String>;

/// Submit MFA code.
pub async fn garmin_submit_mfa(code: String) -> Result<String>;

/// Get current auth state.
pub fn garmin_auth_state() -> Result<String>;

/// Sync health data for a date range. Returns SyncOutcome JSON.
pub async fn garmin_sync_range(from: String, to: String) -> Result<String>;

/// Get the last sync cursor.
pub fn garmin_sync_cursor() -> Result<String>;

/// Clear stored credentials.
pub async fn garmin_logout() -> Result<()>;
```

FRB generates Dart bindings automatically. Dart side calls:

```dart
final outcome = await garminSyncRange(from: '2026-05-09', to: '2026-06-08');
```

---

## 2. Dart Shell Layer

### 2.1 File Structure

```
apps/mobile/lib/features/health/data/
  garmin/
    garmin_bridge.dart           # FRB wrapper: garmin_init/auth/sync/logout
    garmin_token_store_dart.dart # flutter_secure_storage → Rust TokenStore callback
    garmin_sync_controller.dart  # Riverpod controller: auth state, sync status, errors
    garmin_snapshot_writer.dart  # HealthSnapshot → HealthMetric rows → Drift upsert
  providers.dart                 # MODIFIED: add garmin providers
  health_sync_service.dart       # MODIFIED: call garmin_snapshot_writer when Garmin is active

apps/mobile/lib/features/health/ui/
  garmin_account_bind_sheet.dart # Email/password/MFA login flow
  garmin_sync_status_card.dart   # Connection state + last sync + "Sync now"
  health_source_selector.dart    # Choose between HealthKit/HC/Garmin
```

### 2.2 `GarminBridge` — FRB Wrapper

```dart
/// Thin wrapper around FRB-generated bindings.
/// Handles serialization and error mapping.
class GarminBridge {
  Future<GarminAuthState> init({String? storedTokenJson}) async {
    final result = await garminInit(storedTokenJson);
    return GarminAuthState.fromJson(jsonDecode(result));
  }

  Future<GarminAuthState> authenticate(String email, String password) async {
    final result = await garminAuthenticate(email: email, password: password);
    return GarminAuthState.fromJson(jsonDecode(result));
  }

  Future<GarminAuthState> submitMfa(String code) async {
    final result = await garminSubmitMfa(code: code);
    return GarminAuthState.fromJson(jsonDecode(result));
  }

  Future<GarminSyncOutcome> syncRange(DateTime from, DateTime to) async {
    final result = await garminSyncRange(
      from: from.toIso8601String().substring(0, 10),
      to: to.toIso8601String().substring(0, 10),
    );
    return GarminSyncOutcome.fromJson(jsonDecode(result));
  }

  Future<void> logout() => garminLogout();
}
```

### 2.3 `GarminSnapshotWriter` — Snapshot → Drift

Rust returns a normalized `HealthSnapshot` JSON. Dart parses it and upserts into `health_metrics` via the existing `HealthMetricRepository`:

```dart
class GarminSnapshotWriter {
  GarminSnapshotWriter({
    required HealthMetricRepository repository,
    required MutationStamper stamper,
  });

  /// Write a Rust HealthSnapshot into the local Drift database.
  /// Reuses the same idempotent upsert logic as HealthSyncService.
  Future<GarminWriteResult> writeSnapshot(HealthSnapshot snapshot) async {
    var upserted = 0;
    var unchanged = 0;

    for (final step in snapshot.steps) {
      final metric = HealthMetric(
        id: step.id,  // "garmin:steps:2026-06-07"
        capturedAt: step.date,
        kind: HealthMetricKind.stepsDaily,
        value: step.value,
        unit: step.unit,
        sourceDevice: step.sourceDevice ?? 'garmin',
        sync: _placeholderSync,
      );
      final result = await _upsertIfChanged(metric);
      result == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    // ... same pattern for sleep, rhr, hrv, activities, body_battery, stress, etc.

    return GarminWriteResult(upserted: upserted, unchanged: unchanged);
  }
}
```

This writer **reuses the exact same `_upsertIfChanged` pattern** from `HealthSyncService`. No changes to the repository, no changes to the sync outbox.

### 2.4 `GarminSyncController` — Riverpod State

```dart
@riverpod
class GarminSyncController extends _$GarminSyncController {
  @override
  GarminSyncState build() => const GarminSyncState.initial();

  Future<void> connect(String email, String password) async { ... }
  Future<void> submitMfa(String code) async { ... }
  Future<void> syncNow({Duration window = const Duration(days: 30)}) async { ... }
  Future<void> disconnect() async { ... }
}

@freezed
class GarminSyncState with _$GarminSyncState {
  const factory GarminSyncState.initial() = _Initial;
  const factory GarminSyncState.pendingMfa() = _PendingMfa;
  const factory GarminSyncState.connected({
    required DateTime? lastSyncAt,
    required int totalMetrics,
  }) = _Connected;
  const factory GarminSyncState.syncing({
    required DateTime startedAt,
  }) = _Syncing;
  const factory GarminSyncState.error(String message) = _Error;
}
```

### 2.5 Modified Files

| File | Change |
|---|---|
| `features/health/data/providers.dart` | Add `garminSyncControllerProvider`, `garminBridgeProvider`, `garminSnapshotWriterProvider` |
| `features/health/ui/health_today_page.dart` | Add `GarminSyncStatusCard` when Garmin is configured |
| `features/health/data/health_sync_service.dart` | Add optional `GarminSnapshotWriter` parameter; when present, also call Garmin sync before platform sync |
| `pubspec.yaml` | Add `flutter_secure_storage` (if not present) |

### 2.6 Multi-Source Strategy

When both HealthKit and Garmin are active:

- **Steps / HR / HRV / Sleep**: Garmin takes priority (wrist-based, more granular)
- **Weight / Body Fat**: Manual entry (both platforms allow, dedup by date)
- **Workouts**: Merge by timestamp, dedup by `garmin:activity:<id>` vs `hk:workout:<uuid>`
- **Body Battery / Stress**: Garmin-only (no HealthKit equivalent)

Implementation: `HealthSyncService.syncRange()` runs both adapters and applies per-kind priority. The `sourceDevice` field on each `HealthMetric` row records provenance.

---

## 3. UI Layer

### 3.1 `GarminAccountBindSheet`

Modal sheet (`showAppFormSheet`) with:
- Email + password fields
- MFA code field (shown after `AuthResult.MfaRequired`)
- Loading states: connecting, submitting MFA, saving token
- Error states: wrong credentials, MFA timeout, network error
- Success: stores token → triggers first sync

### 3.2 `GarminSyncStatusCard`

Added to `HealthTodayPage`:
- "Garmin ✓" / "Garmin 未连接"
- Last sync: `2026-06-08 22:30`
- Sync range: 最近 30 天
- "立即同步" button
- Error banner if last sync failed

### 3.3 `HealthSourceSelector`

In Settings → Health:
- Toggle Garmin on/off
- When both HealthKit and Garmin active: "Garmin 优先" / "HealthKit 优先" per metric group
- "断开 Garmin" button (clears token)

---

## 4. Phase 1 — Python Probe

Before writing Rust, validate the Garmin API:

### 4.1 Setup

```bash
cd scripts/
uv venv garmin-probe
source garmin-probe/bin/activate
uv pip install garminconnect
```

### 4.2 Probe Script: `scripts/garmin_probe.py`

Authenticate via `python-garminconnect`, dump 7 days of data:

| Endpoint | Target |
|---|---|
| `get_steps_data(date)` | `DailyMetric` |
| `get_sleep_data(date)` | `SleepSession` |
| `get_rhr_day(date)` | `DailyMetric` |
| `get_hrv_data(date)` | `DailyMetric` |
| `get_body_battery(date)` | `BodyBatteryDay` |
| `get_stress_data(date)` | `DailyMetric` |
| `get_activities(start, limit)` | `ActivityRecord` |
| `get_training_status()` | VO2 max |
| `get_weigh_in_data(date)` | `PointMetric` |
| `get_daily_summary(date)` | composite |

### 4.3 Deliverables

- [x] `scripts/garmin_probe.py` — CN region support, correct method names
- [x] `garmin_sample_output.json` — 7-day sample (2026-06-02..08)
- [x] Confirmed field shapes → Rust `mapper.rs` golden tests (16 tests)
- [x] Rate limit notes → `rate_limiter.rs` (500ms interval, 30s base backoff)
- [x] Auth flow notes → `auth.rs` state machine

### 4.4 Confirmed Data Shapes (2026-06-08 CN Probe)

| Endpoint | Method | Response Shape | Mapper |
|---|---|---|---|
| Steps | `get_steps_data(d)` | `[{startGMT, endGMT, steps: N}, ...]` (15-min intervals) | `map_steps` — sums intervals |
| Sleep | `get_sleep_data(d)` | `{dailySleepDTO: {id, sleepStartTimestampGMT (epoch ms), sleepTimeSeconds, deepSleepSeconds, lightSleepSeconds, remSleepSeconds, awakeSleepSeconds, avgHeartRate}}` | `map_sleep` + `map_heart_rate_from_sleep` |
| RHR | `get_rhr_day(d)` | `{allMetrics: {metricsMap: {WELLNESS_RESTING_HEART_RATE: [{value, calendarDate}]}}}` | `map_rhr` |
| HRV | `get_hrv_data(d)` | `{hrvSummary: {lastNightAvg, weeklyAvg, ...}}` | `map_hrv` |
| Body Battery | `get_body_battery(d)` | `[{date, charged, drained, bodyBatteryValuesArray: [[ts, val], ...]}]` | `map_body_battery` |
| Stress | `get_stress_data(d)` | `{avgStressLevel, maxStressLevel, stressValuesArray: [...]}` | `map_stress` |
| Activities | `get_activities(0, N)` | `[{activityId, activityType: {typeKey}, startTimeGMT, duration (float sec), distance (m), calories}]` | `map_activity` |
| User Summary | `get_user_summary(d)` | ❌ Method doesn't exist in current python-garminconnect | N/A |
| Weight | `get_daily_weigh_ins(d)` | ❌ Empty/error for this user | N/A |
| Training Status | `get_training_status()` | ❌ Error for this user | N/A |

**Success rate**: 6/8 endpoints working (steps, sleep, RHR, HRV, body battery, stress, activities).

**Key findings**:
- Heart rate: extracted from sleep DTO's `avgHeartRate` (not a separate endpoint)
- Sleep start time: epoch milliseconds, not ISO string
- Steps: 15-minute intervals, must sum for daily total
- RHR: nested in `allMetrics.metricsMap.WELLNESS_RESTING_HEART_RATE`
- Body Battery: array with `charged`/`drained` + per-slot `bodyBatteryValuesArray`

---

## 5. Testing Strategy

### 5.1 Rust Tests (34 passing)

| Module | Tests | Coverage |
|---|---|---|
| `mapper.rs` (inline `#[cfg(test)]`) | 16 | Steps summing, sleep DTO parsing, RHR metricsMap, HRV summary, body battery array, stress, activity, VO2 max, build_snapshot, edge cases (zero/empty) |
| `auth.rs` (inline `#[cfg(test)]`) | 9 | can_make_requests per state, needs_refresh expiry, serialization roundtrip |
| `rate_limiter.rs` (inline `#[cfg(test)]`) | 7 | 429 exponential backoff, max cap, success reset, run/execute, error propagation |
| `embedder.rs` (existing) | 3 | Constants, empty dir, missing dir |

Golden test data uses real Garmin CN JSON shapes from `garmin_sample_output.json` (2026-06-08).

### 5.2 Dart Tests

| Test file | Coverage |
|---|---|
| `garmin_bridge_test.dart` | FRB call serialization, error mapping (mock Rust calls) |
| `garmin_snapshot_writer_test.dart` | Snapshot → Drift upsert, idempotency, unchanged detection |
| `garmin_sync_controller_test.dart` | State transitions, error handling |
| `garmin_account_bind_sheet_test.dart` | Widget test: form validation, MFA flow UI |
| `garmin_sync_status_card_test.dart` | Widget test: connected/disconnected/syncing states |

### 5.3 Integration Test

Full flow: Dart UI → FRB → Rust client (mock HTTP) → snapshot → Dart writer → Drift → memory indexer

### 5.4 CI Gates

The active architecture checks pass unchanged:
- `lint-no-feature-in-shared.sh` — no Health feature imports from shared layers
- `lint-cross-feature-imports.sh` — no cross-feature leaks
- `domain_prefix_test.dart` — `health:` prefix maintained
- `device_degradation_test.dart` — no descriptor drift until Phase 3

---

## 6. Delivered Baseline

| Phase | Status | Deliverable |
|---|---|---|
| **Phase 1**: Python probe | ✅ Done | `garmin_probe.py`, 7-day CN sample, confirmed data shapes |
| **Phase 2a**: Rust health types + provider | ✅ Done | `provider.rs` (HealthProvider trait + 7 types), `mapper.rs` (16 golden tests) |
| **Phase 2b**: Rust Garmin client + auth | ✅ Done | `client.rs`, `auth.rs` (9 tests), `rate_limiter.rs` (7 tests), `endpoints.rs` |
| **Phase 2c**: Rust sync engine + FRB | ✅ Done | `sync_engine.rs`, `health.rs` FRB surface (primitive types only) |
| **Phase 2d**: Dart shell | ✅ Done | `garmin_bridge.dart`, `garmin_sync_controller.dart`, `garmin_snapshot_writer.dart` |
| **Phase 2e**: UI | ✅ Done | `garmin_account_bind_sheet.dart`, `garmin_sync_status_card.dart` |
| **Phase 2f**: FRB codegen | ✅ Done | Generated Dart/Rust FRB bindings for the Garmin surface |

**Codegen guard**: `apps/mobile/test/native/frb_garmin_codegen_contract_test.dart`
asserts that `lib/src/rust/api/health.dart`, `frb_generated.dart`,
`frb_generated.{io,web}.dart`, and `native/lifeos_native/src/frb_generated.rs`
continue to expose the Garmin auth, sync, cancel, cursor, logout, export, and
`GarminSyncProgress` bridge symbols. When the Rust API surface changes, rerun
`flutter_rust_bridge_codegen generate` and keep this contract green.

---

## 7. Future Extensions (Phase 3+)

| Extension | Trigger |
|---|---|
| New AI tools (`get_body_battery_trend`, `get_training_load`) | Phase 2 stable + user demand |
| Background sync (workmanager + Rust sync engine) | Phase 2 stable |
| Morning Briefing with Garmin analytics | Phase 2 stable |
| Official Garmin Connect API adapter | Multi-user / commercial |
| `HealthProvider` impl for Huawei Health / COROS | New device |
| CLI health sync (`lifeos_native` as standalone binary) | Desktop / headless need |
| Rust read model builder for AI context | Agent integration |

---

## 8. Risk Register

| Risk | Mitigation |
|---|---|
| Garmin SSO changes break auth | Auth state machine isolated in `auth.rs`; monitor python-garminconnect issues; snapshot tests catch regressions |
| 429 rate limits during initial sync | Rate limiter with exponential backoff; paginate by day; 30-day sync may take 15–30 min |
| FRB async bridge complexity | FRB 2.13 beta supports async natively; generated contract tests guard the exposed symbols |
| Rust dependency size (reqwest + tokio) | `opt-level = "z"` + LTO + strip already configured; reqwest with rustls avoids OpenSSL |
| Token persistence across app restarts | `TokenStore` trait with Dart `flutter_secure_storage` impl; test round-trip |
| Garmin data quality worse than HealthKit | Phase 1 probe validates; merge strategy prefers higher-quality source |

---

## 9. File Inventory

### New Rust Files

| File | Purpose |
|---|---|
| `lifeos_native/src/api/health/mod.rs` | FRB public surface |
| `lifeos_native/src/frb_generated.rs` | Generated Rust FRB dispatch for Garmin bridge |
| `lifeos_native/src/api/health/provider.rs` | `HealthProvider` trait + snapshot types |
| `lifeos_native/src/api/health/sync_engine.rs` | Cursor-based incremental sync |
| `lifeos_native/src/api/health/garmin/mod.rs` | `GarminProvider` impl |
| `lifeos_native/src/api/health/garmin/client.rs` | HTTP client, SSO, cookies |
| `lifeos_native/src/api/health/garmin/auth.rs` | Auth state machine |
| `lifeos_native/src/api/health/garmin/token_store.rs` | `TokenStore` trait |
| `lifeos_native/src/api/health/garmin/rate_limiter.rs` | 429 backoff + concurrency |
| `lifeos_native/src/api/health/garmin/endpoints.rs` | Garmin API wrappers |
| `lifeos_native/src/api/health/garmin/mapper.rs` | JSON → `HealthSnapshot` |

### New Dart Files

| File | Purpose |
|---|---|
| `features/health/data/garmin/garmin_bridge.dart` | FRB wrapper |
| `features/health/data/garmin/garmin_token_store_dart.dart` | Secure storage impl |
| `features/health/data/garmin/garmin_sync_controller.dart` | Riverpod state |
| `features/health/data/garmin/garmin_snapshot_writer.dart` | Snapshot → Drift |
| `features/health/ui/garmin_account_bind_sheet.dart` | Login/MFA UI |
| `features/health/ui/garmin_sync_status_card.dart` | Sync status |
| `features/health/ui/health_source_selector.dart` | Source picker |
| `lib/src/rust/api/health.dart` | Generated Dart FRB facade for Garmin calls |
| `lib/src/rust/frb_generated.dart` | Generated Dart FRB API dispatch |
| `lib/src/rust/frb_generated.io.dart` | Generated Dart native codec bindings |
| `lib/src/rust/frb_generated.web.dart` | Generated Dart web codec bindings |
| `scripts/garmin_probe.py` | Phase 1 probe |

### Modified Files

| File | Change |
|---|---|
| `lifeos_native/Cargo.toml` | Add reqwest, serde, tokio, chrono, uuid |
| `lifeos_native/src/api/mod.rs` | Add `pub mod health` |
| `features/health/data/providers.dart` | Add Garmin providers |
| `features/health/ui/health_today_page.dart` | Add sync status card |
| `pubspec.yaml` | Add `flutter_secure_storage` |

### Unchanged

`HealthSyncService` (extended, not rewritten), `HealthMetricRepository`, `health_metrics` Drift table, AI tools, memory indexer, Morning Briefing agent, sync v3, DomainPack.
