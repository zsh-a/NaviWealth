/// Native (iOS / Android) implementation of [HealthPlatformAdapter]
/// backed by `package:health` (`docs/healthos-domain.md` §2, D-2.2).
///
/// HealthKit / Health Connect type mapping:
///
/// | HealthOS kind         | iOS HK type                              | Android HC type                                    |
/// |-----------------------|------------------------------------------|----------------------------------------------------|
/// | sleepSession          | `SLEEP_ASLEEP` (per segment)             | `SLEEP_SESSION` (per session)                       |
/// | hrvDaily              | `HEART_RATE_VARIABILITY_SDNN`            | `HEART_RATE_VARIABILITY_RMSSD`                      |
/// | rhrDaily              | `RESTING_HEART_RATE`                     | `RESTING_HEART_RATE`                                |
/// | stepsDaily            | `STEPS`                                  | `STEPS`                                             |
/// | activeEnergyDaily     | `ACTIVE_ENERGY_BURNED`                   | `ACTIVE_ENERGY_BURNED`                              |
/// | weight                | `WEIGHT`                                 | `WEIGHT`                                            |
/// | bodyFat               | `BODY_FAT_PERCENTAGE` (0–100 → /100)     | `BODY_FAT_PERCENTAGE` (0–100 → /100)                |
/// | workoutSession        | `WORKOUT`                                | `WORKOUT`                                           |
/// | distanceWalkingRunning| `DISTANCE_WALKING_RUNNING`               | `DISTANCE_DELTA`                                     |
/// | vo2Max                | *not yet exposed by `package:health@13.3.1`* — list stays empty until plugin support lands or a native channel is added |
///
/// The plugin returns meters in both cases (we still bucket per UTC day
/// and sum, matching the steps/active-energy pipeline).
///
/// **iOS sleep MVP caveat**: HealthKit returns per-segment
/// `SLEEP_ASLEEP` entries — one nightly sleep can become 3–7 segments
/// depending on awakenings. We emit one [RawSleepSession] per segment
/// for now; the Memory indexer downstream tolerates extra rows because
/// the AI tools aggregate by day anyway. Proper segment→session
/// merging is a follow-up.
library;

import 'dart:io';

import 'package:health/health.dart';

import 'health_platform_adapter.dart';

HealthPlatformAdapter createHealthPlatformAdapter() => _HealthPackageAdapter();

class _HealthPackageAdapter implements HealthPlatformAdapter {
  _HealthPackageAdapter();

  final Health _health = Health();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  List<HealthDataType> get _types {
    final distanceType = _distanceWalkingRunningType;
    if (Platform.isIOS) {
      return <HealthDataType>[
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.WORKOUT,
        distanceType,
      ];
    }
    if (Platform.isAndroid) {
      return <HealthDataType>[
        HealthDataType.SLEEP_SESSION,
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.WORKOUT,
        distanceType,
      ];
    }
    return const <HealthDataType>[];
  }

  HealthDataType get _distanceWalkingRunningType => Platform.isAndroid
      ? HealthDataType.DISTANCE_DELTA
      : HealthDataType.DISTANCE_WALKING_RUNNING;

  List<HealthDataAccess> _readOnlyPermissions(List<HealthDataType> types) =>
      List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    await _ensureConfigured();
    if (Platform.isAndroid) {
      // On Android the Health Connect app must be installed.
      try {
        return await _health.isHealthConnectAvailable();
      } on Object {
        return false;
      }
    }
    // iOS: HealthKit is always present on real devices; the simulator
    // also reports availability but returns empty data.
    return true;
  }

  @override
  Future<bool> hasPermissions() async {
    if (!await isAvailable()) return false;
    final types = _types;
    final result = await _health.hasPermissions(
      types,
      permissions: _readOnlyPermissions(types),
    );
    // Health Connect (Android) refuses to report READ-permission status by
    // design — querying it would leak whether the user has data of a given
    // type — so `hasPermissions` always returns `null` there even after the
    // user grants everything. Treat `null` as "unknown → assume granted" on
    // Android so sync isn't permanently blocked; an empty fetch reveals the
    // genuinely-unauthorized case. iOS reports a real value, so honour it.
    if (Platform.isAndroid) return result ?? true;
    return result ?? false;
  }

  @override
  Future<bool> requestPermissions() async {
    if (!await isAvailable()) return false;
    final types = _types;
    return _health.requestAuthorization(
      types,
      permissions: _readOnlyPermissions(types),
    );
  }

  @override
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!await isAvailable()) return const HealthPlatformSnapshot.empty();
    await _ensureConfigured();

    final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: from,
      endTime: to,
    );

    final hrvType = Platform.isIOS
        ? HealthDataType.HEART_RATE_VARIABILITY_SDNN
        : HealthDataType.HEART_RATE_VARIABILITY_RMSSD;
    final sleepType = Platform.isIOS
        ? HealthDataType.SLEEP_ASLEEP
        : HealthDataType.SLEEP_SESSION;
    final distanceType = _distanceWalkingRunningType;

    final platformPrefix = Platform.isIOS ? 'hk' : 'hc';

    final rawSleep = points
        .where((p) => p.type == sleepType)
        .map(_sleepFrom)
        .whereType<RawSleepSession>()
        .toList(growable: false);
    // iOS emits per-segment SLEEP_ASLEEP rows (3–7 per night). Merge
    // them into one row per night so the Today UI + AI tools don't have
    // to count segments. On Android the gap threshold guarantees this
    // is a no-op (whole sessions don't fall within 30 min of each
    // other unless the source recorded them that way).
    final sleepSessions = mergeSleepSegments(rawSleep);

    final hrv = _aggregateDailyAverage(
      points: points.where((p) => p.type == hrvType),
      kindWire: 'hrv',
      platformPrefix: platformPrefix,
    );
    final rhr = _aggregateDailyAverage(
      points: points.where((p) => p.type == HealthDataType.RESTING_HEART_RATE),
      kindWire: 'rhr',
      platformPrefix: platformPrefix,
    );
    final steps = _aggregateDailySum(
      points: points.where((p) => p.type == HealthDataType.STEPS),
      kindWire: 'steps',
      platformPrefix: platformPrefix,
    );
    final active = _aggregateDailySum(
      points: points.where(
        (p) => p.type == HealthDataType.ACTIVE_ENERGY_BURNED,
      ),
      kindWire: 'active_energy',
      platformPrefix: platformPrefix,
    );
    final distanceWalkRun = _aggregateDailySum(
      points: points.where((p) => p.type == distanceType),
      kindWire: 'distance_walking_running',
      platformPrefix: platformPrefix,
    );

    final weight = points
        .where((p) => p.type == HealthDataType.WEIGHT)
        .map((p) => _pointFrom(p, platformPrefix, scale: 1.0))
        .whereType<RawPointValue>()
        .toList(growable: false);

    // Body fat: health package reports PERCENT (0–100); our domain
    // uses fraction (0.0–1.0). Scale once at the boundary.
    final bodyFat = points
        .where((p) => p.type == HealthDataType.BODY_FAT_PERCENTAGE)
        .map((p) => _pointFrom(p, platformPrefix, scale: 0.01))
        .whereType<RawPointValue>()
        .toList(growable: false);

    final workouts = points
        .where((p) => p.type == HealthDataType.WORKOUT)
        .map((p) => _workoutFrom(p, platformPrefix))
        .whereType<RawWorkoutSession>()
        .toList(growable: false);

    // VO2 max is intentionally empty — see the docstring at the top of
    // this file. The day `package:health` exposes it (or we add a
    // native MethodChannel) it lands here.
    const vo2Max = <RawDailyValue>[];

    return HealthPlatformSnapshot(
      sleepSessions: sleepSessions,
      hrv: hrv,
      rhr: rhr,
      steps: steps,
      activeEnergy: active,
      weight: weight,
      bodyFat: bodyFat,
      workouts: workouts,
      vo2Max: vo2Max,
      distanceWalkingRunning: distanceWalkRun,
    );
  }

  RawSleepSession? _sleepFrom(HealthDataPoint p) {
    final duration = p.dateTo.difference(p.dateFrom);
    if (duration <= Duration.zero) return null;
    return RawSleepSession(
      externalId: 'hk:sleep:${p.uuid}',
      startedAt: p.dateFrom.toUtc(),
      duration: duration,
      sourceDevice: _sourceLabel(p),
    );
  }

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

  static double? _numericValue(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  static String? _sourceLabel(HealthDataPoint p) {
    final candidate = p.deviceModel ?? p.sourceName;
    if (candidate.trim().isEmpty) return null;
    return candidate;
  }

  static String _dayKeyUtc(DateTime t) {
    final utc = t.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

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
