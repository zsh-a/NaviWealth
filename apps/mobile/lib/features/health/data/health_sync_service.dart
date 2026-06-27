/// HealthOS platform → local DB sync (`docs/domains/healthos-domain.md` §2,
/// D-2.2).
///
/// Reads from a [HealthPlatformAdapter], maps each raw reading into the
/// HealthOS canonical [HealthMetric] shape, and upserts via
/// [HealthMetricRepository]. Stable platform UUIDs (`hk:…` / `hc:…`)
/// flow into [HealthMetric.id] so repeated syncs are idempotent — the
/// Memory indexer downstream is already idempotent by stable id, so the
/// sync chain produces no duplicate events / memories.
///
/// **Not in scope**:
///   * write-back to HealthKit / Health Connect (§10 反目标)
///   * sleep-segment grouping on iOS (one row per asleep segment)
library;

import 'dart:convert';

import 'package:naviwealth/core/sync/mutation_context.dart';

import '../domain/health_metric_kind.dart';
import 'health_metric_ingestor.dart';
import 'health_metric_repository.dart';
import 'health_platform_adapter.dart';

/// Outcome of one [HealthSyncService.syncRange] call. Used by the
/// Settings UI to render "Synced N readings · last at HH:MM" and to
/// surface adapter failures without throwing into the widget tree.
class HealthSyncResult {
  const HealthSyncResult({
    required this.startedAt,
    required this.completedAt,
    required this.totalFetched,
    required this.upserted,
    required this.unchanged,
    this.errorMessage,
  });

  const HealthSyncResult.skipped({
    required this.startedAt,
    required this.errorMessage,
  }) : completedAt = startedAt,
       totalFetched = 0,
       upserted = 0,
       unchanged = 0;

  final DateTime startedAt;
  final DateTime completedAt;
  final int totalFetched;
  final int upserted;
  final int unchanged;
  final String? errorMessage;

  Duration get elapsed => completedAt.difference(startedAt);
  bool get ok => errorMessage == null;
}

/// Default lookback window when the caller doesn't pass one. Matches
/// what the AI tools (`get_recent_sleep_summary` etc.) read out, so a
/// fresh install reaches steady-state quickly.
const Duration kDefaultHealthSyncWindow = Duration(days: 30);

class HealthSyncService {
  HealthSyncService({
    required HealthPlatformAdapter adapter,
    required HealthMetricRepository repository,
    required MutationStamper stamper,
    DateTime Function()? clock,
  }) : _adapter = adapter,
       _ingestor = HealthMetricIngestor(
         repository: repository,
         stamper: stamper,
       ),
       _clock = clock ?? _defaultClock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  final HealthPlatformAdapter _adapter;
  final HealthMetricIngestor _ingestor;
  final DateTime Function() _clock;

  /// Pass-through to the adapter — Settings UI calls this when the
  /// user taps "Connect HealthKit".
  Future<bool> requestPermissions() => _adapter.requestPermissions();

  Future<bool> isAvailable() => _adapter.isAvailable();

  Future<bool> hasPermissions() => _adapter.hasPermissions();

  /// Pull the last [window] of platform health data and upsert into
  /// `health_metrics`. Returns a [HealthSyncResult] either way — never
  /// throws, so the UI button can render a toast for both branches.
  Future<HealthSyncResult> syncRange({
    Duration window = kDefaultHealthSyncWindow,
    DateTime? from,
    DateTime? to,
  }) async {
    final startedAt = _clock();
    final effectiveTo = to ?? startedAt;
    final effectiveFrom = from ?? effectiveTo.subtract(window);

    if (!await _adapter.isAvailable()) {
      return HealthSyncResult.skipped(
        startedAt: startedAt,
        errorMessage: 'health-platform-unavailable',
      );
    }
    if (!await _adapter.hasPermissions()) {
      return HealthSyncResult.skipped(
        startedAt: startedAt,
        errorMessage: 'health-platform-permission-denied',
      );
    }

    HealthPlatformSnapshot snapshot;
    try {
      snapshot = await _adapter.fetchRange(
        from: effectiveFrom,
        to: effectiveTo,
      );
    } on Object catch (e) {
      return HealthSyncResult.skipped(
        startedAt: startedAt,
        errorMessage: 'health-platform-fetch-failed: $e',
      );
    }

    final ingest = await _ingestor.ingestRaw(_metricsFromSnapshot(snapshot));

    return HealthSyncResult(
      startedAt: startedAt,
      completedAt: _clock(),
      totalFetched: snapshot.totalCount,
      upserted: ingest.upserted,
      unchanged: ingest.unchanged,
    );
  }

  Iterable<RawHealthMetric> _metricsFromSnapshot(
    HealthPlatformSnapshot snapshot,
  ) sync* {
    for (final s in snapshot.sleepSessions) {
      yield _sleepMetric(s);
    }
    for (final d in snapshot.hrv) {
      yield _dailyMetric(d, HealthMetricKind.hrvDaily);
    }
    for (final d in snapshot.rhr) {
      yield _dailyMetric(d, HealthMetricKind.rhrDaily);
    }
    for (final d in snapshot.steps) {
      yield _dailyMetric(d, HealthMetricKind.stepsDaily);
    }
    for (final d in snapshot.activeEnergy) {
      yield _dailyMetric(d, HealthMetricKind.activeEnergyDaily);
    }
    for (final p in snapshot.weight) {
      yield _pointMetric(p, HealthMetricKind.weight);
    }
    for (final p in snapshot.bodyFat) {
      yield _pointMetric(p, HealthMetricKind.bodyFat);
    }
    for (final w in snapshot.workouts) {
      yield _workoutMetric(w);
    }
    for (final d in snapshot.vo2Max) {
      yield _dailyMetric(d, HealthMetricKind.vo2Max);
    }
    for (final d in snapshot.distanceWalkingRunning) {
      yield _dailyMetric(d, HealthMetricKind.distanceWalkingRunningDaily);
    }
    for (final d in snapshot.heartRate) {
      yield _dailyMetric(d, HealthMetricKind.heartRateDaily);
    }
    for (final d in snapshot.totalEnergy) {
      yield _dailyMetric(d, HealthMetricKind.totalEnergyDaily);
    }
    for (final d in snapshot.floorsClimbed) {
      yield _dailyMetric(d, HealthMetricKind.floorsClimbedDaily);
    }
    for (final d in snapshot.respiratoryRate) {
      yield _dailyMetric(d, HealthMetricKind.respiratoryRateDaily);
    }
  }

  RawHealthMetric _sleepMetric(RawSleepSession s) => RawHealthMetric(
    id: s.externalId,
    capturedAt: s.startedAt,
    kind: HealthMetricKind.sleepSession,
    value: s.duration.inSeconds.toDouble(),
    unit: HealthMetricKind.sleepSession.defaultUnit,
    payloadJson: s.stageHistogramJson,
    sourceDevice: s.sourceDevice,
  );

  RawHealthMetric _dailyMetric(RawDailyValue d, HealthMetricKind kind) =>
      RawHealthMetric(
        id: d.externalId,
        capturedAt: d.day,
        kind: kind,
        value: d.value,
        unit: kind.defaultUnit,
        sourceDevice: d.sourceDevice,
      );

  RawHealthMetric _pointMetric(RawPointValue p, HealthMetricKind kind) =>
      RawHealthMetric(
        id: p.externalId,
        capturedAt: p.measuredAt,
        kind: kind,
        value: p.value,
        unit: kind.defaultUnit,
        sourceDevice: p.sourceDevice,
      );

  RawHealthMetric _workoutMetric(RawWorkoutSession w) {
    // Stable, canonical payload so `_payloadEquivalent` can rely on
    // string equality. Keep fields in a fixed order via the literal
    // map and only include non-null values to avoid string churn when
    // the platform omits a field.
    final payload = <String, Object?>{
      if (w.activityType != null) 'activity_type': w.activityType,
      if (w.totalEnergyKcal != null) 'total_energy_kcal': w.totalEnergyKcal,
      if (w.totalDistanceMeters != null)
        'total_distance_meters': w.totalDistanceMeters,
    };
    return RawHealthMetric(
      id: w.externalId,
      capturedAt: w.startedAt,
      kind: HealthMetricKind.workoutSession,
      value: w.duration.inSeconds.toDouble(),
      unit: HealthMetricKind.workoutSession.defaultUnit,
      payloadJson: payload.isEmpty ? null : jsonEncode(payload),
      sourceDevice: w.sourceDevice,
    );
  }
}
