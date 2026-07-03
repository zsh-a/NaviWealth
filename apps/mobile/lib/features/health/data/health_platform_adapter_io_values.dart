part of 'health_platform_adapter_io.dart';

RawWorkoutSession? _workoutFrom(HealthDataPoint p, String platformPrefix) {
  final v = p.value;
  if (v is! WorkoutHealthValue) return null;
  final duration = p.dateTo.difference(p.dateFrom);
  if (duration <= Duration.zero) return null;

  final energy = v.totalEnergyBurned;
  double? energyKcal;
  if (energy != null) {
    final eUnit = v.totalEnergyBurnedUnit;
    // package:health emits KILOCALORIE by default for HK workouts;
    // guard against JOULE just in case the platform-specific path
    // changes.
    energyKcal = switch (eUnit) {
      HealthDataUnit.JOULE => energy / 4184.0,
      _ => energy.toDouble(),
    };
  }

  final distance = v.totalDistance;
  double? distanceMeters;
  if (distance != null) {
    final dUnit = v.totalDistanceUnit;
    distanceMeters = switch (dUnit) {
      HealthDataUnit.MILE => distance * 1609.344,
      HealthDataUnit.FOOT => distance * 0.3048,
      HealthDataUnit.YARD => distance * 0.9144,
      HealthDataUnit.INCH => distance * 0.0254,
      HealthDataUnit.CENTIMETER => distance / 100.0,
      _ => distance.toDouble(), // METER + anything unknown
    };
  }

  return RawWorkoutSession(
    externalId: '$platformPrefix:workout:${p.uuid}',
    startedAt: p.dateFrom.toUtc(),
    duration: duration,
    activityType: v.workoutActivityType.name.toLowerCase(),
    totalEnergyKcal: energyKcal,
    totalDistanceMeters: distanceMeters,
    sourceDevice: _sourceLabel(p),
  );
}

RawPointValue? _pointFrom(
  HealthDataPoint p,
  String platformPrefix, {
  required double scale,
}) {
  final v = _numericValue(p);
  if (v == null) return null;
  return RawPointValue(
    externalId: '$platformPrefix:${p.type.name.toLowerCase()}:${p.uuid}',
    measuredAt: p.dateFrom.toUtc(),
    value: v * scale,
    sourceDevice: _sourceLabel(p),
  );
}

/// Group [points] by UTC day and average the numeric values. The
/// synthetic [externalId] is `'<prefix>:<kindWire>:<yyyy-mm-dd>'` so
/// subsequent syncs replace the same row instead of duplicating.
List<RawDailyValue> _aggregateDailyAverage({
  required Iterable<HealthDataPoint> points,
  required String kindWire,
  required String platformPrefix,
}) {
  final buckets = <String, _DailyBucket>{};
  for (final p in points) {
    final v = _numericValue(p);
    if (v == null) continue;
    final dayKey = _dayKeyUtc(p.dateFrom);
    final bucket = buckets.putIfAbsent(
      dayKey,
      () => _DailyBucket(dayKey: dayKey, source: _sourceLabel(p)),
    );
    bucket.add(v);
  }
  return buckets.values
      .map(
        (b) => b.toDaily(
          externalId: '$platformPrefix:$kindWire:${b.dayKey}',
          reduce: _Reduce.average,
        ),
      )
      .toList(growable: false);
}

List<RawDailyValue> _aggregateDailySum({
  required Iterable<HealthDataPoint> points,
  required String kindWire,
  required String platformPrefix,
}) {
  final buckets = <String, _DailyBucket>{};
  for (final p in points) {
    final v = _numericValue(p);
    if (v == null) continue;
    final dayKey = _dayKeyUtc(p.dateFrom);
    final bucket = buckets.putIfAbsent(
      dayKey,
      () => _DailyBucket(dayKey: dayKey, source: _sourceLabel(p)),
    );
    bucket.add(v);
  }
  return buckets.values
      .map(
        (b) => b.toDaily(
          externalId: '$platformPrefix:$kindWire:${b.dayKey}',
          reduce: _Reduce.sum,
        ),
      )
      .toList(growable: false);
}

double? _numericValue(HealthDataPoint p) {
  final v = p.value;
  if (v is NumericHealthValue) return v.numericValue.toDouble();
  return null;
}

String? _sourceLabel(HealthDataPoint p) {
  final candidate = p.deviceModel ?? p.sourceName;
  if (candidate.trim().isEmpty) return null;
  return candidate;
}

String _dayKeyUtc(DateTime t) {
  final utc = t.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime _maxInstant(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

DateTime _minInstant(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

enum _Reduce { sum, average }

class _DailyBucket {
  _DailyBucket({required this.dayKey, required this.source});
  final String dayKey;
  final String? source;
  double _sum = 0.0;
  int _count = 0;

  void add(double v) {
    _sum += v;
    _count++;
  }

  RawDailyValue toDaily({required String externalId, required _Reduce reduce}) {
    final parts = dayKey.split('-');
    final day = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final value = switch (reduce) {
      _Reduce.sum => _sum,
      _Reduce.average => _count == 0 ? 0.0 : _sum / _count,
    };
    return RawDailyValue(
      externalId: externalId,
      day: day,
      value: value,
      sourceDevice: source,
    );
  }
}
