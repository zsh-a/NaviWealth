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
/// 3. **For metric batches with enough history** semantic trend memories
///    and, when the signal should affect planning, procedural rules.
///    These are deterministic summaries of already-synced rows; agents
///    can still refine them later with preference-aware inference.
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
const int kHealthTrendMinimumRows = 3;

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
    final rows = metrics
        .where((m) => m.kind != HealthMetricKind.unknown)
        .toList(growable: false);
    for (final m in rows) {
      if (m.kind == HealthMetricKind.unknown) continue;
      await runtime.recordEvent(_eventFor(m, ownerUserId));
      events++;
      final memory = _episodicMemoryFor(m, ownerUserId, now: now);
      if (memory != null) {
        await runtime.remember(memory);
        memories++;
      }
    }
    for (final memory in _trendMemoriesFor(rows, ownerUserId, now: now)) {
      await runtime.remember(memory);
      memories++;
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

  List<MemoryRecord> _trendMemoriesFor(
    List<HealthMetric> rows,
    String ownerUserId, {
    required DateTime now,
  }) {
    final grouped = <HealthMetricKind, List<HealthMetric>>{};
    for (final row in rows) {
      if (!_supportsTrendMemory(row.kind)) continue;
      grouped.putIfAbsent(row.kind, () => <HealthMetric>[]).add(row);
    }

    final out = <MemoryRecord>[];
    for (final entry in grouped.entries) {
      final trend = _trendFor(entry.key, entry.value);
      if (trend == null) continue;
      out.add(_semanticTrendMemory(trend, ownerUserId, now: now));
      final procedural = _proceduralTrendMemory(trend, ownerUserId, now: now);
      if (procedural != null) out.add(procedural);
    }
    return out;
  }

  _HealthTrend? _trendFor(HealthMetricKind kind, List<HealthMetric> rows) {
    if (rows.length < kHealthTrendMinimumRows) return null;
    final ordered = rows.toList(growable: false)
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final split = (ordered.length / 2).floor().clamp(1, ordered.length - 1);
    final older = ordered.take(split).toList(growable: false);
    final recent = ordered.skip(split).toList(growable: false);
    final olderAvg = _average(older.map(_trendValue));
    final recentAvg = _average(recent.map(_trendValue));
    final latest = _trendValue(ordered.last);
    final delta = recentAvg - olderAvg;
    final threshold = _trendThreshold(kind, olderAvg);
    final direction = delta.abs() < threshold
        ? _TrendDirection.stable
        : delta > 0
        ? _TrendDirection.increasing
        : _TrendDirection.decreasing;
    return _HealthTrend(
      kind: kind,
      from: ordered.first.capturedAt.toUtc(),
      to: ordered.last.capturedAt.toUtc(),
      sampleCount: ordered.length,
      olderAverage: olderAvg,
      recentAverage: recentAvg,
      latestValue: latest,
      direction: direction,
    );
  }

  MemoryRecord _semanticTrendMemory(
    _HealthTrend trend,
    String ownerUserId, {
    required DateTime now,
  }) {
    final label = _trendKindLabel(trend.kind);
    final unit = _trendUnit(trend.kind);
    final direction = trend.direction.wire;
    final statement =
        'Recent $label is $direction: latest ${_formatTrendValue(trend.latestValue, unit)}, '
        'recent average ${_formatTrendValue(trend.recentAverage, unit)} '
        'vs earlier ${_formatTrendValue(trend.olderAverage, unit)} '
        'across ${trend.sampleCount} rows.';
    return MemoryRecord(
      id: '$kHealthSource:semantic:trend:${trend.kind.wire}',
      kind: MemoryKind.semantic,
      ownerUserId: ownerUserId,
      scope: 'health',
      source: kHealthSource,
      sourceId: 'trend:${trend.kind.wire}',
      title: 'Health trend: $label $direction',
      summary: statement,
      payload: <String, Object?>{
        'statement': statement,
        'scope': 'health',
        'kind': trend.kind.wire,
        'trend': direction,
        'sample_count': trend.sampleCount,
        'latest_value': _round(trend.latestValue),
        'recent_average': _round(trend.recentAverage),
        'older_average': _round(trend.olderAverage),
        'unit': unit,
        'from': trend.from.toIso8601String(),
        'to': trend.to.toIso8601String(),
      },
      entities: <String>{
        'health',
        'health_trend',
        trend.kind.wire,
        'trend:$direction',
        if (_isAdverseTrend(trend)) 'recovery_risk',
      },
      importance: _isAdverseTrend(trend) ? 0.74 : 0.6,
      confidence: 0.72,
      validFrom: trend.from,
      createdAt: now,
      updatedAt: now,
    );
  }

  MemoryRecord? _proceduralTrendMemory(
    _HealthTrend trend,
    String ownerUserId, {
    required DateTime now,
  }) {
    final advice = _proceduralAdviceFor(trend);
    if (advice == null) return null;
    return MemoryRecord(
      id: '$kHealthSource:procedural:trend:${trend.kind.wire}',
      kind: MemoryKind.procedural,
      ownerUserId: ownerUserId,
      scope: 'health',
      source: kHealthSource,
      sourceId: 'trend:${trend.kind.wire}',
      title: advice.title,
      summary: advice.rule,
      payload: <String, Object?>{
        'rule': advice.rule,
        'scope': 'health',
        'conditions': advice.conditions,
        'action': advice.action,
        'kind': trend.kind.wire,
        'trend': trend.direction.wire,
        'latest_value': _round(trend.latestValue),
        'recent_average': _round(trend.recentAverage),
      },
      entities: <String>{
        'health',
        'health_rule',
        'recovery_planning',
        'workout_planning',
        trend.kind.wire,
      },
      importance: 0.78,
      confidence: 0.68,
      validFrom: trend.from,
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
      HealthMetricKind.spo2Daily => 'SpO2 ${_round(metric.value)}% · $whenIso',
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

  static bool _supportsTrendMemory(HealthMetricKind kind) => switch (kind) {
    HealthMetricKind.sleepSession ||
    HealthMetricKind.hrvDaily ||
    HealthMetricKind.stepsDaily ||
    HealthMetricKind.rhrDaily ||
    HealthMetricKind.activeEnergyDaily ||
    HealthMetricKind.weight ||
    HealthMetricKind.bodyFat ||
    HealthMetricKind.vo2Max ||
    HealthMetricKind.distanceWalkingRunningDaily ||
    HealthMetricKind.heartRateDaily ||
    HealthMetricKind.totalEnergyDaily ||
    HealthMetricKind.floorsClimbedDaily ||
    HealthMetricKind.respiratoryRateDaily ||
    HealthMetricKind.stressDaily ||
    HealthMetricKind.bodyBatteryDaily ||
    HealthMetricKind.trainingLoadDaily ||
    HealthMetricKind.trainingEffectDaily ||
    HealthMetricKind.spo2Daily => true,
    HealthMetricKind.workoutSession || HealthMetricKind.unknown => false,
  };

  static double _trendValue(HealthMetric metric) => switch (metric.kind) {
    HealthMetricKind.sleepSession => _secondsToHours(metric.value, metric.unit),
    HealthMetricKind.bodyFat => metric.value * 100,
    HealthMetricKind.distanceWalkingRunningDaily => metric.value / 1000.0,
    _ => metric.value,
  };

  static double _trendThreshold(HealthMetricKind kind, double baseline) {
    final relative = baseline.abs() * 0.06;
    final absolute = switch (kind) {
      HealthMetricKind.sleepSession => 0.3,
      HealthMetricKind.hrvDaily => 3.0,
      HealthMetricKind.rhrDaily => 3.0,
      HealthMetricKind.stepsDaily => 1000.0,
      HealthMetricKind.activeEnergyDaily ||
      HealthMetricKind.totalEnergyDaily => 80.0,
      HealthMetricKind.weight => 0.5,
      HealthMetricKind.bodyFat => 0.5,
      HealthMetricKind.vo2Max => 0.8,
      HealthMetricKind.distanceWalkingRunningDaily => 0.8,
      HealthMetricKind.heartRateDaily => 3.0,
      HealthMetricKind.floorsClimbedDaily => 3.0,
      HealthMetricKind.respiratoryRateDaily => 1.0,
      HealthMetricKind.stressDaily => 5.0,
      HealthMetricKind.bodyBatteryDaily => 8.0,
      HealthMetricKind.trainingLoadDaily => 10.0,
      HealthMetricKind.trainingEffectDaily => 0.4,
      HealthMetricKind.spo2Daily => 1.0,
      _ => 1.0,
    };
    return relative > absolute ? relative : absolute;
  }

  static bool _isAdverseTrend(_HealthTrend trend) => switch (trend.kind) {
    HealthMetricKind.sleepSession =>
      trend.recentAverage < 6.0 ||
          (trend.direction == _TrendDirection.decreasing &&
              trend.latestValue < 7.0),
    HealthMetricKind.hrvDaily => trend.direction == _TrendDirection.decreasing,
    HealthMetricKind.rhrDaily => trend.direction == _TrendDirection.increasing,
    HealthMetricKind.stressDaily =>
      trend.direction == _TrendDirection.increasing || trend.latestValue >= 65,
    HealthMetricKind.bodyBatteryDaily =>
      trend.direction == _TrendDirection.decreasing || trend.latestValue < 45,
    HealthMetricKind.spo2Daily =>
      trend.direction == _TrendDirection.decreasing || trend.latestValue < 94,
    HealthMetricKind.trainingLoadDaily =>
      trend.direction == _TrendDirection.increasing && trend.latestValue > 100,
    _ => false,
  };

  static _TrendAdvice? _proceduralAdviceFor(_HealthTrend trend) {
    final label = _trendKindLabel(trend.kind);
    final unit = _trendUnit(trend.kind);
    final latest = _formatTrendValue(trend.latestValue, unit);
    return switch (trend.kind) {
      HealthMetricKind.sleepSession when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: protect sleep before load',
        rule:
            'When recent sleep is short or falling, bias HealthOS plans toward recovery before high-intensity work.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action:
            'Recommend lighter training, earlier wind-down, and avoid stacking intense workouts until sleep normalizes.',
      ),
      HealthMetricKind.hrvDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: treat falling HRV as recovery risk',
        rule:
            'When HRV trends down, reduce planned intensity unless the user explicitly overrides.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action:
            'Prefer mobility, zone-2, or rest recommendations and explain the HRV context.',
      ),
      HealthMetricKind.rhrDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: treat rising RHR as recovery risk',
        rule:
            'When resting heart rate trends up, avoid aggressive workload recommendations.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action:
            'Suggest conservative recovery actions and mention RHR as a caution signal.',
      ),
      HealthMetricKind.stressDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: de-load on elevated stress',
        rule:
            'When stress is elevated or rising, prioritize recovery blocks in the plan.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action:
            'Recommend rest, breathing, or easy movement before strenuous sessions.',
      ),
      HealthMetricKind.bodyBatteryDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: low Body Battery limits workload',
        rule:
            'When Body Battery is low or falling, cap workout ambition for the next plan.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action:
            'Prefer low-intensity activity or full rest and revisit after recovery improves.',
      ),
      HealthMetricKind.spo2Daily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: low SpO2 needs caution',
        rule:
            'When SpO2 trends down or falls below normal, avoid hard training recommendations.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action:
            'Suggest rest and advise the user to treat persistent low readings as a medical follow-up signal.',
      ),
      HealthMetricKind.trainingLoadDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: rising load needs recovery budget',
        rule:
            'When training load is already high and rising, leave recovery budget before adding work.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action:
            'Avoid compounding load; recommend deload or easy sessions unless recovery metrics are strong.',
      ),
      _ => null,
    };
  }

  static String _trendKindLabel(HealthMetricKind kind) => switch (kind) {
    HealthMetricKind.sleepSession => 'sleep duration',
    HealthMetricKind.hrvDaily => 'HRV',
    HealthMetricKind.stepsDaily => 'steps',
    HealthMetricKind.rhrDaily => 'resting heart rate',
    HealthMetricKind.activeEnergyDaily => 'active energy',
    HealthMetricKind.weight => 'weight',
    HealthMetricKind.bodyFat => 'body fat',
    HealthMetricKind.vo2Max => 'VO2 max',
    HealthMetricKind.distanceWalkingRunningDaily => 'walking/running distance',
    HealthMetricKind.heartRateDaily => 'heart rate',
    HealthMetricKind.totalEnergyDaily => 'total energy',
    HealthMetricKind.floorsClimbedDaily => 'floors climbed',
    HealthMetricKind.respiratoryRateDaily => 'respiratory rate',
    HealthMetricKind.stressDaily => 'stress',
    HealthMetricKind.bodyBatteryDaily => 'Body Battery',
    HealthMetricKind.trainingLoadDaily => 'training load',
    HealthMetricKind.trainingEffectDaily => 'training effect',
    HealthMetricKind.spo2Daily => 'SpO2',
    HealthMetricKind.workoutSession => 'workout duration',
    HealthMetricKind.unknown => 'health metric',
  };

  static String _trendUnit(HealthMetricKind kind) => switch (kind) {
    HealthMetricKind.sleepSession => 'h',
    HealthMetricKind.bodyFat => '%',
    HealthMetricKind.distanceWalkingRunningDaily => 'km',
    _ => kind.defaultUnit,
  };

  static String _formatTrendValue(double value, String unit) {
    final rounded = _round(value);
    final text = rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toString();
    return unit.isEmpty ? text : '$text $unit';
  }

  static double _average(Iterable<double> values) {
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      sum += value;
      count++;
    }
    return count == 0 ? 0.0 : sum / count;
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

enum _TrendDirection {
  increasing('increasing'),
  decreasing('decreasing'),
  stable('stable');

  const _TrendDirection(this.wire);
  final String wire;
}

class _HealthTrend {
  const _HealthTrend({
    required this.kind,
    required this.from,
    required this.to,
    required this.sampleCount,
    required this.olderAverage,
    required this.recentAverage,
    required this.latestValue,
    required this.direction,
  });

  final HealthMetricKind kind;
  final DateTime from;
  final DateTime to;
  final int sampleCount;
  final double olderAverage;
  final double recentAverage;
  final double latestValue;
  final _TrendDirection direction;
}

class _TrendAdvice {
  const _TrendAdvice({
    required this.title,
    required this.rule,
    required this.conditions,
    required this.action,
  });

  final String title;
  final String rule;
  final String conditions;
  final String action;
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
