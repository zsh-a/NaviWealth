part of 'health_metric_memory_indexer.dart';

const int kHealthTrendMinimumRows = 3;

mixin _HealthMetricTrendMemoryBuilder on _HealthMetricMemoryFormatting {
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
      role: MemoryRole.pattern,
      authority: EvidenceAuthority.deterministicDerived,
      provenance: EvidenceProvenance(
        source: kHealthSource,
        sourceId: 'trend:${trend.kind.wire}',
        algorithmVersion: 'health_trend_v1',
        observedAt: trend.to,
      ),
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
      role: MemoryRole.guidance,
      authority: EvidenceAuthority.deterministicDerived,
      provenance: EvidenceProvenance(
        source: kHealthSource,
        sourceId: 'trend:${trend.kind.wire}',
        algorithmVersion: 'health_trend_v1',
        observedAt: trend.to,
      ),
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

  bool _supportsTrendMemory(HealthMetricKind kind) => switch (kind) {
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

  double _trendValue(HealthMetric metric) => switch (metric.kind) {
    HealthMetricKind.sleepSession => _secondsToHours(metric.value, metric.unit),
    HealthMetricKind.bodyFat => metric.value * 100,
    HealthMetricKind.distanceWalkingRunningDaily => metric.value / 1000.0,
    _ => metric.value,
  };

  double _trendThreshold(HealthMetricKind kind, double baseline) {
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

  bool _isAdverseTrend(_HealthTrend trend) => switch (trend.kind) {
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

  _TrendAdvice? _proceduralAdviceFor(_HealthTrend trend) {
    final label = _trendKindLabel(trend.kind);
    final unit = _trendUnit(trend.kind);
    final latest = _formatTrendValue(trend.latestValue, unit);
    return switch (trend.kind) {
      HealthMetricKind.sleepSession when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: protect sleep before load',
        rule: 'When recent sleep is short or falling, bias HealthOS plans toward recovery before high-intensity work.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action: 'Recommend lighter training, earlier wind-down, and avoid stacking intense workouts until sleep normalizes.',
      ),
      HealthMetricKind.hrvDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: treat falling HRV as recovery risk',
        rule: 'When HRV trends down, reduce planned intensity unless the user explicitly overrides.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action: 'Prefer mobility, zone-2, or rest recommendations and explain the HRV context.',
      ),
      HealthMetricKind.rhrDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: treat rising RHR as recovery risk',
        rule: 'When resting heart rate trends up, avoid aggressive workload recommendations.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action: 'Suggest conservative recovery actions and mention RHR as a caution signal.',
      ),
      HealthMetricKind.stressDaily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: de-load on elevated stress',
        rule: 'When stress is elevated or rising, prioritize recovery blocks in the plan.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action: 'Recommend rest, breathing, or easy movement before strenuous sessions.',
      ),
      HealthMetricKind.bodyBatteryDaily when _isAdverseTrend(trend) =>
        _TrendAdvice(
          title: 'Health rule: low Body Battery limits workload',
          rule: 'When Body Battery is low or falling, cap workout ambition for the next plan.',
          conditions:
              '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
          action: 'Prefer low-intensity activity or full rest and revisit after recovery improves.',
        ),
      HealthMetricKind.spo2Daily when _isAdverseTrend(trend) => _TrendAdvice(
        title: 'Health rule: low SpO2 needs caution',
        rule: 'When SpO2 trends down or falls below normal, avoid hard training recommendations.',
        conditions:
            '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
        action: 'Suggest rest and advise the user to treat persistent low readings as a medical follow-up signal.',
      ),
      HealthMetricKind.trainingLoadDaily when _isAdverseTrend(trend) =>
        _TrendAdvice(
          title: 'Health rule: rising load needs recovery budget',
          rule: 'When training load is already high and rising, leave recovery budget before adding work.',
          conditions:
              '$label ${trend.direction.wire}, latest $latest, recent average ${_formatTrendValue(trend.recentAverage, unit)}.',
          action: 'Avoid compounding load; recommend deload or easy sessions unless recovery metrics are strong.',
        ),
      _ => null,
    };
  }

  String _trendKindLabel(HealthMetricKind kind) => switch (kind) {
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

  String _trendUnit(HealthMetricKind kind) => switch (kind) {
    HealthMetricKind.sleepSession => 'h',
    HealthMetricKind.bodyFat => '%',
    HealthMetricKind.distanceWalkingRunningDaily => 'km',
    _ => kind.defaultUnit,
  };

  String _formatTrendValue(double value, String unit) {
    final rounded = _round(value);
    final text = rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toString();
    return unit.isEmpty ? text : '$text $unit';
  }
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
