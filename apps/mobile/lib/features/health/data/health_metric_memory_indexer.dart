/// Second production caller of the Memory Runtime
/// (`docs/lifeos-shell.md` §6.7, `docs/healthos-domain.md` §7, D-2.4b).
///
/// For each `health_metrics` row this indexer emits:
///
/// 1. **Always** an [EventRecord] in the cross-domain event log so
///    `ContextPack.recentEvents` can surface "user slept 6.5h on
///    2026-05-26" alongside a Finance event from the same day.
/// 2. **For notable sleep sessions only** an episodic [MemoryRecord]:
///    - Short (< 5h) or long (> 9h) → outlier nights worth recalling
///      ("I crashed for 11 hours after the trip")
///    - With a `payloadJson` note → user manually flagged the moment
///
/// HRV / steps / RHR / energy / weight / body-fat rows currently only
/// emit events. Pattern-based memories (e.g. "HRV trending down for 5
/// days") need cross-row reasoning and are deferred to the Morning
/// Briefing agent in D-2.5.
///
/// No semantic / procedural extraction yet — those need user prefs +
/// agent inference, which is also D-2.5.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'providers.dart';

/// Cross-source label so [ContextPack] can filter ("only health
/// memories") without enum'ing in core.
const String kHealthSource = 'health:health_metrics';

/// Per-kind event types. Free-form strings on the wire; constants here
/// for local consistency.
const String kEventSleepSessionEnded = 'sleep_session_ended';
const String kEventHrvRecorded = 'hrv_recorded';
const String kEventStepsRecorded = 'steps_recorded';
const String kEventRhrRecorded = 'rhr_recorded';
const String kEventActiveEnergyRecorded = 'active_energy_recorded';
const String kEventWeightRecorded = 'weight_recorded';
const String kEventBodyFatRecorded = 'body_fat_recorded';
const String kEventWorkoutCompleted = 'workout_completed';
const String kEventVo2MaxRecorded = 'vo2_max_recorded';
const String kEventDistanceWalkingRunningRecorded =
    'distance_walking_running_recorded';
const String kEventHeartRateRecorded = 'heart_rate_recorded';
const String kEventTotalEnergyRecorded = 'total_energy_recorded';
const String kEventFloorsClimbedRecorded = 'floors_climbed_recorded';
const String kEventRespiratoryRateRecorded = 'respiratory_rate_recorded';
const String kEventStressRecorded = 'stress_recorded';
const String kEventBodyBatteryRecorded = 'body_battery_recorded';
const String kEventTrainingLoadRecorded = 'training_load_recorded';
const String kEventTrainingEffectRecorded = 'training_effect_recorded';
const String kEventSpo2Recorded = 'spo2_recorded';

/// Sleep duration boundaries (hours) for an episodic memory. Outside
/// this range a session is "notable" — either deficit or recovery.
const double kSleepShortHours = 5.0;
const double kSleepLongHours = 9.0;

class HealthMetricMemoryIndexer {
  HealthMetricMemoryIndexer({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Re-index every supplied metric. Idempotent — repeated calls with
  /// the same input overwrite the same rows (events and memories are
  /// both upserted by stable id).
  ///
  /// Returns `(events, memories)` written. Rows whose [HealthMetric.kind]
  /// is [HealthMetricKind.unknown] are skipped (defensive: the AI
  /// runtime shouldn't try to summarise data it can't interpret).
  Future<({int events, int memories})> reindex(
    MemoryRuntime runtime,
    Iterable<HealthMetric> metrics, {
    required String ownerUserId,
  }) async {
    var events = 0;
    var memories = 0;
    final now = _clock();
    for (final m in metrics) {
      if (m.kind == HealthMetricKind.unknown) continue;
      await runtime.recordEvent(_eventFor(m, ownerUserId));
      events++;
      final memory = _episodicMemoryFor(m, ownerUserId, now: now);
      if (memory != null) {
        await runtime.remember(memory);
        memories++;
      }
    }
    return (events: events, memories: memories);
  }

  EventRecord _eventFor(HealthMetric metric, String ownerUserId) {
    final type = _eventType(metric.kind);
    return EventRecord(
      id: '$kHealthSource:$type:${metric.id}',
      type: type,
      timestamp: metric.capturedAt.toUtc(),
      source: kHealthSource,
      ownerUserId: ownerUserId,
      title: _eventTitle(metric),
      summary: _eventSummary(metric),
      payload: <String, Object?>{
        'kind': metric.kind.wire,
        'value': metric.value,
        'unit': metric.unit,
        if (metric.sourceDevice != null) 'source_device': metric.sourceDevice,
        if (metric.payloadJson != null) 'payload_json': metric.payloadJson,
      },
      entities: _entitiesFor(metric),
      importance: _eventImportance(metric),
    );
  }

  /// Episodic memory for "notable" sleep sessions only. HRV, RHR,
  /// steps etc. land in events but don't carry per-row reasoning —
  /// their stories are told by the Morning Briefing agent (D-2.5).
  MemoryRecord? _episodicMemoryFor(
    HealthMetric metric,
    String ownerUserId, {
    required DateTime now,
  }) {
    if (metric.kind != HealthMetricKind.sleepSession) return null;
    final hours = _secondsToHours(metric.value, metric.unit);
    final notes = metric.payloadJson?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;
    final isShort = hours < kSleepShortHours;
    final isLong = hours > kSleepLongHours;
    if (!isShort && !isLong && !hasNotes) return null;

    final shape = isShort
        ? 'short'
        : isLong
        ? 'long'
        : 'noted';
    final eventId = '$kHealthSource:${_eventType(metric.kind)}:${metric.id}';
    return MemoryRecord(
      id: '$kHealthSource:episodic:${metric.id}',
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: 'health',
      source: kHealthSource,
      sourceId: metric.id,
      sourceEventId: eventId,
      title: 'Sleep ${_round(hours)}h ($shape)',
      summary: _episodicSummary(metric, hours, shape, notes),
      payload: <String, Object?>{
        'context': _episodicContext(metric, hours, shape),
        'decision': null,
        'reasoning': hasNotes ? notes : null,
        'outcome': <String, Object?>{
          'kind': metric.kind.wire,
          'value': metric.value,
          'unit': metric.unit,
          'duration_hours': _round(hours),
          'shape': shape,
        },
      },
      entities: <String>{
        ..._entitiesFor(metric),
        if (isShort) 'short_sleep',
        if (isLong) 'long_sleep',
        if (hasNotes) 'noted_sleep',
      },
      importance: _episodicImportance(shape: shape, hasNotes: hasNotes),
      confidence: hasNotes ? 0.85 : 0.7,
      validFrom: metric.capturedAt.toUtc(),
      // No validUntil — historical sleep stays valid forever as context.
      createdAt: now,
      updatedAt: now,
    );
  }

  String _eventType(HealthMetricKind kind) => switch (kind) {
    HealthMetricKind.sleepSession => kEventSleepSessionEnded,
    HealthMetricKind.hrvDaily => kEventHrvRecorded,
    HealthMetricKind.stepsDaily => kEventStepsRecorded,
    HealthMetricKind.rhrDaily => kEventRhrRecorded,
    HealthMetricKind.activeEnergyDaily => kEventActiveEnergyRecorded,
    HealthMetricKind.weight => kEventWeightRecorded,
    HealthMetricKind.bodyFat => kEventBodyFatRecorded,
    HealthMetricKind.workoutSession => kEventWorkoutCompleted,
    HealthMetricKind.vo2Max => kEventVo2MaxRecorded,
    HealthMetricKind.distanceWalkingRunningDaily =>
      kEventDistanceWalkingRunningRecorded,
    HealthMetricKind.heartRateDaily => kEventHeartRateRecorded,
    HealthMetricKind.totalEnergyDaily => kEventTotalEnergyRecorded,
    HealthMetricKind.floorsClimbedDaily => kEventFloorsClimbedRecorded,
    HealthMetricKind.respiratoryRateDaily => kEventRespiratoryRateRecorded,
    HealthMetricKind.stressDaily => kEventStressRecorded,
    HealthMetricKind.bodyBatteryDaily => kEventBodyBatteryRecorded,
    HealthMetricKind.trainingLoadDaily => kEventTrainingLoadRecorded,
    HealthMetricKind.trainingEffectDaily => kEventTrainingEffectRecorded,
    HealthMetricKind.spo2Daily => kEventSpo2Recorded,
    HealthMetricKind.unknown => 'health_unknown',
  };

  String _eventTitle(HealthMetric metric) {
    final whenIso = metric.capturedAt.toUtc().toIso8601String().substring(
      0,
      10,
    );
    return switch (metric.kind) {
      HealthMetricKind.sleepSession =>
        'Sleep ${_round(_secondsToHours(metric.value, metric.unit))}h · $whenIso',
      HealthMetricKind.hrvDaily =>
        'HRV ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.stepsDaily => 'Steps ${metric.value.round()} · $whenIso',
      HealthMetricKind.rhrDaily =>
        'RHR ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.activeEnergyDaily =>
        'Active ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.weight =>
        'Weight ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.bodyFat =>
        'Body fat ${_round(metric.value * 100)}% · $whenIso',
      HealthMetricKind.workoutSession =>
        'Workout ${_round(_secondsToHours(metric.value, metric.unit))}h · $whenIso',
      HealthMetricKind.vo2Max =>
        'VO₂max ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.distanceWalkingRunningDaily =>
        'Walk/run ${_round(metric.value / 1000.0)} km · $whenIso',
      HealthMetricKind.heartRateDaily =>
        'Heart rate ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.totalEnergyDaily =>
        'Total energy ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.floorsClimbedDaily =>
        'Floors ${_round(metric.value)} · $whenIso',
      HealthMetricKind.respiratoryRateDaily =>
        'Respiration ${_round(metric.value)} ${metric.unit} · $whenIso',
      HealthMetricKind.stressDaily =>
        'Stress ${_round(metric.value)} · $whenIso',
      HealthMetricKind.bodyBatteryDaily =>
        'Body Battery ${metric.value.round()} · $whenIso',
      HealthMetricKind.trainingLoadDaily =>
        'Training load ${_round(metric.value)} · $whenIso',
      HealthMetricKind.trainingEffectDaily =>
        'Training effect ${_round(metric.value)} · $whenIso',
      HealthMetricKind.spo2Daily =>
        'SpO2 ${_round(metric.value)}% · $whenIso',
      HealthMetricKind.unknown => 'Health row · $whenIso',
    };
  }

  String _eventSummary(HealthMetric metric) {
    final whenIso = metric.capturedAt.toUtc().toIso8601String();
    return switch (metric.kind) {
      HealthMetricKind.sleepSession =>
        'Slept ${_round(_secondsToHours(metric.value, metric.unit))}h starting $whenIso.',
      HealthMetricKind.hrvDaily =>
        'HRV ${_round(metric.value)} ${metric.unit} on $whenIso.',
      HealthMetricKind.stepsDaily =>
        'Took ${metric.value.round()} steps on $whenIso.',
      HealthMetricKind.rhrDaily =>
        'Resting heart rate ${_round(metric.value)} ${metric.unit} on $whenIso.',
      HealthMetricKind.activeEnergyDaily =>
        'Burned ${_round(metric.value)} ${metric.unit} (active) on $whenIso.',
      HealthMetricKind.weight =>
        'Weight ${_round(metric.value)} ${metric.unit} on $whenIso.',
      HealthMetricKind.bodyFat =>
        'Body fat ${_round(metric.value * 100)}% on $whenIso.',
      HealthMetricKind.workoutSession =>
        'Workout lasting ${_round(_secondsToHours(metric.value, metric.unit))}h starting $whenIso.',
      HealthMetricKind.vo2Max =>
        'VO₂max ${_round(metric.value)} ${metric.unit} on $whenIso.',
      HealthMetricKind.distanceWalkingRunningDaily =>
        'Walked/ran ${_round(metric.value / 1000.0)} km on $whenIso.',
      HealthMetricKind.heartRateDaily =>
        'Average heart rate ${_round(metric.value)} ${metric.unit} on $whenIso.',
      HealthMetricKind.totalEnergyDaily =>
        'Burned ${_round(metric.value)} ${metric.unit} total on $whenIso.',
      HealthMetricKind.floorsClimbedDaily =>
        'Climbed ${_round(metric.value)} floors on $whenIso.',
      HealthMetricKind.respiratoryRateDaily =>
        'Respiratory rate ${_round(metric.value)} ${metric.unit} on $whenIso.',
      HealthMetricKind.stressDaily =>
        'Stress level ${_round(metric.value)} on $whenIso.',
      HealthMetricKind.bodyBatteryDaily =>
        'Body Battery max ${metric.value.round()} on $whenIso.',
      HealthMetricKind.trainingLoadDaily =>
        'Training load ${_round(metric.value)} on $whenIso.',
      HealthMetricKind.trainingEffectDaily =>
        'Training effect ${_round(metric.value)} on $whenIso.',
      HealthMetricKind.spo2Daily =>
        'SpO2 ${_round(metric.value)}% on $whenIso.',
      HealthMetricKind.unknown => 'Health metric on $whenIso.',
    };
  }

  String _episodicContext(HealthMetric metric, double hours, String shape) =>
      'Sleep session ${metric.capturedAt.toUtc().toIso8601String()} '
      'lasting ${_round(hours)}h ($shape).';

  String _episodicSummary(
    HealthMetric metric,
    double hours,
    String shape,
    String? notes,
  ) {
    final whenIso = metric.capturedAt.toUtc().toIso8601String();
    final base =
        'Sleep session $whenIso lasted ${_round(hours)}h — flagged as $shape.';
    if (notes != null && notes.isNotEmpty) {
      return '$base Notes: $notes';
    }
    return base;
  }

  Set<String> _entitiesFor(HealthMetric metric) => <String>{
    'health',
    metric.kind.wire,
    if (metric.sourceDevice != null) metric.sourceDevice!,
  };

  double _eventImportance(HealthMetric metric) {
    switch (metric.kind) {
      case HealthMetricKind.sleepSession:
        final hours = _secondsToHours(metric.value, metric.unit);
        if (hours < kSleepShortHours || hours > kSleepLongHours) return 0.7;
        return 0.5;
      case HealthMetricKind.hrvDaily:
      case HealthMetricKind.rhrDaily:
        return 0.55;
      case HealthMetricKind.stepsDaily:
      case HealthMetricKind.activeEnergyDaily:
      case HealthMetricKind.distanceWalkingRunningDaily:
        return 0.45;
      case HealthMetricKind.weight:
      case HealthMetricKind.bodyFat:
        return 0.5;
      case HealthMetricKind.workoutSession:
        // Long sessions (>60min) or high-kcal sessions get a small
        // bump; the rest sit at the activity baseline. Reading the
        // payload here would couple the indexer to wire-format strings,
        // so we just lean on duration as the signal.
        final hours = _secondsToHours(metric.value, metric.unit);
        return hours > 1.0 ? 0.6 : 0.5;
      case HealthMetricKind.vo2Max:
      case HealthMetricKind.heartRateDaily:
      case HealthMetricKind.respiratoryRateDaily:
        return 0.55;
      case HealthMetricKind.totalEnergyDaily:
      case HealthMetricKind.floorsClimbedDaily:
        return 0.45;
      case HealthMetricKind.stressDaily:
        return 0.55;
      case HealthMetricKind.bodyBatteryDaily:
        return 0.55;
      case HealthMetricKind.trainingLoadDaily:
      case HealthMetricKind.trainingEffectDaily:
      case HealthMetricKind.spo2Daily:
        return 0.55;
      case HealthMetricKind.unknown:
        return 0.4;
    }
  }

  double _episodicImportance({required String shape, required bool hasNotes}) {
    var imp = switch (shape) {
      'short' => 0.7, // Deficit nights matter for "why was I off"
      'long' => 0.6,
      'noted' => 0.65,
      _ => 0.5,
    };
    if (hasNotes) imp += 0.05;
    return imp.clamp(0.0, 0.95);
  }

  static double _secondsToHours(double value, String unit) {
    return switch (unit) {
      's' => value / 3600.0,
      'min' => value / 60.0,
      'h' => value,
      _ => value / 3600.0,
    };
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}

/// Provider that wires the indexer to the sleep + HRV streams. Gated
/// on `domainOptInsProvider`: when Health is OFF the indexer is built
/// but doesn't subscribe — first-time installs spend zero work.
final healthMetricMemoryIndexerProvider = Provider<HealthMetricMemoryIndexer>((
  ref,
) {
  final indexer = HealthMetricMemoryIndexer();

  Future<void> reindexNow(List<HealthMetric> metrics) async {
    final runtime = await ref.read(memoryRuntimeProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    await indexer.reindex(runtime, metrics, ownerUserId: userId);
  }

  () async {
    final resolved = await ref.read(core_auth.domainOptInsProvider.future);
    if (!resolved.contains(DomainScope.health)) {
      // Health domain OFF — don't subscribe to any streams. The
      // provider stays inert until the user opts in and the bootstrap
      // re-reads it.
      return;
    }
    final repo = await ref.read(healthMetricRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();

    Future<void> queue = Future<void>.value();
    void subscribe(HealthMetricKind kind, int limit) {
      final sub = repo
          .watchRecent(ownerUserId: userId, kind: kind, limit: limit)
          .listen((metrics) {
            queue = queue.then((_) => reindexNow(metrics));
            // ignore: discarded_futures
            queue;
          });
      ref.onDispose(sub.cancel);
    }

    for (final kind in HealthMetricKind.values) {
      if (kind == HealthMetricKind.unknown) continue;
      subscribe(kind, _indexerLimitFor(kind));
    }
  }();

  return indexer;
});

int _indexerLimitFor(HealthMetricKind kind) => switch (kind) {
  HealthMetricKind.sleepSession => 60,
  HealthMetricKind.hrvDaily ||
  HealthMetricKind.rhrDaily ||
  HealthMetricKind.heartRateDaily ||
  HealthMetricKind.respiratoryRateDaily ||
  HealthMetricKind.vo2Max ||
  HealthMetricKind.stressDaily ||
  HealthMetricKind.bodyBatteryDaily => 90,
  HealthMetricKind.workoutSession => 150,
  _ => 120,
};
