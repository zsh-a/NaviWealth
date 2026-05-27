/// HealthOS platform → local DB sync (`docs/healthos-domain.md` §2,
/// D-2.2).
///
/// Reads from a [HealthPlatformAdapter], maps each raw reading into the
/// HealthOS canonical [HealthMetric] shape, and upserts via
/// [HealthMetricRepository]. Stable platform UUIDs (`hk:…` / `hc:…`)
/// flow into [HealthMetric.id] so repeated syncs are idempotent — the
/// Memory indexer downstream is already idempotent by stable id, so the
/// sync chain produces no duplicate events / memories.
///
/// **Not in scope** (deferred to D-2.5b / future):
///   * background fetch / WorkManager scheduling — manual trigger only
///   * write-back to HealthKit / Health Connect (§10 反目标)
///   * sleep-segment grouping on iOS (one row per asleep segment)
library;

import 'dart:convert';

import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
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
  })  : completedAt = startedAt,
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
  })  : _adapter = adapter,
        _repo = repository,
        _stamper = stamper,
        _clock = clock ?? _defaultClock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  final HealthPlatformAdapter _adapter;
  final HealthMetricRepository _repo;
  final MutationStamper _stamper;
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

    var upserted = 0;
    var unchanged = 0;

    for (final s in snapshot.sleepSessions) {
      final metric = _sleepMetric(s);
      final result = await _upsertIfChanged(metric);
      result == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final d in snapshot.hrv) {
      final m = _dailyMetric(d, HealthMetricKind.hrvDaily);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final d in snapshot.rhr) {
      final m = _dailyMetric(d, HealthMetricKind.rhrDaily);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final d in snapshot.steps) {
      final m = _dailyMetric(d, HealthMetricKind.stepsDaily);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final d in snapshot.activeEnergy) {
      final m = _dailyMetric(d, HealthMetricKind.activeEnergyDaily);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final p in snapshot.weight) {
      final m = _pointMetric(p, HealthMetricKind.weight);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final p in snapshot.bodyFat) {
      final m = _pointMetric(p, HealthMetricKind.bodyFat);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final w in snapshot.workouts) {
      final m = _workoutMetric(w);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final d in snapshot.vo2Max) {
      final m = _dailyMetric(d, HealthMetricKind.vo2Max);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }
    for (final d in snapshot.distanceWalkingRunning) {
      final m = _dailyMetric(d, HealthMetricKind.distanceWalkingRunningDaily);
      final r = await _upsertIfChanged(m);
      r == _WriteOutcome.upserted ? upserted++ : unchanged++;
    }

    return HealthSyncResult(
      startedAt: startedAt,
      completedAt: _clock(),
      totalFetched: snapshot.totalCount,
      upserted: upserted,
      unchanged: unchanged,
    );
  }

  /// Drop the row in if a `findById`-equivalent row doesn't exist or
  /// the data side of the row differs. Saves the outbox from N
  /// duplicate enqueues on every re-sync — the stamper bumps the HLC
  /// only when we actually write.
  Future<_WriteOutcome> _upsertIfChanged(HealthMetric unstamped) async {
    final existing = await _repo.findById(unstamped.id);
    if (existing != null && _payloadEquivalent(existing, unstamped)) {
      return _WriteOutcome.unchanged;
    }
    final stamp = await _stamper.stamp();
    final stamped = unstamped.copyWith(
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _repo.upsert(stamped);
    return _WriteOutcome.upserted;
  }

  bool _payloadEquivalent(HealthMetric a, HealthMetric b) {
    return a.kind == b.kind &&
        a.capturedAt.isAtSameMomentAs(b.capturedAt) &&
        a.value == b.value &&
        a.unit == b.unit &&
        a.payloadJson == b.payloadJson &&
        a.sourceDevice == b.sourceDevice;
  }

  HealthMetric _sleepMetric(RawSleepSession s) => HealthMetric(
        id: s.externalId,
        capturedAt: s.startedAt,
        kind: HealthMetricKind.sleepSession,
        value: s.duration.inSeconds.toDouble(),
        unit: HealthMetricKind.sleepSession.defaultUnit,
        payloadJson: s.stageHistogramJson,
        sourceDevice: s.sourceDevice,
        sync: _placeholderSync,
      );

  HealthMetric _dailyMetric(RawDailyValue d, HealthMetricKind kind) =>
      HealthMetric(
        id: d.externalId,
        capturedAt: d.day,
        kind: kind,
        value: d.value,
        unit: kind.defaultUnit,
        sourceDevice: d.sourceDevice,
        sync: _placeholderSync,
      );

  HealthMetric _pointMetric(RawPointValue p, HealthMetricKind kind) =>
      HealthMetric(
        id: p.externalId,
        capturedAt: p.measuredAt,
        kind: kind,
        value: p.value,
        unit: kind.defaultUnit,
        sourceDevice: p.sourceDevice,
        sync: _placeholderSync,
      );

  HealthMetric _workoutMetric(RawWorkoutSession w) {
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
    return HealthMetric(
      id: w.externalId,
      capturedAt: w.startedAt,
      kind: HealthMetricKind.workoutSession,
      value: w.duration.inSeconds.toDouble(),
      unit: HealthMetricKind.workoutSession.defaultUnit,
      payloadJson: payload.isEmpty ? null : jsonEncode(payload),
      sourceDevice: w.sourceDevice,
      sync: _placeholderSync,
    );
  }

  /// Sync meta is replaced via [HealthMetric.copyWith] in
  /// [_upsertIfChanged] right before the write — we only call
  /// [MutationStamper.stamp] when we actually persist, so unchanged
  /// rows neither bump the HLC nor allocate an outbox op.
  static final SyncMeta _placeholderSync = SyncMeta(
    ownerUserId: '',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedByDevice: '',
    hlc: Hlc.zero('placeholder'),
  );
}

enum _WriteOutcome { upserted, unchanged }
