/// Read models for Today's recovery, metric cards and seven-day digest.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import '../data/health_metric_selector.dart';
import '../data/health_preferences.dart';
import '../data/health_series.dart';
import '../data/health_series_providers.dart';
import '../data/providers.dart';
import '../data/recovery_scorer.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class HealthTodaySnapshot {
  const HealthTodaySnapshot({
    required this.now,
    required this.byKind,
    this.rawByKind,
    this.preferences = const HealthPreferences(),
  });
  final DateTime now;
  final Map<HealthMetricKind, List<HealthMetric>> byKind;
  final Map<HealthMetricKind, List<HealthMetric>>? rawByKind;
  final HealthPreferences preferences;
  List<HealthMetric> rawRows(HealthMetricKind kind) =>
      rawByKind?[kind] ?? rows(kind);
  List<HealthMetric> rows(HealthMetricKind kind) => byKind[kind] ?? const [];
  HealthMetric? latest(HealthMetricKind kind) => rows(kind).firstOrNull;
  HealthSeries series(HealthMetricKind kind, {int days = 7}) =>
      buildHealthSeries(
        kind: kind,
        rows: rawRows(kind),
        window: HealthWindow(now: now, days: days),
        preferredSource: preferences.sources[kind],
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
  ref.watch(healthCalendarDayProvider);
  final repoFuture = ref.watch(healthMetricRepositoryProvider.future);
  final ownerFuture = ref.watch(currentUserIdProvider)();
  final preferencesFuture = ref.watch(healthPreferencesProvider.future);
  final now = ref.watch(healthClockProvider)();
  final repo = await repoFuture;
  final owner = await ownerFuture;
  final preferences = await preferencesFuture;
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
    byKind: selectCanonicalHealthMetrics(
      combined,
      preferredSources: preferences.sources,
    ),
    rawByKind: combined,
    preferences: preferences,
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
            hrv: snapshot.rawRows(HealthMetricKind.hrvDaily),
            sleep: snapshot.rawRows(HealthMetricKind.sleepSession),
            rhr: snapshot.rawRows(HealthMetricKind.rhrDaily),
            vo2Max: snapshot.rawRows(HealthMetricKind.vo2Max),
            bodyBattery: snapshot.rawRows(HealthMetricKind.bodyBatteryDaily),
            stress: snapshot.rawRows(HealthMetricKind.stressDaily),
            preferredSources: snapshot.preferences.sources,
            sleepGoalHours: snapshot.preferences.sleepGoalHours,
            now: snapshot.now,
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
