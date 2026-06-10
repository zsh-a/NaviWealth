/// Discriminator for rows in the `health_metrics` table
/// (`docs/healthos-domain.md` §1 + §3, D-2.1).
///
/// Stored as a free-text column on the Drift side so a new kind can
/// land without a schema bump; the enum here is the canonical client
/// surface. Wire names use `snake_case` and match the column literal
/// (`'sleep_session'`, `'hrv_daily'`, …) — never rename a wire name
/// without a migration.
library;

enum HealthMetricKind {
  /// One sleep session (capturedAt = session start, value = duration
  /// in seconds, payloadJson holds the per-stage histogram).
  sleepSession,

  /// One HRV reading aggregated to a calendar day (capturedAt = local
  /// day start in UTC, value = HRV in ms, unit = `'ms'`).
  hrvDaily,

  /// Daily step count (value = count, unit = `'count'`).
  stepsDaily,

  /// Daily resting heart rate (value = bpm, unit = `'bpm'`).
  rhrDaily,

  /// Daily active energy burned (value = kcal, unit = `'kcal'`).
  activeEnergyDaily,

  /// One body-weight measurement (value = kg, unit = `'kg'`).
  weight,

  /// One body-fat measurement (value = fraction 0.0–1.0, unit =
  /// `'fraction'`).
  bodyFat,

  /// One workout session (capturedAt = session start, value = duration
  /// in seconds, unit = `'s'`). `payloadJson` carries
  /// `{activityType, totalEnergyKcal, totalDistanceMeters}` when the
  /// platform supplies them.
  workoutSession,

  /// Daily VO2 max reading (capturedAt = local day start UTC,
  /// value = ml/(kg·min), unit = `'ml_kg_min'`).
  vo2Max,

  /// Daily walking + running distance (independent of workout sessions —
  /// captures background steps over the day). capturedAt = local day
  /// start UTC, value = meters, unit = `'m'`.
  distanceWalkingRunningDaily,

  /// Daily average heart rate from platform samples. This is distinct
  /// from resting heart rate: Garmin Health Connect sharing exposes
  /// heart-rate samples, but does not currently guarantee RHR.
  heartRateDaily,

  /// Daily total calories burned (active + basal where the platform
  /// source supplies the total). Android Health Connect only today.
  totalEnergyDaily,

  /// Daily floors climbed.
  floorsClimbedDaily,

  /// Daily average respiratory rate.
  respiratoryRateDaily,

  /// Daily average stress level (Garmin-specific).
  /// capturedAt = local day start UTC, value = avg stress level (0–100),
  /// unit = `'level'`. payloadJson may contain per-slot detail.
  stressDaily,

  /// Daily Body Battery summary (Garmin-specific).
  /// capturedAt = local day start UTC, value = max level (0–100),
  /// unit = `'level'`. payloadJson carries
  /// `{min, max, charged, drained}`.
  bodyBatteryDaily,

  /// Weekly training load (Garmin-specific, from trainingStatus endpoint).
  /// capturedAt = local day start UTC, value = load score,
  /// unit = `'load'`.
  trainingLoadDaily,

  /// Training effect label encoded as numeric score (Garmin-specific).
  /// capturedAt = local day start UTC, value = 0–4 level,
  /// unit = `'level'`. 4=Improving, 3=Productive, 2=Maintaining,
  /// 1=Recovery, 0=Strained.
  trainingEffectDaily,

  /// Sentinel for wire kinds the client doesn't recognise. Callers
  /// should drop rows with this kind rather than crash.
  unknown,
}

extension HealthMetricKindX on HealthMetricKind {
  /// Stable wire / column name. Used as the `kind` column literal.
  String get wire => switch (this) {
    HealthMetricKind.sleepSession => 'sleep_session',
    HealthMetricKind.hrvDaily => 'hrv_daily',
    HealthMetricKind.stepsDaily => 'steps_daily',
    HealthMetricKind.rhrDaily => 'rhr_daily',
    HealthMetricKind.activeEnergyDaily => 'active_energy_daily',
    HealthMetricKind.weight => 'weight',
    HealthMetricKind.bodyFat => 'body_fat',
    HealthMetricKind.workoutSession => 'workout_session',
    HealthMetricKind.vo2Max => 'vo2_max_daily',
    HealthMetricKind.distanceWalkingRunningDaily =>
      'distance_walking_running_daily',
    HealthMetricKind.heartRateDaily => 'heart_rate_daily',
    HealthMetricKind.totalEnergyDaily => 'total_energy_daily',
    HealthMetricKind.floorsClimbedDaily => 'floors_climbed_daily',
    HealthMetricKind.respiratoryRateDaily => 'respiratory_rate_daily',
    HealthMetricKind.stressDaily => 'stress_daily',
    HealthMetricKind.bodyBatteryDaily => 'body_battery_daily',
    HealthMetricKind.trainingLoadDaily => 'training_load_daily',
    HealthMetricKind.trainingEffectDaily => 'training_effect_daily',
    HealthMetricKind.unknown => 'unknown',
  };

  /// Conventional unit string for the [HealthMetricKind]. Callers
  /// should still write the unit they actually have on the row —
  /// this is a default to use when the platform didn't supply one.
  String get defaultUnit => switch (this) {
    HealthMetricKind.sleepSession => 's',
    HealthMetricKind.hrvDaily => 'ms',
    HealthMetricKind.stepsDaily => 'count',
    HealthMetricKind.rhrDaily => 'bpm',
    HealthMetricKind.activeEnergyDaily => 'kcal',
    HealthMetricKind.weight => 'kg',
    HealthMetricKind.bodyFat => 'fraction',
    HealthMetricKind.workoutSession => 's',
    HealthMetricKind.vo2Max => 'ml_kg_min',
    HealthMetricKind.distanceWalkingRunningDaily => 'm',
    HealthMetricKind.heartRateDaily => 'bpm',
    HealthMetricKind.totalEnergyDaily => 'kcal',
    HealthMetricKind.floorsClimbedDaily => 'count',
    HealthMetricKind.respiratoryRateDaily => 'rpm',
    HealthMetricKind.stressDaily => 'level',
    HealthMetricKind.bodyBatteryDaily => 'level',
    HealthMetricKind.trainingLoadDaily => 'load',
    HealthMetricKind.trainingEffectDaily => 'level',
    HealthMetricKind.unknown => '',
  };

  static HealthMetricKind parse(String wire) {
    for (final k in HealthMetricKind.values) {
      if (k.wire == wire) return k;
    }
    return HealthMetricKind.unknown;
  }
}
