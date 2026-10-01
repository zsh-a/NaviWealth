# HealthOS Domain SSOT

HealthOS is the LifeOS health domain. It is user opt-in, native-only, local-first, and focused on daily recovery signals rather than medical diagnosis.

## Document Contract

Owns HealthOS behavior, data-source precedence, recovery semantics, tools, and
Agents. It does not own native runtime internals or Sync wire behavior.
`health_pack.dart`, Health repositories, and focused Health tests are
authoritative for the current implementation inventory.

## Scope

Included:

- Sleep sessions and duration.
- HRV, resting heart rate, and recovery trend.
- Steps, active energy, workouts, workout duration, distance.
- VO2 max pipeline where platform support exists.
- Weight and body fat as explicit low-frequency manual or AI-confirmed entries.
- Optional daily energy, sleep quality, and subjective stress check-ins, with
  life-event tags and notes. Recording does not require a wearable or AI.
- Personal source preferences and an optional user-set sleep-duration goal.
- Read-only Garmin Connect ingestion through the narrow native runtime.
- Recovery Alert and Weekly Summary domain analyzers.

Excluded:

- Medical diagnosis or medication management.
- Health data write-back to HealthKit or Health Connect.
- Realtime raw heart-rate streaming.
- Web support.
- Social, leaderboard, achievement, or coaching-network features.
- Third-party device SDKs unless a separate trigger justifies them.

## Data Sources

| Platform | Source | Mode |
|---|---|---|
| iOS | HealthKit via `package:health` | Read-only |
| Android | Health Connect via `package:health` | Read-only |
| iOS / Android | Garmin Connect through `lifeos_native` + FRB | Read-only import |
| Web/Desktop | Stub adapter | Not supported |

Key files:

- `features/health/data/health_platform_adapter.dart`
- `features/health/data/health_platform_adapter_io.dart`
- `features/health/data/health_platform_adapter_stub.dart`
- `features/health/data/health_sync_service.dart`
- `features/health/data/health_metric_repository.dart`
- `features/health/data/garmin/garmin_bridge.dart`
- `features/health/data/garmin/garmin_sync_controller.dart`
- `features/health/data/garmin/garmin_snapshot_writer.dart`

`HealthSyncService.syncRange()` fetches platform data, converts it to `HealthMetric`, and upserts only changed rows. Unchanged rows do not create outbox work.

The first-run Today activation card is optional: users can continue without
connecting a source. It offers system Health, Garmin Connect, and manual body
measurement as peer entry paths. Connecting a source performs the first sync
in one action.

System Health is optional, including Android Health Connect. Unavailable or
unauthorized platform sources skip automatic imports without writing a failed
sync status. Connection prerequisites (including legacy persisted statuses)
remain neutral source-row states, not refresh-failure banners. Actual import
failures remain visible; Garmin and manual records work independently.

Manual weight and body-fat records count as existing Health data. Today shows
the latest measurement with its capture time and metric-specific Trends entry;
body fat is displayed as a percentage, not the stored fraction. Missing recovery
inputs degrade the recovery summary rather than returning the user to activation.

Pull-to-refresh is a real source refresh, not a local-query reload:

- Every connected source is refreshed once through
  `health_refresh_coordinator.dart`.
- Concurrent refresh gestures share one in-flight import.
- Partial failures preserve successful source results and remain visible on
  Today.
- Daily Navigator consumes the refreshed Health `LifeSignal` only after the
  app-level freshness and material-change gates.

Today and Trends expose the same pull-to-refresh affordance. Trends refreshes
all connected sources through the shared coordinator, then reloads the active
chart group; a partial source failure remains visible inline without adding a
permanent status panel.

Today source cards show connection, freshness, and failure state only. Manual
connect, sync, retry, cancel, and disconnect controls live in Health Settings;
this avoids a second action cluster beside pull-to-refresh while preserving the
same operational state in both places.

The last platform-sync attempt, last successful refresh, and its
fetched/upserted/unchanged counts are persisted locally by
`health_sync_status.dart`. Garmin persists its last attempt, last successful
refresh, import count, and latest failure code per NaviWealth owner. Today and
Health Settings restore this operational state after restart; it does not
sync. Source cards derive the latest imported data time from local Health
rows, so a successful refresh that only returns old data can still be marked
stale.

Garmin also refreshes silently while the app is in the foreground: at launch,
on resume, and when returning to a Health tab if the last check is older than
30 minutes. The newest three local-calendar days are always rechecked before
bounded historical reconciliation. Existing rows never imply that a day's
sleep, steps or other endpoints are complete. Temporary failures back off;
rate-limit cooldowns also apply to manual refresh. Pausing the app stops this
foreground driver; no background freshness guarantee is implied.

Garmin source cards retain their previous content during automatic refresh,
distinguish "last checked" from data capture time, and retain partial failures.
Settings owns detailed actions. Binding or completing MFA through the shared
sheet initiates the first import without a second Sync tap.

### Garmin session lifecycle

- Garmin access tokens are refreshed by the native runtime shortly before
  expiry. Rotated refresh tokens are exported back to Dart and persisted in
  platform secure storage.
- A user may explicitly enable secure password saving. The email, password,
  selected Garmin region, and session are encrypted by the device
  Keychain/Keystore and partitioned by the active NaviWealth owner.
- Saved passwords are device-local secrets: they never enter Drift, sync,
  memory, analytics, or application logs.
- If token refresh fails, HealthOS attempts one automatic login with the saved
  credentials. An MFA challenge pauses recovery and asks the user for the
  current verification code.
- Disconnect clears Garmin sessions for all regions, the saved password, and
  local Garmin operational sync status. Previously imported health metrics
  remain.

## Persistence

Tables:

- `core/persistence/health_tables.dart`
- Drift table: `health_metrics`
- Drift table: `health_check_ins` (additive schema v97)
- Entity: `features/health/domain/health_metric.dart`
- Kind enum: `features/health/domain/health_metric_kind.dart`

The table is syncable and carries the shared `SyncableTable` fields:

- `ownerUserId`
- `updatedAt`
- `updatedByDevice`
- `hlc`
- `deletedAt`

Primary row shape:

```text
id
captured_at
kind
value
unit
payload_json
source_device
source_id
sync metadata
```

Typical kinds:

- `sleep_session`
- `hrv_daily`
- `rhr_daily`
- `steps_daily`
- `active_energy_daily`
- `workout_session`
- `vo2_max_daily`
- `weight`
- `body_fat`

Daily check-ins are owner-scoped and use a UTC midnight value as a calendar
date container. The row carries optional 1–5 `energy`, `sleep_quality`, and
`stress`, a JSON list of event tags, an optional note (up to 1,000 characters),
and the shared sync metadata. Saving requires at least one value, tag, or note;
future dates are rejected. Edits, deletion tombstones, and later restoration
reuse the same date's row identity. Owner-migration duplicates are resolved by
HLC before tombstone filtering. Writes and outbox enqueue share a transaction.
Unknown event tags remain intact when an older client edits a record.

`health:health_check_ins` is registered in the generic sync table registry and
participates in Health reset and encrypted backups. Older clients skip the
unknown row family; upgrading changes the registry compatibility signature
and replays the remote rows. Restoring an older archive that has no check-in
table preserves existing check-ins. The v97 migration adds the table/indexes
without rewriting existing metrics or sync state.

Source selection and sleep goals are device-local, owner-scoped preferences
in `health_preferences.dart`; they are not synced or included in backups.

## Sources and Recovery Comparability

Persisted `source_id` takes precedence over legacy adapter ID/device-name
inference. A per-metric preference wins overlapping daily/session records;
dates missing from that source fall back to the existing priority order
(Garmin, HealthKit, Health Connect, manual). Selection preserves raw rows.

HRV trends and all recovery components use the newest active measurement
family: source, available device attribution, unit, measurement method, and
import origin must match. HealthKit HRV uses SDNN; Health Connect uses RMSSD;
Garmin remains provider-defined. Platform daily averages retain method/origin
metadata and aggregate separately by import origin/device. A source or method
switch starts a new baseline instead of mixing incompatible histories.
Legacy aggregates lack origin metadata and remain a separate family until
history is reimported or enough new observations accumulate; this is not a
destructive migration of old rows.

`RecoveryScorer` compares the most recent seven calendar dates (including
today) with the preceding 21 dates. Each component needs five distinct
baseline observation days and a recent observation before contributing.
Sleep sums separate sessions/naps by local wake date and compares recorded-day
averages; an explicitly configured sleep goal may replace its baseline.
Unfinished sleep and future dates do not contribute. Without an eligible
component, the score remains absent and evidence shows baseline learning.

Eligible components have equal weight. Coverage is eligible components / six;
freshness is the age of the oldest contributing component's latest capture,
so one fresh input cannot conceal a stale one. Confidence also depends on
each component's recent observed-day count. Evidence includes component
status, source/device/method, reference basis, observed-day counts, freshness,
and weight. This is an explainable lifestyle heuristic, not a validated
physiological or clinical score.

## Shell Registration

HealthOS is registered through `kHealthPack` in `app/domain_packs.dart`.

Contributions:

- Scope: `DomainScope.health`.
- Shell: `features/health/composition/health_domain_shell.dart`.
- Routes: `features/health/composition/health_routes.dart`.
- Tabs: Today, Trends. Removed legacy `/health/plan` deep links now follow the
  normal unknown-route fallback;
  recovery-plan content lives in the Today hero.
- Tools: `features/health/health_ai_tools.dart`.
- Agents: Recovery Alert, Weekly Summary.
- Command palette: `features/health/composition/health_command_palette.dart`.

HealthOS is active only when the user enables it in Settings.

## UI

| Tab | Purpose |
|---|---|
| Today | Daily check-in, compact recovery summary, latest metric readings with seven-day mini charts, last-seven-day digest, and collapsed source status |
| Trends | Recovery / Activity / Body overview; one focused metric chart with date, unit, coverage, source choice, daily context, and check-in history |

Presentation contract:

- Today, Trends, and the seven-day digest use `data/health_series.dart` for
  source-deduplicated calendar aggregation. Windows contain exactly 7, 30, or
  90 dates including today. Range queries are time-bounded, not truncated by
  an assumed number of rows per day.
- Daily source rows retain their encoded calendar date. Workouts use local
  start dates; sleep uses local wake dates (start plus recorded duration),
  summing separate sessions/naps before computing a recorded-day average.
  Date-only manual measurements do not shift when converted to local time.
- Missing days remain absent, not zero, and split line segments. Daily totals
  and sleep use bars; measurements use lines/points; training status uses
  labels rather than a numeric curve. A single recorded day shows its reading
  and records without an oversized empty chart.
- Comparisons use recorded-day averages in equal calendar windows, requiring
  at least two observations in each. Cumulative activity comparisons omit
  today and the matching last date of the preceding window. Coverage remains
  visible; percentage changes are neutral, not financial gain/loss signals.
- The URL is the sole navigation state for group, metric, and time window.
  Opening a metric shows its detail, rather than reordering overview cards.
- Recovery retains the shared scorer used by the AI tool. Its evidence,
  guidance, and disclaimer live behind one disclosure; the old unlabeled HRV
  sparkline is removed. Users with manual measurements only see those readings
  first and a quiet recovery-baseline hint.
- Source warnings reflect current persisted/controller state, not a cached
  result of the last pull-to-refresh. Source management is in Health settings;
  platform connection/sync uses the shared refresh coordinator.
- Manual body measurements can be corrected from their source record. Editing
  preserves kind, date, and stable row identity; value/note are replaced and
  synced normally. Capture keeps separate weight/body-fat drafts and an optional
  note. Stored body fat remains a fraction; UI input/output is percentage.
  Capture and correction use the shared commit-first form protocol: a pending
  write locks fields and dismissal, failure keeps the same draft and a safe
  inline error, and success closes the sheet and refreshes Today/Trends.
- Daily check-ins use the same guarded, commit-first sheet. Scales are optional;
  tapping the selected value clears it. Event tags include caffeine, late meals,
  alcohol, illness, travel, hard workouts, meditation, and late screen time.
  History supports past-day recording, editing, and confirmed deletion; the
  existing entry is loaded before editing a date. Live subscriptions reflect
  local and synced changes and stop exposing records when Health is disabled
  or the owner changes.
- Calendar windows advance with the shell's shared minute clock after
  device-local midnight and on foreground resume,
  including retained tabs. This refreshes local reads without starting a new
  source import or background task.
- Focused metric charts mark dates that also have check-ins. Selecting a date
  shows that day's subjective context without fabricating a missing metric.
  Check-in-only dates stay in the window's history. These are contextual
  observations; the UI does not claim event causation.
- Health Settings allows a sleep goal or automatic personal baseline. Metric
  details allow a source preference; Today, recovery, and related AI reads
  honor it while keeping underlying source records.

These additions retain the existing Today/Trends navigation and native
foreground/background scheduling.

Key files:

- `features/health/ui/health_today_page.dart`
- `features/health/ui/health_trend_page.dart`
- `features/health/ui/health_metric_presentation.dart`
- `features/health/ui/health_metric_detail.dart`
- `features/health/data/health_series.dart`
- `features/health/data/health_check_in_repository.dart`
- `features/health/ui/health_check_in_sheet.dart`
- `features/health/ui/health_domain_settings_page.dart`

## AI Tools

Tool barrel: `features/health/health_ai_tools.dart`.

| Tool | Access | Purpose |
|---|---|---|
| `get_recent_sleep_summary` | Read | Sleep sessions and recorded-day average duration, including naps |
| `get_hrv_trend` | Read | HRV points, window summary, delta |
| `get_activity_summary` | Read | Steps, active calories, workout totals |
| `get_recovery_signal` | Read | Score, verdict, confidence, coverage, freshness, and explainable components from sleep, HRV, RHR, VO2 max, Body Battery, and stress where available |
| `record_body_measurement` | Confirmed local write | Weight or body fat only |

Rules:

- AI must not write sleep, HRV, steps, workouts, or platform-collected health rows.
- Weight and body fat writes require a user-explicit record/save intent plus a numeric value.
- Health interpretation must cite tool-returned windows and values.
- Recovery score is a lifestyle signal, not a diagnosis. Today and the AI
  tool use the same scorer and expose the same confidence, input coverage,
  freshness, and component evidence. Component evidence includes recent value,
  personal baseline or explicit goal, delta, and observed-day counts where
  available. Recovery Alert compares a single HRV measurement family; legacy
  repository Weekly Summary helpers use the same preferences and scorer.
- Check-in notes/tags are not automatically exposed through AI tools or the
  memory indexer in this version.

## Memory Integration

Indexer:

- `features/health/data/health_metric_memory_indexer.dart`

Source:

- `health:health_metrics`

Behavior:

- Each supported health row emits a typed `EventRecord` with Health domain,
  occurred/observed time, source row identity/fingerprint, facts, entities,
  confidence, and evidence anchor.
- Notable sleep sessions can emit an episodic `MemoryRecord` in `scope='health'`.
- Health opt-in is enforced inside the indexer provider.
- Memory Runtime remains domain-neutral.

Event examples:

- `sleep_session_ended`
- `hrv_recorded`
- `rhr_recorded`
- `steps_recorded`
- `active_energy_recorded`
- `workout_completed`
- `vo2_max_recorded`
- `weight_recorded`
- `body_fat_recorded`

## Agents

Weekly Summary is presented as Weekly Health Summary and runs through the
shared scheduled LLM executor. It reads available local Health data via tools,
regardless of whether the source is Health Connect, HealthKit or Garmin.
The model generates the analysis; absent models or failed runs do not fall back
to template reports. It retains `weekly_summary` as its stable identity and
defaults to Sunday 20:00 device-local time with an editable weekly plan.

| Agent | Purpose |
|---|---|
| Recovery Alert | Surfaces material recovery-risk signals |
| Weekly Summary | Reviews the recent Health window |

Both produce shared local findings and Agent Artifacts and are registered
through `kHealthPack`. They do not write Agent summaries to durable Memory or
post notifications directly. Health recovery `LifeSignal`s feed the app-owned
Daily Navigator; the global attention layer decides whether the cross-domain
judgment stays silent, appears on Life, or interrupts. Disabling HealthOS
removes Health Agents, signals, tools, and context from active composition.

## Platform Caveats

- iOS HealthKit capability must be enabled in Xcode signing settings.
- iOS background scheduling is opportunistic and not guaranteed to run exactly on time.
- HealthKit sleep can arrive as segments; the adapter merges close segments
  into sessions. Canonical multi-source selection deduplicates only sessions
  with at least 80% overlap, so a separate nap or split sleep on the same UTC
  day is preserved.
- VO2 max depends on `package:health` platform support. The pipeline can store it when the adapter returns it.

## Tests To Prefer

When touching HealthOS, add or run targeted tests for:

- `HealthSyncService` mapping and idempotency.
- Sleep segment merge behavior.
- `HealthMetricRepository` queries.
- Check-in owner/date identity, live opt-in gating, transactional outbox,
  tombstones, v96→v97 upgrade/rollback, sync replay, and backup compatibility.
- Source/method/device isolation, per-component baseline days, stale inputs,
  naps, explicit goals, and chart-date context.
- Health AI tool outputs.
- `HealthMetricMemoryIndexer`.
- Recovery Alert and Weekly Summary agents.
- Typed event/evidence identity and Health source-route resolution.
- Daily Navigator stale/inactive Health gating through app composition.
- Health route shell and opt-in behavior.
