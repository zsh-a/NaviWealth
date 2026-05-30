# HealthOS Domain SSOT

HealthOS is the LifeOS health domain. It is user opt-in, native-only, local-first, and focused on daily recovery signals rather than medical diagnosis.

## Scope

Included:

- Sleep sessions and duration.
- HRV, resting heart rate, and recovery trend.
- Steps, active energy, workouts, workout duration, distance.
- VO2 max pipeline where platform support exists.
- Weight and body fat as explicit low-frequency manual or AI-confirmed entries.
- Morning Briefing as the first HealthOS agent.

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
| Web/Desktop | Stub adapter | Not supported |

Key files:

- `features/health/data/health_platform_adapter.dart`
- `features/health/data/health_platform_adapter_io.dart`
- `features/health/data/health_platform_adapter_stub.dart`
- `features/health/data/health_sync_service.dart`
- `features/health/data/health_metric_repository.dart`

`HealthSyncService.syncRange()` fetches platform data, converts it to `HealthMetric`, and upserts only changed rows. Unchanged rows do not create outbox work.

## Persistence

Table:

- `core/persistence/health_tables.dart`
- Drift table: `health_metrics`
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

## Shell Registration

HealthOS is registered through `kHealthPack` in `app/domain_packs.dart`.

Contributions:

- Scope: `DomainScope.health`.
- Shell: `features/health/composition/health_domain_shell.dart`.
- Routes: `features/health/composition/health_routes.dart`.
- Tabs: Today, Trend, Plan.
- Tools: `features/health_ai_tools.dart`.
- Agent: `MorningBriefingAgent`.
- Command palette: `features/health/composition/health_command_palette.dart`.

HealthOS is active only when the user enables it in Settings.

## UI

| Tab | Purpose |
|---|---|
| Today | Sleep, HRV, recovery, workout cards, latest Morning Briefing, manual run |
| Trend | HRV, sleep hours, workout minutes line charts |
| Plan | Recovery score, inputs, simple training load suggestion, medical disclaimer |

Key files:

- `features/health/ui/health_today_page.dart`
- `features/health/ui/health_trend_page.dart`
- `features/health/ui/health_plan_page.dart`
- `features/settings/ui/domains_settings_page.dart`

## AI Tools

Tool barrel: `features/health_ai_tools.dart`.

| Tool | Access | Purpose |
|---|---|---|
| `get_recent_sleep_summary` | Read | Sleep sessions and average duration |
| `get_hrv_trend` | Read | HRV points, window summary, delta |
| `get_activity_summary` | Read | Steps, active calories, workout totals |
| `get_recovery_signal` | Read | Score and verdict from sleep, HRV, RHR, VO2 max where available |
| `record_body_measurement` | Confirmed local write | Weight or body fat only |

Rules:

- AI must not write sleep, HRV, steps, workouts, or platform-collected health rows.
- Weight and body fat writes require a user-explicit record/save intent plus a numeric value.
- Health interpretation must cite tool-returned windows and values.
- Recovery score is a lifestyle signal, not a diagnosis.

## Memory Integration

Indexer:

- `features/health/data/health_metric_memory_indexer.dart`

Source:

- `health:health_metrics`

Behavior:

- Each supported health row emits an `EventRecord`.
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

## Morning Briefing

Agent:

- `features/health/agents/morning_briefing_agent.dart`

Supporting files:

- `features/health/agents/briefing_synthesizer.dart`
- `features/health/agents/providers.dart`
- `features/health/data/morning_briefing_preferences.dart`
- `core/background/`
- `core/notifications/`

Behavior:

- Runs around the user's configured local hour.
- Reads recent Memory Runtime events.
- Uses LLM synthesis when a usable device LLM profile exists.
- Falls back to deterministic programmatic synthesis on LLM failure or absence.
- Writes a briefing memory and a domain notification.
- Background callbacks only set a due flag; the full run happens after foreground startup.

## Platform Caveats

- iOS HealthKit capability must be enabled in Xcode signing settings.
- iOS background scheduling is opportunistic and not guaranteed to run exactly on time.
- HealthKit sleep can arrive as segments; the adapter merges close segments into sessions.
- VO2 max depends on `package:health` platform support. The pipeline can store it when the adapter returns it.

## Tests To Prefer

When touching HealthOS, add or run targeted tests for:

- `HealthSyncService` mapping and idempotency.
- Sleep segment merge behavior.
- `HealthMetricRepository` queries.
- Health AI tool outputs.
- `HealthMetricMemoryIndexer`.
- Morning Briefing agent and synthesizer.
- Health route shell and opt-in behavior.
