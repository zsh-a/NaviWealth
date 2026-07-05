/// Native (iOS / Android) implementation of [HealthPlatformAdapter]
/// backed by `package:health` (`docs/domains/healthos-domain.md` §2, D-2.2).
///
/// HealthKit / Health Connect type mapping:
///
/// | HealthOS kind         | iOS HK type                              | Android HC type                                    |
/// |-----------------------|------------------------------------------|----------------------------------------------------|
/// | sleepSession          | `SLEEP_*` stage segments                 | `SLEEP_SESSION` (per session)                       |
/// | hrvDaily              | `HEART_RATE_VARIABILITY_SDNN`            | `HEART_RATE_VARIABILITY_RMSSD`                      |
/// | rhrDaily              | `RESTING_HEART_RATE`                     | `RESTING_HEART_RATE`                                |
/// | stepsDaily            | `STEPS`                                  | `STEPS`                                             |
/// | activeEnergyDaily     | `ACTIVE_ENERGY_BURNED`                   | `ACTIVE_ENERGY_BURNED`                              |
/// | weight                | `WEIGHT`                                 | `WEIGHT`                                            |
/// | bodyFat               | `BODY_FAT_PERCENTAGE` (0–100 → /100)     | `BODY_FAT_PERCENTAGE` (0–100 → /100)                |
/// | workoutSession        | `WORKOUT`                                | `WORKOUT`                                           |
/// | distanceWalkingRunning| `DISTANCE_WALKING_RUNNING`               | `DISTANCE_DELTA`                                     |
/// | heartRateDaily        | `HEART_RATE`                             | `HEART_RATE`                                        |
/// | totalEnergyDaily      | —                                        | `TOTAL_CALORIES_BURNED`                             |
/// | floorsClimbedDaily    | `FLIGHTS_CLIMBED`                        | `FLIGHTS_CLIMBED`                                   |
/// | respiratoryRateDaily  | `RESPIRATORY_RATE`                       | `RESPIRATORY_RATE`                                  |
/// | vo2Max                | Native HealthKit channel                 | Not exposed by `package:health` yet                 |
///
/// The plugin returns meters in both cases (we still bucket per UTC day
/// and sum, matching the steps/active-energy pipeline).
///
/// iOS HealthKit returns `HKCategoryTypeIdentifierSleepAnalysis` as
/// per-stage segments. The adapter merges those into nightly
/// [RawSleepSession] rows and persists a stage histogram.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:health/health.dart';

import 'health_platform_adapter.dart';

part 'health_platform_adapter_io_sleep.dart';
part 'health_platform_adapter_io_values.dart';
part 'health_platform_adapter_io_vo2max.dart';

const MethodChannel _healthKitChannel = MethodChannel(
  'com.naviwealth.healthkit',
);

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
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_AWAKE_IN_BED,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_UNKNOWN,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.WORKOUT,
        distanceType,
        HealthDataType.HEART_RATE,
        HealthDataType.FLIGHTS_CLIMBED,
        HealthDataType.RESPIRATORY_RATE,
      ];
    }
    if (Platform.isAndroid) {
      return <HealthDataType>[
        HealthDataType.SLEEP_SESSION,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_AWAKE_IN_BED,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_UNKNOWN,
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.WORKOUT,
        distanceType,
        HealthDataType.HEART_RATE,
        HealthDataType.TOTAL_CALORIES_BURNED,
        HealthDataType.FLIGHTS_CLIMBED,
        HealthDataType.RESPIRATORY_RATE,
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
    final granted = await _health.requestAuthorization(
      types,
      permissions: _readOnlyPermissions(types),
    );
    if (!Platform.isIOS) return granted;
    return granted && await _requestIosVo2MaxAuthorization();
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
    final distanceType = _distanceWalkingRunningType;

    final platformPrefix = Platform.isIOS ? 'hk' : 'hc';

    final sleepSessions = Platform.isIOS
        ? mergeSleepStageSegments(
            points
                .map((p) => _sleepStageSegmentFrom(p, platformPrefix))
                .whereType<RawSleepStageSegment>(),
          )
        : _attachSleepStageHistograms(
            points
                .where((p) => p.type == HealthDataType.SLEEP_SESSION)
                .map((p) => _sleepFrom(p, platformPrefix))
                .whereType<RawSleepSession>()
                .toList(growable: false),
            points,
          );

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
    final heartRate = _aggregateDailyAverage(
      points: points.where((p) => p.type == HealthDataType.HEART_RATE),
      kindWire: 'heart_rate',
      platformPrefix: platformPrefix,
    );
    final totalEnergy = _aggregateDailySum(
      points: points.where(
        (p) => p.type == HealthDataType.TOTAL_CALORIES_BURNED,
      ),
      kindWire: 'total_energy',
      platformPrefix: platformPrefix,
    );
    final floorsClimbed = _aggregateDailySum(
      points: points.where((p) => p.type == HealthDataType.FLIGHTS_CLIMBED),
      kindWire: 'floors_climbed',
      platformPrefix: platformPrefix,
    );
    final respiratoryRate = _aggregateDailyAverage(
      points: points.where((p) => p.type == HealthDataType.RESPIRATORY_RATE),
      kindWire: 'respiratory_rate',
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

    final vo2Max = await _fetchIosVo2Max(from: from, to: to);

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
      heartRate: heartRate,
      totalEnergy: totalEnergy,
      floorsClimbed: floorsClimbed,
      respiratoryRate: respiratoryRate,
    );
  }
}
