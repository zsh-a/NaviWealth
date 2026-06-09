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
import '../ai_tools/get_recovery_signal_tool.dart';
import '../data/providers.dart';
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
      final hrv = await repo.listByKind(
        ownerUserId: userId,
        kind: HealthMetricKind.hrvDaily,
        limit: 35,
      );
      final sleep = await repo.listByKind(
        ownerUserId: userId,
        kind: HealthMetricKind.sleepSession,
        limit: 50,
      );
      final rhr = await repo.listByKind(
        ownerUserId: userId,
        kind: HealthMetricKind.rhrDaily,
        limit: 35,
      );
      final vo2 = await repo.listByKind(
        ownerUserId: userId,
        kind: HealthMetricKind.vo2Max,
        limit: 35,
      );
      return GetRecoverySignalTool.shape(
        hrv: hrv,
        sleep: sleep,
        rhr: rhr,
        vo2Max: vo2,
        now: DateTime.now().toUtc(),
      );
    });
