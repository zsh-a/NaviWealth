part of 'health_metric_memory_indexer.dart';

/// Per-kind event types. Free-form strings on the wire; constants here
/// keep local producers consistent.
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

/// Sleep duration boundaries (hours) for an episodic memory. Outside this
/// range a session is "notable": either deficit or recovery.
const double kSleepShortHours = 5.0;
const double kSleepLongHours = 9.0;

mixin _HealthMetricEventMapper on _HealthMetricMemoryFormatting {
  EventRecord _eventFor(
    HealthMetric metric,
    String ownerUserId, {
    required DateTime observedAt,
  }) {
    final type = _eventType(metric.kind);
    return EventRecord(
      id: '$kHealthSource:$type:${metric.id}',
      domain: DomainScope.health,
      kind: EventKind.domain(DomainScope.health, type),
      occurredAt: metric.capturedAt.toUtc(),
      observedAt: observedAt.toUtc(),
      sourceIdentity: SourceIdentity(
        domain: DomainScope.health,
        rowFamily: kHealthSource,
        rowId: metric.id,
        fingerprint: metric.sync.hlc.toString(),
      ),
      ownerUserId: ownerUserId,
      title: _eventTitle(metric),
      summary: _eventSummary(metric),
      facts: <String, Object?>{
        'kind': metric.kind.wire,
        'value': metric.value,
        'unit': metric.unit,
        if (metric.sourceDevice != null) 'source_device': metric.sourceDevice,
        if (metric.payloadJson != null) 'payload_json': metric.payloadJson,
      },
      entities: _entitiesFor(metric),
      importance: _eventImportance(metric),
      confidence: 1,
    );
  }

  /// Episodic memory for notable sleep sessions only. HRV, RHR, steps, etc.
  /// land in events but do not carry per-row reasoning.
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
      role: MemoryRole.episode,
      authority: EvidenceAuthority.sourceFact,
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
        'Sleep ${_round(_secondsToHours(metric.value, metric.unit))}h \u00b7 $whenIso',
      HealthMetricKind.hrvDaily =>
        'HRV ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.stepsDaily =>
        'Steps ${metric.value.round()} \u00b7 $whenIso',
      HealthMetricKind.rhrDaily =>
        'RHR ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.activeEnergyDaily =>
        'Active ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.weight =>
        'Weight ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.bodyFat =>
        'Body fat ${_round(metric.value * 100)}% \u00b7 $whenIso',
      HealthMetricKind.workoutSession =>
        'Workout ${_round(_secondsToHours(metric.value, metric.unit))}h \u00b7 $whenIso',
      HealthMetricKind.vo2Max =>
        'VO\u2082max ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.distanceWalkingRunningDaily =>
        'Walk/run ${_round(metric.value / 1000.0)} km \u00b7 $whenIso',
      HealthMetricKind.heartRateDaily =>
        'Heart rate ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.totalEnergyDaily =>
        'Total energy ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.floorsClimbedDaily =>
        'Floors ${_round(metric.value)} \u00b7 $whenIso',
      HealthMetricKind.respiratoryRateDaily =>
        'Respiration ${_round(metric.value)} ${metric.unit} \u00b7 $whenIso',
      HealthMetricKind.stressDaily =>
        'Stress ${_round(metric.value)} \u00b7 $whenIso',
      HealthMetricKind.bodyBatteryDaily =>
        'Body Battery ${metric.value.round()} \u00b7 $whenIso',
      HealthMetricKind.trainingLoadDaily =>
        'Training load ${_round(metric.value)} \u00b7 $whenIso',
      HealthMetricKind.trainingEffectDaily =>
        'Training effect ${_round(metric.value)} \u00b7 $whenIso',
      HealthMetricKind.spo2Daily =>
        'SpO2 ${_round(metric.value)}% \u00b7 $whenIso',
      HealthMetricKind.unknown => 'Health row \u00b7 $whenIso',
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
        'VO\u2082max ${_round(metric.value)} ${metric.unit} on $whenIso.',
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
        'Sleep session $whenIso lasted ${_round(hours)}h \u2014 flagged as $shape.';
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
      'short' => 0.7,
      'long' => 0.6,
      'noted' => 0.65,
      _ => 0.5,
    };
    if (hasNotes) imp += 0.05;
    return imp.clamp(0.0, 0.95);
  }
}
