/// HealthOS Drift tables (`docs/domains/healthos-domain.md` §3, D-2.1).
///
/// Lives in `core/persistence/` alongside the Finance tables because
/// Drift currently requires every table to be passed to a single
/// `@DriftDatabase(tables: [...])` annotation. The schema row family
/// for sync uses the `health:` prefix introduced in D-1.4
/// (`docs/architecture/lifeos-shell.md` §8).
library;

import 'package:drift/drift.dart';

import 'tables.dart' show SyncableTable;

/// All HealthOS measurements live in one wide-flat table keyed by
/// [kind]. This matches `docs/domains/healthos-domain.md` §3: a sleep
/// session, an HRV daily reading, and a steps daily reading are all
/// rows here, distinguished by the [kind] discriminator.
///
/// Sync row_kind: `health:health_metrics` (see `docs/architecture/lifeos-shell.md`
/// §8 row family namespace, D-1.4).
@DataClassName('HealthMetricRow')
class HealthMetrics extends Table with SyncableTable {
  /// String UUID. Same convention as Finance tables — primitive ints
  /// don't survive multi-device sync.
  TextColumn get id => text()();

  /// Wall-time the measurement is *about*. For a sleep session this
  /// is the session start; for a daily summary it is the start of the
  /// local calendar day, captured in UTC.
  DateTimeColumn get capturedAt => dateTime()();

  /// Discriminator: `'sleep_session'`, `'hrv_daily'`, `'steps_daily'`,
  /// `'rhr_daily'`, `'active_energy_daily'`, `'weight'`, `'body_fat'`,
  /// ... Stored as text rather than an int enum so a future kind can
  /// land without an Drift schema bump.
  TextColumn get kind => text()();

  /// Numeric value. Sleep sessions store duration in seconds; HRV in
  /// ms; steps as a count; energy in kcal; weight in kg; body fat as
  /// a fraction (0.0–1.0). The semantic is keyed by [kind] + [unit].
  RealColumn get value => real()();

  /// SI-style unit string (`'s'`, `'ms'`, `'count'`, `'kcal'`,
  /// `'kg'`, `'fraction'`). Kept explicit so a unit mistake never
  /// silently corrupts a trend chart.
  TextColumn get unit => text()();

  /// Optional payload for kind-specific extra fields (sleep stages
  /// histogram, HRV averaging window, source app etc.) JSON-encoded.
  /// Keeping it loose at the schema level so [kind]-specific projections
  /// can evolve without column churn.
  TextColumn get payloadJson => text().nullable()();

  /// Best-effort attribution. iPhone / Apple Watch / Garmin / manual.
  /// Free-text so the on-device adapter can pass through whatever
  /// HealthKit / Health Connect surfaces.
  TextColumn get sourceDevice => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
