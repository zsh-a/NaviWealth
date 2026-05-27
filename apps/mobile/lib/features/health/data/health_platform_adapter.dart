/// Platform-independent HealthOS adapter contract
/// (`docs/healthos-domain.md` §2, D-2.2).
///
/// Wraps HealthKit (iOS) / Health Connect (Android) reads behind a
/// narrow seam so [HealthSyncService] stays platform-agnostic and
/// testable. Web returns an `unsupported` stub (HealthOS isn't shipped
/// to web — northstar §1.1).
///
/// **Read-only by design** — HealthOS never writes back to the platform
/// store (§10 反目标). The adapter only models reads + permission
/// negotiation.
library;

/// Capability surface the [HealthSyncService] needs from the platform.
abstract class HealthPlatformAdapter {
  /// `true` when the OS supports HealthKit / Health Connect at all.
  /// Returns `false` on web, on Android < HC-available, or when the
  /// Health Connect app isn't installed.
  Future<bool> isAvailable();

  /// `true` when the user has already granted read permissions for the
  /// HealthOS data types. Implementations may return `null` from the
  /// underlying API; we coerce to `false` so the caller can treat
  /// "unknown" as "not yet granted".
  Future<bool> hasPermissions();

  /// Show the OS permission sheet. Returns `true` if the user granted
  /// every requested read scope, `false` if any were denied or the
  /// sheet was dismissed.
  Future<bool> requestPermissions();

  /// One-shot pull of every supported metric in `[from, to)`. The
  /// adapter aggregates platform-side as needed (e.g. summing steps
  /// across multiple sources for a single day) so the service can
  /// just upsert.
  ///
  /// `from`/`to` are interpreted in UTC. Implementations must honour
  /// the half-open interval (don't double-count `to`).
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  });
}

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
        vo2Max = const <RawDailyValue>[];

  /// One [RawSleepSession] per ended sleep session (HealthKit
  /// `HKCategoryTypeIdentifierSleepAnalysis` of stage `asleep*`;
  /// Health Connect `SleepSessionRecord`). Per-stage histograms can
  /// land in [RawSleepSession.stageHistogramJson] later — MVP only
  /// records the outer duration.
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

  /// Daily VO2 max (ml/(kg·min)). HK `HKQuantityTypeIdentifierVO2Max`
  /// / HC `Vo2MaxRecord`. **NOTE**: as of `package:health@13.3.1` the
  /// plugin does not expose VO2 max — adapters keep this list empty
  /// until either the plugin gains VO2 max support or a native
  /// MethodChannel is added. The rest of the pipeline (repo / sync /
  /// indexer / AI tools) is wired so the day VO2 starts flowing only
  /// the adapter needs to change.
  final List<RawDailyValue> vo2Max;

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
      vo2Max.length;
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

  /// Optional per-stage histogram JSON (`{"core": 18000, "deep": 5400,
  /// "rem": 5400, "awake": 1800}`). Null when the platform returns
  /// only outer duration. MVP doesn't populate this; left as a seam
  /// for follow-up.
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
