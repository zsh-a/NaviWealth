part of 'health_platform_adapter_io.dart';

RawSleepSession? _sleepFrom(HealthDataPoint p, String platformPrefix) {
  final duration = p.dateTo.difference(p.dateFrom);
  if (duration <= Duration.zero) return null;
  return RawSleepSession(
    externalId: '$platformPrefix:sleep:${p.uuid}',
    startedAt: p.dateFrom.toUtc(),
    duration: duration,
    sourceDevice: _sourceLabel(p),
  );
}

RawSleepStageSegment? _sleepStageSegmentFrom(
  HealthDataPoint p,
  String platformPrefix,
) {
  final stage = _sleepStageLabel(p.type);
  if (stage == null) return null;
  final duration = p.dateTo.difference(p.dateFrom);
  if (duration <= Duration.zero) return null;
  return RawSleepStageSegment(
    externalId: '$platformPrefix:sleep_stage:${p.uuid}',
    startedAt: p.dateFrom.toUtc(),
    duration: duration,
    stage: stage,
    sourceDevice: _sourceLabel(p),
  );
}

List<RawSleepSession> _attachSleepStageHistograms(
  List<RawSleepSession> sessions,
  List<HealthDataPoint> points,
) {
  if (sessions.isEmpty) return sessions;
  final stagePoints = points
      .where((p) => _sleepStageLabel(p.type) != null)
      .toList(growable: false);
  if (stagePoints.isEmpty) return sessions;

  return sessions
      .map((s) {
        final start = s.startedAt.toUtc();
        final end = start.add(s.duration);
        final secondsByStage = <String, int>{};
        for (final p in stagePoints) {
          final label = _sleepStageLabel(p.type);
          if (label == null) continue;
          final from = _maxInstant(start, p.dateFrom.toUtc());
          final to = _minInstant(end, p.dateTo.toUtc());
          if (!to.isAfter(from)) continue;
          secondsByStage.update(
            label,
            (v) => v + to.difference(from).inSeconds,
            ifAbsent: () => to.difference(from).inSeconds,
          );
        }
        if (secondsByStage.isEmpty) return s;
        final ordered = <String, int>{
          for (final key in const <String>[
            'light',
            'deep',
            'rem',
            'awake',
            'unknown',
          ])
            if ((secondsByStage[key] ?? 0) > 0) key: secondsByStage[key]!,
        };
        return RawSleepSession(
          externalId: s.externalId,
          startedAt: s.startedAt,
          duration: s.duration,
          sourceDevice: s.sourceDevice,
          stageHistogramJson: jsonEncode(ordered),
        );
      })
      .toList(growable: false);
}

String? _sleepStageLabel(HealthDataType type) => switch (type) {
  HealthDataType.SLEEP_ASLEEP => 'asleep',
  HealthDataType.SLEEP_LIGHT => 'light',
  HealthDataType.SLEEP_DEEP => 'deep',
  HealthDataType.SLEEP_REM => 'rem',
  HealthDataType.SLEEP_AWAKE || HealthDataType.SLEEP_AWAKE_IN_BED => 'awake',
  HealthDataType.SLEEP_UNKNOWN => 'unknown',
  _ => null,
};
