/// Platform-independent HealthOS adapter contract
/// (`docs/domains/healthos-domain.md` §2, D-2.2).
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

import 'dart:convert';

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

/// Default gap (≤ this much time between two `asleep` segments → same
/// night). Empirically Apple Watch can split a single night into 3–7
/// `SLEEP_ASLEEP` segments separated by awake-in-bed gaps; 30 minutes
/// captures the typical awakening / bathroom break without collapsing
/// genuinely separate sleeps (e.g. an afternoon nap).
const Duration kSleepSegmentMergeGap = Duration(minutes: 30);

/// Coalesce per-segment sleep rows into one row per night.
///
/// iOS HealthKit exports `HKCategoryTypeIdentifierSleepAnalysis` as
/// per-segment values; one calendar night with a couple of awakenings
/// arrives as 3–7 [RawSleepSession] entries. Android Health Connect
/// already supplies whole sessions so on that platform this is a no-op
/// (no segments will be within `gap` of each other unless the source
/// recorded them that way).
///
/// **Inputs**: any iterable of segments (may be in any order).
/// **Output**: list of merged sessions, ordered by [RawSleepSession.startedAt].
///
/// Merging rule: two consecutive segments collapse when the second's
/// `startedAt` is at most [gap] after the first's end. Merged session
/// duration = sum of all segments' durations (not span end-start —
/// that would double-count awake gaps). Merged `externalId` is keyed
/// on the first segment's UTC start so repeated syncs of the same
/// segment set hit the same row.
///
/// `sourceDevice` is the first segment's device; an honest "merged from
/// N segments" provenance hint goes into `stageHistogramJson` when
/// already-null. If the incoming segments already carry per-stage
/// histograms, those histograms are summed so merges do not lose stage
/// detail.
List<RawSleepSession> mergeSleepSegments(
  Iterable<RawSleepSession> segments, {
  Duration gap = kSleepSegmentMergeGap,
}) {
  final sorted = segments.toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  if (sorted.length < 2) return List<RawSleepSession>.unmodifiable(sorted);

  final merged = <RawSleepSession>[];
  var bucket = <RawSleepSession>[sorted.first];
  var bucketEnd = sorted.first.startedAt.add(sorted.first.duration);

  RawSleepSession flush(List<RawSleepSession> b) {
    final first = b.first;
    if (b.length == 1) return first;
    final totalDuration = b.fold<Duration>(
      Duration.zero,
      (acc, s) => acc + s.duration,
    );
    final device = b
        .firstWhere((s) => s.sourceDevice != null, orElse: () => first)
        .sourceDevice;
    final mergedHistogram = _mergeStageHistogramPayloads(
      b.map((s) => s.stageHistogramJson),
      fallbackSegments: b.length,
    );
    // Keep the prefix of the underlying segments so the merged id stays
    // `hk:…` on iOS and `hc:…` on Android (Android shouldn't actually
    // produce merged buckets, but be defensive). Falls back to `hk` for
    // synthetic test inputs that don't use a prefix.
    final firstId = first.externalId;
    final prefix = firstId.contains(':')
        ? firstId.substring(0, firstId.indexOf(':'))
        : 'hk';
    return RawSleepSession(
      externalId: '$prefix:sleep:merged:${first.startedAt.toIso8601String()}',
      startedAt: first.startedAt,
      duration: totalDuration,
      sourceDevice: device,
      stageHistogramJson: mergedHistogram,
    );
  }

  for (var i = 1; i < sorted.length; i++) {
    final s = sorted[i];
    if (s.startedAt.difference(bucketEnd) <= gap) {
      bucket.add(s);
      final sEnd = s.startedAt.add(s.duration);
      if (sEnd.isAfter(bucketEnd)) bucketEnd = sEnd;
    } else {
      merged.add(flush(bucket));
      bucket = <RawSleepSession>[s];
      bucketEnd = s.startedAt.add(s.duration);
    }
  }
  merged.add(flush(bucket));
  return List<RawSleepSession>.unmodifiable(merged);
}

/// One platform sleep-analysis segment with an explicit stage label.
///
/// iOS HealthKit often returns sleep as category segments rather than a
/// session envelope. This DTO lets the adapter preserve stage detail
/// (`light` / `deep` / `rem` / `awake` / `unknown` / `asleep`) while
/// merging those segments into [RawSleepSession] rows. `awake` contributes
/// to the histogram but not to [RawSleepSession.duration].
class RawSleepStageSegment {
  const RawSleepStageSegment({
    required this.externalId,
    required this.startedAt,
    required this.duration,
    required this.stage,
    this.sourceDevice,
  });

  final String externalId;
  final DateTime startedAt;
  final Duration duration;
  final String stage;
  final String? sourceDevice;

  bool get isAwake => stage == 'awake';
}

/// Coalesce HealthKit-style stage segments into nightly sessions.
///
/// Non-awake stages define session membership and total sleep duration.
/// Awake segments within [gap] of the current sleep bucket are retained
/// in the histogram but do not add to sleep duration. Awake-only ranges
/// are ignored because they do not describe a completed sleep session.
List<RawSleepSession> mergeSleepStageSegments(
  Iterable<RawSleepStageSegment> segments, {
  Duration gap = kSleepSegmentMergeGap,
}) {
  final sorted =
      segments.where((s) => s.duration > Duration.zero).toList(growable: false)
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  if (sorted.isEmpty) return const <RawSleepSession>[];

  final merged = <RawSleepSession>[];
  var bucket = <RawSleepStageSegment>[];
  DateTime? bucketEnd;

  void flush() {
    if (bucket.isEmpty) return;
    final sleepSegments = bucket.where((s) => !s.isAwake).toList();
    if (sleepSegments.isEmpty) {
      bucket = <RawSleepStageSegment>[];
      bucketEnd = null;
      return;
    }

    final first = sleepSegments.first;
    final totalDuration = sleepSegments.fold<Duration>(
      Duration.zero,
      (acc, s) => acc + s.duration,
    );
    final secondsByStage = <String, int>{};
    for (final s in bucket) {
      secondsByStage.update(
        s.stage,
        (value) => value + s.duration.inSeconds,
        ifAbsent: () => s.duration.inSeconds,
      );
    }
    final device = bucket
        .firstWhere((s) => s.sourceDevice != null, orElse: () => first)
        .sourceDevice;
    final prefix = _platformPrefixFromExternalId(first.externalId);
    merged.add(
      RawSleepSession(
        externalId: '$prefix:sleep:merged:${first.startedAt.toIso8601String()}',
        startedAt: first.startedAt,
        duration: totalDuration,
        sourceDevice: device,
        stageHistogramJson: _encodeStageHistogram(secondsByStage),
      ),
    );
    bucket = <RawSleepStageSegment>[];
    bucketEnd = null;
  }

  for (final segment in sorted) {
    final end = segment.startedAt.add(segment.duration);
    if (bucket.isEmpty) {
      if (segment.isAwake) continue;
      bucket = <RawSleepStageSegment>[segment];
      bucketEnd = end;
      continue;
    }

    final currentEnd = bucketEnd!;
    if (segment.startedAt.difference(currentEnd) <= gap) {
      bucket.add(segment);
      if (end.isAfter(currentEnd)) bucketEnd = end;
      continue;
    }

    flush();
    if (!segment.isAwake) {
      bucket = <RawSleepStageSegment>[segment];
      bucketEnd = end;
    }
  }
  flush();
  return List<RawSleepSession>.unmodifiable(merged);
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

String _platformPrefixFromExternalId(String externalId) {
  return externalId.contains(':')
      ? externalId.substring(0, externalId.indexOf(':'))
      : 'hk';
}

String? _mergeStageHistogramPayloads(
  Iterable<String?> payloads, {
  required int fallbackSegments,
}) {
  final secondsByStage = <String, int>{};
  for (final payload in payloads) {
    if (payload == null || payload.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) continue;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! num) continue;
        secondsByStage.update(
          entry.key.toString(),
          (current) => current + value.round(),
          ifAbsent: () => value.round(),
        );
      }
    } on Object {
      continue;
    }
  }
  if (secondsByStage.isEmpty) return '{"merged_segments":$fallbackSegments}';
  return _encodeStageHistogram(secondsByStage);
}

String _encodeStageHistogram(Map<String, int> secondsByStage) {
  final ordered = <String, int>{
    for (final key in const <String>[
      'light',
      'deep',
      'rem',
      'awake',
      'unknown',
      'asleep',
    ])
      if ((secondsByStage[key] ?? 0) > 0) key: secondsByStage[key]!,
  };
  for (final entry in secondsByStage.entries) {
    if (ordered.containsKey(entry.key) || entry.value <= 0) continue;
    ordered[entry.key] = entry.value;
  }
  return jsonEncode(ordered);
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
