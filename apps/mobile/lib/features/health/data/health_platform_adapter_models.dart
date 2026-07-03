part of 'health_platform_adapter.dart';

/// Aggregate bundle returned from a single platform pull. Each list
/// is per-kind, deduplicated by [externalId] (HealthKit/HC UUID), so
/// the sync service can map straight to `HealthMetric` rows without
/// extra grouping.
class HealthPlatformSnapshot {
  const HealthPlatformSnapshot({
    this.sleepSessions = const <RawSleepSession>[],
    this.hrv = const <RawDailyValue>[],
    this.rhr = const <RawDailyValue>[],
    this.steps = const <RawDailyValue>[],
    this.activeEnergy = const <RawDailyValue>[],
    this.weight = const <RawPointValue>[],
    this.bodyFat = const <RawPointValue>[],
    this.workouts = const <RawWorkoutSession>[],
    this.vo2Max = const <RawDailyValue>[],
    this.distanceWalkingRunning = const <RawDailyValue>[],
    this.heartRate = const <RawDailyValue>[],
    this.totalEnergy = const <RawDailyValue>[],
    this.floorsClimbed = const <RawDailyValue>[],
    this.respiratoryRate = const <RawDailyValue>[],
  });

  const HealthPlatformSnapshot.empty()
    : sleepSessions = const <RawSleepSession>[],
      hrv = const <RawDailyValue>[],
      rhr = const <RawDailyValue>[],
      steps = const <RawDailyValue>[],
      activeEnergy = const <RawDailyValue>[],
      weight = const <RawPointValue>[],
      bodyFat = const <RawPointValue>[],
      workouts = const <RawWorkoutSession>[],
      vo2Max = const <RawDailyValue>[],
      distanceWalkingRunning = const <RawDailyValue>[],
      heartRate = const <RawDailyValue>[],
      totalEnergy = const <RawDailyValue>[],
      floorsClimbed = const <RawDailyValue>[],
      respiratoryRate = const <RawDailyValue>[];

  /// One [RawSleepSession] per ended sleep session. HealthKit
  /// `HKCategoryTypeIdentifierSleepAnalysis` segments are coalesced into
  /// nightly sessions with a per-stage histogram; Health Connect
  /// `SleepSessionRecord` rows are already session-shaped and may carry
  /// stage histograms from companion stage records.
  final List<RawSleepSession> sleepSessions;

  /// Daily HRV averages (ms). HealthKit `HKQuantityTypeIdentifier`
  /// `HeartRateVariabilitySDNN`; HC `HeartRateVariabilityRecord`.
  final List<RawDailyValue> hrv;

  /// Daily resting heart rate (bpm).
  final List<RawDailyValue> rhr;

  /// Daily step count.
  final List<RawDailyValue> steps;

  /// Daily active energy burned (kcal).
  final List<RawDailyValue> activeEnergy;

  /// Per-measurement body weight (kg).
  final List<RawPointValue> weight;

  /// Per-measurement body fat fraction (0.0–1.0).
  final List<RawPointValue> bodyFat;

  /// Workout sessions (HK `HKWorkout` / HC `ExerciseSessionRecord`).
  /// One entry per session; the adapter fills in [RawWorkoutSession]
  /// activity / energy / distance fields from whatever the platform
  /// reports — any may be missing.
  final List<RawWorkoutSession> workouts;

  /// Daily VO2 max (ml/(kg·min)). iOS reads
  /// `HKQuantityTypeIdentifierVO2Max` through the app's native
  /// HealthKit channel because `package:health` does not expose the
  /// type yet. Android stays empty until the plugin or a Health
  /// Connect channel exposes `Vo2MaxRecord`.
  final List<RawDailyValue> vo2Max;

  /// Daily walking + running distance (meters). HK
  /// `HKQuantityTypeIdentifierDistanceWalkingRunning` / HC
  /// `DistanceRecord`. Independent of `workouts` — captures background
  /// strolls + commute that don't get recorded as a session.
  final List<RawDailyValue> distanceWalkingRunning;

  /// Daily average heart rate (bpm). Garmin's native Health Connect
  /// export currently shares heart rate, while HRV/RHR may be absent.
  final List<RawDailyValue> heartRate;

  /// Daily total calories burned (kcal). Health Connect-only in the
  /// current plugin; active calories remain separate.
  final List<RawDailyValue> totalEnergy;

  /// Daily floors climbed.
  final List<RawDailyValue> floorsClimbed;

  /// Daily average respiratory rate (breaths/min).
  final List<RawDailyValue> respiratoryRate;

  /// Total number of raw readings across every list — handy for
  /// "fetched N readings" status text without re-summing in the UI.
  int get totalCount =>
      sleepSessions.length +
      hrv.length +
      rhr.length +
      steps.length +
      activeEnergy.length +
      weight.length +
      bodyFat.length +
      workouts.length +
      vo2Max.length +
      distanceWalkingRunning.length +
      heartRate.length +
      totalEnergy.length +
      floorsClimbed.length +
      respiratoryRate.length;
}

/// One sleep session that has already ended (no in-progress sessions).
class RawSleepSession {
  const RawSleepSession({
    required this.externalId,
    required this.startedAt,
    required this.duration,
    this.sourceDevice,
    this.stageHistogramJson,
  });

  /// Platform-stable id used for dedup. HealthKit `HKObject.uuid`
  /// (lowercased), HC `Record.metadata.id`. Plus a `hk:` / `hc:`
  /// prefix so collisions between platforms are impossible.
  final String externalId;

  /// Session start in UTC.
  final DateTime startedAt;

  /// Total in-bed-asleep duration. Equivalent to `endedAt - startedAt`
  /// minus awake stages.
  final Duration duration;

  /// Best-effort device label (`'Apple Watch'`, `'Pixel Watch'`, …).
  final String? sourceDevice;

  /// Optional per-stage histogram JSON (`{"light": 18000, "deep": 5400,
  /// "rem": 5400, "awake": 1800}`). Null when the platform returns
  /// only outer duration.
  final String? stageHistogramJson;
}

/// A value bucketed to a calendar day (UTC day-start as the timestamp).
class RawDailyValue {
  const RawDailyValue({
    required this.externalId,
    required this.day,
    required this.value,
    this.sourceDevice,
  });

  /// Platform-stable id. For daily aggregates synthesised across
  /// multiple platform records, the adapter chooses a stable composite
  /// (e.g. `'hk:steps:2026-05-27'`).
  final String externalId;

  /// UTC day-start the value refers to.
  final DateTime day;

  final double value;

  final String? sourceDevice;
}

/// One workout session that has already ended. Most fields are
/// optional because HealthKit / Health Connect both surface workouts
/// without (some of) `totalEnergyBurned` / `totalDistance`.
class RawWorkoutSession {
  const RawWorkoutSession({
    required this.externalId,
    required this.startedAt,
    required this.duration,
    this.activityType,
    this.totalEnergyKcal,
    this.totalDistanceMeters,
    this.sourceDevice,
  });

  /// Platform-stable id (`hk:workout:<uuid>` / `hc:workout:<uuid>`).
  final String externalId;
  final DateTime startedAt;
  final Duration duration;

  /// Platform-reported activity label, lowercased free text
  /// (`'running'`, `'cycling'`, `'strength_training'`, …). Null when
  /// the platform didn't classify the session.
  final String? activityType;

  /// Total active kilocalories spent. Null when missing.
  final double? totalEnergyKcal;

  /// Total distance in meters (HK + HC both report distance in meters
  /// via the plugin). Null when not a distance activity.
  final double? totalDistanceMeters;

  final String? sourceDevice;
}

/// A single timestamped measurement (weight, body-fat reading, etc.).
class RawPointValue {
  const RawPointValue({
    required this.externalId,
    required this.measuredAt,
    required this.value,
    this.sourceDevice,
  });

  final String externalId;
  final DateTime measuredAt;
  final double value;
  final String? sourceDevice;
}
