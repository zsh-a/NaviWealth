# Garmin Connect Integration Reference

Status: implemented HealthOS provider.

Last reviewed: 2026-08-01.

This document records the current Garmin integration and its maintenance
boundaries. Delivery phases, dependency snapshots, proposed APIs, and completed
task checklists have been removed; the code and tests are authoritative for
exact signatures.

## Scope And Boundaries

Garmin Connect is an optional, read-only HealthOS source on native platforms.
It imports normalized health metrics into the same `health_metrics` repository
used by HealthKit, Health Connect, and manual measurements.

- Garmin network protocol, authentication state, rate limiting, endpoint
  mapping, and incremental cursors live in the Rust native runtime.
- Flutter owns connection/MFA UI, per-user secure credential persistence,
  refresh orchestration, status display, and Drift writes.
- Imported metrics use the existing HealthOS sync path and the `health:` wire
  prefix; Garmin sessions and operational status remain device-local.
- Web uses the unsupported Health adapter and never loads this runtime.
- Garmin data is evidence for HealthOS features, not medical advice.

Garmin Connect endpoints are not a stable public API. Endpoint or auth changes
must fail visibly without deleting the last successful import or exposing
credentials in logs.

## Runtime Flow

```text
Health Today / Health Settings / background due flag
  -> GarminSyncController
  -> GarminBridge
  -> flutter_rust_bridge primitive API
  -> Rust GarminClient + HealthSyncEngine
  -> normalized snapshot/progress
  -> GarminSnapshotWriter
  -> HealthMetricRepository
  -> health_metrics + normal Sync v3 outbox
```

Pull-to-refresh uses `health_refresh_coordinator.dart`, which coalesces
concurrent refreshes and reports partial source failures. Background callbacks
only record due work; `pendingGarminSyncRunProvider` performs the real sync
after the foreground provider graph is available.

## Code Map

Rust implementation:

```text
apps/mobile/native/lifeos_native/src/health/
  mod.rs                 FRB-facing primitive API and process state
  provider.rs            normalized health value types
  sync_engine.rs         incremental cursor and date-range orchestration
  garmin/
    auth.rs              authentication and MFA state
    client.rs            Garmin HTTP/session client
    endpoints.rs         endpoint access
    mapper.rs            payload normalization
    rate_limiter.rs      throttling and retry policy
    token_store.rs       in-memory session abstraction
```

Flutter implementation:

```text
apps/mobile/lib/features/health/
  data/garmin/
    garmin_bridge.dart                 typed wrapper over generated FRB calls
    garmin_sync_controller*.dart       auth, session, range, and sync state
    garmin_snapshot_normalizer.dart    native payload normalization
    garmin_snapshot_writer.dart        idempotent repository writes
    garmin_token_store.dart            secure, owner-scoped credentials
    garmin_sync_status_store.dart      local operational status
    garmin_region_preference.dart      Garmin CN/global selection
    garmin_sync_issue.dart             stable user-facing issue mapping
  data/health_refresh_coordinator.dart shared source refresh orchestration
  ui/garmin_account_bind_sheet.dart    login and MFA flow
  ui/garmin_sync_status_card.dart      connection and sync status
```

Generated FRB files under `apps/mobile/lib/src/rust/` are outputs and must not
be edited by hand.

## Authentication And Secrets

- The native client supports unauthenticated, pending-MFA, authenticated,
  refreshing, and error states.
- Dart exports/restores the native session through platform secure storage.
- Credentials and session state are partitioned by the active NaviWealth owner.
- Saving the Garmin password is explicit opt-in. Email, password, region, and
  session never enter Drift, Sync v3, Memory, analytics, or application logs.
- Token refresh occurs before expiry. A failed refresh may retry once with
  saved credentials; an MFA challenge returns control to the user.
- Disconnect clears sessions, saved credentials, and local operational status,
  but keeps previously imported health rows.

## Sync Semantics

- Date ranges are bounded and cursor-aware; progress is streamed per day and
  an active operation can be cancelled.
- Snapshot rows use stable Garmin-derived ids. The writer upserts changed rows
  and does not enqueue unchanged rows.
- Import can preserve successful endpoint results while surfacing structured,
  retryable issues for failed endpoints.
- Garmin refresh state and counts are local diagnostics. Imported
  `health_metrics` are normal HealthOS source rows and sync across devices.
- Source precedence and sleep-session deduplication follow the canonical rules
  in [HealthOS](healthos-domain.md), not Garmin-specific UI logic.

## Change Rules

- Keep FRB entrypoints primitive; do not expose `reqwest`, `chrono`, or other
  internal Rust types through generated bindings.
- Keep secrets out of errors and diagnostic payloads.
- Do not move HealthKit or Health Connect platform permission code into Rust.
- Do not introduce Garmin-only persistence outside the Health repository for
  normalized business data.
- New metrics require a real HealthOS consumer, mapping coverage, and an
  explicit decision about canonical source precedence.
- Background work must retain the lightweight-callback/foreground-run split.

## Verification

Prefer the focused contracts below when changing this integration:

```bash
cd apps/mobile
rtk flutter test test/native/frb_garmin_codegen_contract_test.dart
rtk flutter test test/features/health/data/garmin_snapshot_writer_test.dart
rtk flutter test test/features/health/data/garmin_token_store_test.dart
rtk flutter test test/features/health/data/garmin_sync_status_store_test.dart
rtk flutter test test/features/health/data/garmin_sync_issue_test.dart
rtk flutter test test/features/health/data/health_refresh_coordinator_test.dart
rtk flutter test test/features/health/agents/health_background_sync_provider_test.dart
```

Run Rust unit tests for `lifeos_native` when authentication, endpoint mapping,
rate limiting, or cursor behavior changes. Regenerate FRB bindings through the
normal project workflow whenever the public native surface changes.
