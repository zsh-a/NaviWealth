part of 'health_platform_adapter.dart';

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
