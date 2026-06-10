/// Today-page state plumbing (`docs/healthos-domain.md` §5, D-2.7).
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
import '../data/providers.dart';
import '../data/recovery_scorer.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

/// Newest sleep session row, or `null` when HealthOS is off / no data.
final latestSleepSessionProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.sleepSession,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest HRV daily row.
final latestHrvProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.hrvDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest daily average heart-rate row. Garmin Health Connect sharing
/// reliably exposes heart rate even when HRV/RHR are absent.
final latestHeartRateProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.heartRateDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest workout session row.
final latestWorkoutProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.workoutSession,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest daily step count row.
final latestStepsProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.stepsDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest daily walking + running distance row (meters).
final latestWalkingDistanceProvider = FutureProvider.autoDispose<HealthMetric?>(
  (ref) async {
    final optIns = ref.watch(core_auth.domainOptInsProvider).value;
    if (optIns == null || !optIns.contains(DomainScope.health)) return null;
    final repo = await ref.watch(healthMetricRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final rows = await repo.listByKind(
      ownerUserId: userId,
      kind: HealthMetricKind.distanceWalkingRunningDaily,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  },
);

/// Newest daily active-energy row (kcal burned through activity).
final latestActiveEnergyProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.activeEnergyDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest daily stress level row (Garmin-specific).
final latestStressProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.stressDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest daily Body Battery row (Garmin-specific).
final latestBodyBatteryProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.bodyBatteryDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest resting heart rate row.
final latestRhrProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.rhrDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest training load row (Garmin-specific).
final latestTrainingLoadProvider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.trainingLoadDaily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Newest SpO2 (blood oxygen) row.
final latestSpo2Provider = FutureProvider.autoDispose<HealthMetric?>((
  ref,
) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) return null;
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.spo2Daily,
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
});

/// Last 7 days of HRV values for the recovery sparkline.
/// Returns a list of (dayIndex, value) pairs, oldest-first.
final recoverySparklineProvider =
    FutureProvider.autoDispose<List<double>>((ref) async {
  final optIns = ref.watch(core_auth.domainOptInsProvider).value;
  if (optIns == null || !optIns.contains(DomainScope.health)) {
    return const <double>[];
  }
  final repo = await ref.watch(healthMetricRepositoryProvider.future);
  final userId = await ref.read(currentUserIdProvider)();
  final rows = await repo.listByKind(
    ownerUserId: userId,
    kind: HealthMetricKind.hrvDaily,
    limit: 10,
  );
  final now = DateTime.now().toUtc();
  final cutoff = now.subtract(const Duration(days: 7));
  final inWindow = rows
      .where((m) => !m.capturedAt.isBefore(cutoff))
      .toList()
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return inWindow.map((m) => m.value).toList();
});

/// Recovery signal output, computed off the same shaper the AI tool
/// uses. Returned `null` when HealthOS is off so the UI can render an
/// empty state instead of confusing zeros.
final recoverySignalProvider =
    FutureProvider.autoDispose<Map<String, Object?>?>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      final data = await repo.listByKinds(
        ownerUserId: userId,
        kinds: const {
          HealthMetricKind.hrvDaily,
          HealthMetricKind.sleepSession,
          HealthMetricKind.rhrDaily,
          HealthMetricKind.vo2Max,
          HealthMetricKind.bodyBatteryDaily,
          HealthMetricKind.stressDaily,
        },
        limit: 50,
      );
      final hrv = data[HealthMetricKind.hrvDaily] ?? const [];
      final sleep = data[HealthMetricKind.sleepSession] ?? const [];
      final rhr = data[HealthMetricKind.rhrDaily] ?? const [];
      final vo2 = data[HealthMetricKind.vo2Max] ?? const [];
      final bb = data[HealthMetricKind.bodyBatteryDaily] ?? const [];
      final stressData = data[HealthMetricKind.stressDaily] ?? const [];
      const scorer = RecoveryScorer();
      final result = scorer.score(
        hrv: hrv,
        sleep: sleep,
        rhr: rhr,
        vo2Max: vo2,
        bodyBattery: bb,
        stress: stressData,
      );
      return <String, Object?>{
        'score': result.score,
        'verdict': result.verdict,
        'inputs': result.inputs,
      };
    });

/// Trend direction and delta for a metric kind over the last 7 days.
/// Returns `null` when insufficient data.
///
/// Compares the most recent 3-day average against the prior 4-day average.
/// For sleep sessions, value is converted from seconds to hours before
/// comparison.
final metricTrendProvider = FutureProvider.autoDispose
    .family<MetricTrend?, HealthMetricKind>((ref, kind) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      final rows = await repo.listByKind(
        ownerUserId: userId,
        kind: kind,
        limit: 30,
      );
      if (rows.length < 3) return null;

      final now = DateTime.now().toUtc();
      final recentCutoff = now.subtract(const Duration(days: 3));
      final priorCutoff = now.subtract(const Duration(days: 7));

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
      return MetricTrend(deltaPct: deltaPct);
    });

/// Trend data for a metric.
class MetricTrend {
  const MetricTrend({required this.deltaPct});
  final double deltaPct;

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
final weeklySummaryProvider =
    FutureProvider.autoDispose<WeeklySummary?>((ref) async {
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      if (optIns == null || !optIns.contains(DomainScope.health)) return null;
      final repo = await ref.watch(healthMetricRepositoryProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      final now = DateTime.now().toUtc();
      final cutoff = now.subtract(const Duration(days: 7));

      final data = await repo.listByKinds(
        ownerUserId: userId,
        kinds: const {
          HealthMetricKind.stepsDaily,
          HealthMetricKind.sleepSession,
          HealthMetricKind.workoutSession,
          HealthMetricKind.hrvDaily,
          HealthMetricKind.rhrDaily,
        },
        limit: 100,
      );

      double totalSteps = 0;
      double totalSleepHours = 0;
      int sleepCount = 0;
      int totalWorkoutSecs = 0;
      int workoutCount = 0;
      double hrvSum = 0;
      int hrvCount = 0;
      double rhrSum = 0;
      int rhrCount = 0;

      for (final m in data[HealthMetricKind.stepsDaily] ?? const []) {
        if (m.capturedAt.isAfter(cutoff)) totalSteps += m.value;
      }
      for (final m in data[HealthMetricKind.sleepSession] ?? const []) {
        if (!m.capturedAt.isAfter(cutoff)) continue;
        totalSleepHours += switch (m.unit) {
          's' => m.value / 3600.0,
          'min' => m.value / 60.0,
          'h' => m.value,
          _ => m.value / 3600.0,
        };
        sleepCount++;
      }
      for (final m in data[HealthMetricKind.workoutSession] ?? const []) {
        if (!m.capturedAt.isAfter(cutoff)) continue;
        totalWorkoutSecs += m.value.round();
        workoutCount++;
      }
      for (final m in data[HealthMetricKind.hrvDaily] ?? const []) {
        if (!m.capturedAt.isAfter(cutoff)) continue;
        hrvSum += m.value;
        hrvCount++;
      }
      for (final m in data[HealthMetricKind.rhrDaily] ?? const []) {
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
