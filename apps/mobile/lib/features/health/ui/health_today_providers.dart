/// Read models for Today's recovery, metric cards and seven-day digest.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import '../data/health_metric_selector.dart';
import '../data/health_series.dart';
import '../data/health_series_providers.dart';
import '../data/providers.dart';
import '../data/recovery_scorer.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class HealthTodaySnapshot {
  const HealthTodaySnapshot({required this.now, required this.byKind});
  final DateTime now;
  final Map<HealthMetricKind, List<HealthMetric>> byKind;
  List<HealthMetric> rows(HealthMetricKind kind) => byKind[kind] ?? const [];
  HealthMetric? latest(HealthMetricKind kind) => rows(kind).firstOrNull;
  HealthSeries series(HealthMetricKind kind, {int days = 7}) =>
      buildHealthSeries(
        kind: kind,
        rows: rows(kind),
        window: HealthWindow(now: now, days: days),
      );
}

final healthTodaySnapshotProvider = FutureProvider<HealthTodaySnapshot?>((
  ref,
) async {
  final enabled =
      ref
          .watch(auth.domainOptInsProvider)
          .value
          ?.contains(DomainScope.health) ??
      false;
  ref.watch(activeUserIdProvider);
  if (!enabled) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final owner = await ref.watch(currentUserIdProvider)();
  final now = ref.watch(healthClockProvider)();
  final kinds = HealthMetricKind.values
      .where((k) => k != HealthMetricKind.unknown)
      .toSet();
  final range = await repo.listInRange(
    ownerUserId: owner,
    kinds: kinds,
    from: healthDay(now).subtract(const Duration(days: 92)),
    to: healthDay(now).add(const Duration(days: 2)),
  );
  // Keep old measurements visible rather than sending established users back
  // through activation merely because their last entry is outside this window.
  final latest = await repo.listByKinds(
    ownerUserId: owner,
    kinds: kinds,
    limit: 1,
  );
  final combined = <HealthMetricKind, List<HealthMetric>>{
    for (final kind in kinds)
      kind: {
        for (final row in [...?latest[kind], ...?range[kind]]) row.id: row,
      }.values.toList(),
  };
  return HealthTodaySnapshot(
    now: now,
    byKind: selectCanonicalHealthMetrics(combined),
  );
});

final healthHasAnyDataProvider = FutureProvider.autoDispose<bool>((ref) async {
  final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
  return snapshot?.byKind.values.any((rows) => rows.isNotEmpty) ?? false;
});

final healthHasRecoveryInputsProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
  return snapshot != null &&
      const [
        HealthMetricKind.hrvDaily,
        HealthMetricKind.sleepSession,
        HealthMetricKind.rhrDaily,
        HealthMetricKind.bodyBatteryDaily,
        HealthMetricKind.stressDaily,
        HealthMetricKind.vo2Max,
      ].any((kind) => snapshot.rows(kind).isNotEmpty);
});

class HealthTodayMetricGridModel {
  const HealthTodayMetricGridModel({
    this.byKind = const {},
    this.series = const {},
  });
  factory HealthTodayMetricGridModel.empty() =>
      const HealthTodayMetricGridModel();
  final Map<HealthMetricKind, List<HealthMetric>> byKind;
  final Map<HealthMetricKind, HealthSeries> series;
  HealthMetric? latest(HealthMetricKind kind) => byKind[kind]?.firstOrNull;
  HealthMetric? get weight => latest(HealthMetricKind.weight);
  HealthMetric? get bodyFat => latest(HealthMetricKind.bodyFat);
}

final healthTodayMetricGridProvider =
    FutureProvider.autoDispose<HealthTodayMetricGridModel>((ref) async {
      final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
      if (snapshot == null) return HealthTodayMetricGridModel.empty();
      return HealthTodayMetricGridModel(
        byKind: snapshot.byKind,
        series: {
          for (final kind in snapshot.byKind.keys) kind: snapshot.series(kind),
        },
      );
    });

final recoverySignalProvider =
    FutureProvider.autoDispose<Map<String, Object?>?>((ref) async {
      final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
      if (snapshot == null) return null;
      return const RecoveryScorer()
          .score(
            hrv: snapshot.rows(HealthMetricKind.hrvDaily),
            sleep: snapshot.rows(HealthMetricKind.sleepSession),
            rhr: snapshot.rows(HealthMetricKind.rhrDaily),
            vo2Max: snapshot.rows(HealthMetricKind.vo2Max),
            bodyBattery: snapshot.rows(HealthMetricKind.bodyBatteryDaily),
            stress: snapshot.rows(HealthMetricKind.stressDaily),
            now: snapshot.now.toUtc(),
          )
          .toJson();
    });

class WeeklySummary {
  const WeeklySummary({
    required this.totalSteps,
    required this.avgSleepHours,
    required this.totalWorkoutMinutes,
    required this.avgHrv,
    required this.avgRhr,
    required this.workoutCount,
  });
  final double totalSteps;
  final double avgSleepHours;
  final int totalWorkoutMinutes;
  final double avgHrv;
  final double avgRhr;
  final int workoutCount;
}

/// Exactly seven calendar days. Sleep is summed by wake date before averaging.
final weeklySummaryProvider = FutureProvider.autoDispose<WeeklySummary?>((
  ref,
) async {
  final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
  if (snapshot == null) return null;
  final steps = snapshot.series(HealthMetricKind.stepsDaily);
  final sleep = snapshot.series(HealthMetricKind.sleepSession);
  final workout = snapshot.series(HealthMetricKind.workoutSession);
  final hrv = snapshot.series(HealthMetricKind.hrvDaily);
  final rhr = snapshot.series(HealthMetricKind.rhrDaily);
  if ([steps, sleep, workout, hrv, rhr].every((s) => s.samples.isEmpty)) {
    return null;
  }
  return WeeklySummary(
    totalSteps: steps.total,
    avgSleepHours: sleep.average ?? 0,
    totalWorkoutMinutes: workout.total.round(),
    workoutCount: workout.samples.fold(
      0,
      (count, sample) => count + sample.records.length,
    ),
    avgHrv: hrv.average ?? 0,
    avgRhr: rhr.average ?? 0,
  );
});
