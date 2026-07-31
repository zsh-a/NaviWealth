/// Today-page state plumbing (`docs/domains/healthos-domain.md` §5, D-2.7).
///
/// Each provider exposes a single signal the Today UI renders as a card.
/// Kept in `features/health/ui/` rather than `data/providers.dart`
/// because the shapes here are UI-flavoured (recovery `inputs` map,
/// pre-rounded hours, …) — `data/providers.dart` stays close to the
/// raw repository.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../data/health_metric_selector.dart';
import '../data/providers.dart';
import '../data/recovery_scorer.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

const Set<HealthMetricKind> _kHealthTodayMetricKinds = <HealthMetricKind>{
  HealthMetricKind.sleepSession,
  HealthMetricKind.hrvDaily,
  HealthMetricKind.heartRateDaily,
  HealthMetricKind.workoutSession,
  HealthMetricKind.stepsDaily,
  HealthMetricKind.distanceWalkingRunningDaily,
  HealthMetricKind.activeEnergyDaily,
  HealthMetricKind.stressDaily,
  HealthMetricKind.bodyBatteryDaily,
  HealthMetricKind.rhrDaily,
  HealthMetricKind.trainingLoadDaily,
  HealthMetricKind.spo2Daily,
  HealthMetricKind.vo2Max,
};

class _HealthTodaySnapshot {
  const _HealthTodaySnapshot({required this.now, required this.byKind});

  final DateTime now;
  final Map<HealthMetricKind, List<HealthMetric>> byKind;

  List<HealthMetric> rows(HealthMetricKind kind) =>
      byKind[kind] ?? const <HealthMetric>[];

  HealthMetric? latest(HealthMetricKind kind) {
    final values = rows(kind);
    if (values.isEmpty) return null;
    // Repository + canonical selector both preserve newest-first order.
    return values.first;
  }
}

final healthTodaySnapshotProvider = FutureProvider<_HealthTodaySnapshot?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final data = await repo.listByKinds(
    ownerUserId: userId,
    kinds: _kHealthTodayMetricKinds,
    limit: 100,
  );
  return _HealthTodaySnapshot(
    now: DateTime.now().toUtc(),
    byKind: selectCanonicalHealthMetrics(data),
  );
});

final healthHasAnyDataProvider = FutureProvider.autoDispose<bool>((ref) async {
  final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
  return snapshot != null &&
      snapshot.byKind.values.any((rows) => rows.isNotEmpty);
});

class HealthTodayMetricGridModel {
  const HealthTodayMetricGridModel({
    this.sleep,
    this.hrv,
    this.heartRate,
    this.workout,
    this.steps,
    this.energy,
    this.bodyBattery,
    this.stress,
    this.rhr,
    this.trainingLoad,
    this.spo2,
    this.sleepTrend,
    this.bodyBatteryTrend,
    this.stressTrend,
    this.hrvTrend,
    this.heartRateTrend,
    this.rhrTrend,
    this.stepsTrend,
    this.energyTrend,
  });

  factory HealthTodayMetricGridModel.empty() =>
      const HealthTodayMetricGridModel();

  factory HealthTodayMetricGridModel._fromSnapshot(_HealthTodaySnapshot s) {
    return HealthTodayMetricGridModel(
      sleep: s.latest(HealthMetricKind.sleepSession),
      hrv: s.latest(HealthMetricKind.hrvDaily),
      heartRate: s.latest(HealthMetricKind.heartRateDaily),
      workout: s.latest(HealthMetricKind.workoutSession),
      steps: s.latest(HealthMetricKind.stepsDaily),
      energy: s.latest(HealthMetricKind.activeEnergyDaily),
      bodyBattery: s.latest(HealthMetricKind.bodyBatteryDaily),
      stress: s.latest(HealthMetricKind.stressDaily),
      rhr: s.latest(HealthMetricKind.rhrDaily),
      trainingLoad: s.latest(HealthMetricKind.trainingLoadDaily),
      spo2: s.latest(HealthMetricKind.spo2Daily),
      sleepTrend: _metricTrendFromSnapshot(s, HealthMetricKind.sleepSession),
      bodyBatteryTrend: _metricTrendFromSnapshot(
        s,
        HealthMetricKind.bodyBatteryDaily,
      ),
      stressTrend: _metricTrendFromSnapshot(s, HealthMetricKind.stressDaily),
      hrvTrend: _metricTrendFromSnapshot(s, HealthMetricKind.hrvDaily),
      heartRateTrend: _metricTrendFromSnapshot(
        s,
        HealthMetricKind.heartRateDaily,
      ),
      rhrTrend: _metricTrendFromSnapshot(s, HealthMetricKind.rhrDaily),
      stepsTrend: _metricTrendFromSnapshot(s, HealthMetricKind.stepsDaily),
      energyTrend: _metricTrendFromSnapshot(
        s,
        HealthMetricKind.activeEnergyDaily,
      ),
    );
  }

  final HealthMetric? sleep;
  final HealthMetric? hrv;
  final HealthMetric? heartRate;
  final HealthMetric? workout;
  final HealthMetric? steps;
  final HealthMetric? energy;
  final HealthMetric? bodyBattery;
  final HealthMetric? stress;
  final HealthMetric? rhr;
  final HealthMetric? trainingLoad;
  final HealthMetric? spo2;

  final MetricTrend? sleepTrend;
  final MetricTrend? bodyBatteryTrend;
  final MetricTrend? stressTrend;
  final MetricTrend? hrvTrend;
  final MetricTrend? heartRateTrend;
  final MetricTrend? rhrTrend;
  final MetricTrend? stepsTrend;
  final MetricTrend? energyTrend;
}

final healthTodayMetricGridProvider =
    FutureProvider.autoDispose<HealthTodayMetricGridModel>((ref) async {
      final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
      if (snapshot == null) return HealthTodayMetricGridModel.empty();
      return HealthTodayMetricGridModel._fromSnapshot(snapshot);
    });

Future<HealthMetric?> _latest(Ref ref, HealthMetricKind kind) async {
  final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
  return snapshot?.latest(kind);
}

/// Newest sleep session row, or `null` when HealthOS is off / no data.
final latestSleepSessionProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.sleepSession),
);

/// Newest HRV daily row.
final latestHrvProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.hrvDaily),
);

/// Newest daily average heart-rate row. Garmin Health Connect sharing
/// reliably exposes heart rate even when HRV/RHR are absent.
final latestHeartRateProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.heartRateDaily),
);

/// Newest workout session row.
final latestWorkoutProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.workoutSession),
);

/// Newest daily step count row.
final latestStepsProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.stepsDaily),
);

/// Newest daily walking + running distance row (meters).
final latestWalkingDistanceProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.distanceWalkingRunningDaily),
);

/// Newest daily active-energy row (kcal burned through activity).
final latestActiveEnergyProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.activeEnergyDaily),
);

/// Newest daily stress level row (Garmin-specific).
final latestStressProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.stressDaily),
);

/// Newest daily Body Battery row (Garmin-specific).
final latestBodyBatteryProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.bodyBatteryDaily),
);

/// Newest resting heart rate row.
final latestRhrProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.rhrDaily),
);

/// Newest training load row (Garmin-specific).
final latestTrainingLoadProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.trainingLoadDaily),
);

/// Newest SpO2 (blood oxygen) row.
final latestSpo2Provider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) => _latest(ref, HealthMetricKind.spo2Daily),
);

/// Last 7 days of HRV values for the recovery sparkline.
/// Returns a list of (dayIndex, value) pairs, oldest-first.
final recoverySparklineProvider = FutureProvider.autoDispose<List<double>>((
  ref,
) async {
  final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
  if (snapshot == null) return const <double>[];
  final cutoff = snapshot.now.subtract(const Duration(days: 7));
  final rows = snapshot.rows(HealthMetricKind.hrvDaily);
  final inWindow = rows.where((m) => !m.capturedAt.isBefore(cutoff)).toList()
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return inWindow.map((m) => m.value).toList();
});

/// Recovery signal output, computed off the same shaper the AI tool
/// uses. Returned `null` when HealthOS is off so the UI can render an
/// empty state instead of confusing zeros.
final recoverySignalProvider =
    FutureProvider.autoDispose<Map<String, Object?>?>((ref) async {
      final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
      if (snapshot == null) return null;
      const scorer = RecoveryScorer();
      final result = scorer.score(
        hrv: snapshot.rows(HealthMetricKind.hrvDaily),
        sleep: snapshot.rows(HealthMetricKind.sleepSession),
        rhr: snapshot.rows(HealthMetricKind.rhrDaily),
        vo2Max: snapshot.rows(HealthMetricKind.vo2Max),
        bodyBattery: snapshot.rows(HealthMetricKind.bodyBatteryDaily),
        stress: snapshot.rows(HealthMetricKind.stressDaily),
      );
      return result.toJson();
    });

/// Trend direction and delta for a metric kind over the last 7 days.
/// Returns `null` when insufficient data.
///
/// Compares the most recent 3-day average against the prior 4-day average.
/// For sleep sessions, value is converted from seconds to hours before
/// comparison.
final metricTrendProvider = FutureProvider.autoDispose
    .family<MetricTrend?, HealthMetricKind>((ref, kind) async {
      final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
      if (snapshot == null) return null;
      return _metricTrendFromSnapshot(snapshot, kind);
    });

MetricTrend? _metricTrendFromSnapshot(
  _HealthTodaySnapshot snapshot,
  HealthMetricKind kind,
) {
  final rows = snapshot.rows(kind);
  if (rows.length < 3) return null;

  final recentCutoff = snapshot.now.subtract(const Duration(days: 3));
  final priorCutoff = snapshot.now.subtract(const Duration(days: 7));

  double convert(HealthMetric m) {
    if (kind == HealthMetricKind.sleepSession) {
      return m.value / 3600; // seconds → hours
    }
    if (kind == HealthMetricKind.distanceWalkingRunningDaily) {
      return m.value / 1000; // meters → km
    }
    return m.value;
  }

  final recent = <double>[];
  final prior = <double>[];
  for (final m in rows) {
    if (m.capturedAt.isAfter(recentCutoff)) {
      recent.add(convert(m));
    } else if (m.capturedAt.isAfter(priorCutoff)) {
      prior.add(convert(m));
    }
  }

  if (recent.isEmpty || prior.isEmpty) return null;

  final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
  final priorAvg = prior.reduce((a, b) => a + b) / prior.length;
  if (priorAvg == 0) return null;

  final deltaPct = ((recentAvg - priorAvg) / priorAvg * 100);
  return MetricTrend(deltaPct: deltaPct, higherIsBetter: kind.higherIsBetter);
}

/// Trend data for a metric.
class MetricTrend {
  const MetricTrend({required this.deltaPct, required this.higherIsBetter});
  final double deltaPct;
  final bool? higherIsBetter;

  bool? get isFavorable {
    if (higherIsBetter == null || direction == TrendDirection.flat) return null;
    return higherIsBetter! ? deltaPct > 0 : deltaPct < 0;
  }

  /// Positive = up, negative = down, near zero = flat.
  TrendDirection get direction {
    if (deltaPct > 3) return TrendDirection.up;
    if (deltaPct < -3) return TrendDirection.down;
    return TrendDirection.flat;
  }
}

enum TrendDirection { up, down, flat }

/// Weekly summary data for the Today page.
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

/// Aggregated 7-day summary for the "This Week" panel.
final weeklySummaryProvider = FutureProvider.autoDispose<WeeklySummary?>((
  ref,
) async {
  final snapshot = await ref.watch(healthTodaySnapshotProvider.future);
  if (snapshot == null) return null;
  final cutoff = snapshot.now.subtract(const Duration(days: 7));
  List<HealthMetric> metricsFor(HealthMetricKind kind) => snapshot.rows(kind);

  double totalSteps = 0;
  double totalSleepHours = 0;
  int sleepCount = 0;
  int totalWorkoutSecs = 0;
  int workoutCount = 0;
  double hrvSum = 0;
  int hrvCount = 0;
  double rhrSum = 0;
  int rhrCount = 0;

  for (final m in metricsFor(HealthMetricKind.stepsDaily)) {
    if (m.capturedAt.isAfter(cutoff)) totalSteps += m.value;
  }
  for (final m in metricsFor(HealthMetricKind.sleepSession)) {
    if (!m.capturedAt.isAfter(cutoff)) continue;
    totalSleepHours += switch (m.unit) {
      's' => m.value / 3600.0,
      'min' => m.value / 60.0,
      'h' => m.value,
      _ => m.value / 3600.0,
    };
    sleepCount++;
  }
  for (final m in metricsFor(HealthMetricKind.workoutSession)) {
    if (!m.capturedAt.isAfter(cutoff)) continue;
    totalWorkoutSecs += m.value.round();
    workoutCount++;
  }
  for (final m in metricsFor(HealthMetricKind.hrvDaily)) {
    if (!m.capturedAt.isAfter(cutoff)) continue;
    hrvSum += m.value;
    hrvCount++;
  }
  for (final m in metricsFor(HealthMetricKind.rhrDaily)) {
    if (!m.capturedAt.isAfter(cutoff)) continue;
    rhrSum += m.value;
    rhrCount++;
  }

  if (totalSteps == 0 &&
      sleepCount == 0 &&
      workoutCount == 0 &&
      hrvCount == 0) {
    return null;
  }

  return WeeklySummary(
    totalSteps: totalSteps,
    avgSleepHours: sleepCount > 0 ? totalSleepHours / sleepCount : 0,
    totalWorkoutMinutes: (totalWorkoutSecs / 60).round(),
    avgHrv: hrvCount > 0 ? hrvSum / hrvCount : 0,
    avgRhr: rhrCount > 0 ? rhrSum / rhrCount : 0,
    workoutCount: workoutCount,
  );
});
