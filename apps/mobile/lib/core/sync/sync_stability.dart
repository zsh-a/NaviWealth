import 'dart:convert';

import 'package:drift/drift.dart';

import '../persistence/app_database.dart';

const kSyncStabilityRetentionDays = 30;

class SyncStabilitySample {
  const SyncStabilitySample({
    required this.at,
    required this.success,
    required this.retryableFailures,
    required this.fatalFailures,
    required this.localWins,
    required this.ignoredRows,
    required this.generationResets,
    required this.generationResetFailures,
  });

  final DateTime at;
  final bool success;
  final int retryableFailures;
  final int fatalFailures;
  final int localWins;
  final int ignoredRows;
  final int generationResets;
  final int generationResetFailures;
}

enum SyncStabilityGateStatus { insufficientData, passing, failing }

enum SyncStabilityGateIssue {
  insufficientSamples,
  insufficientDuration,
  successRateBelowMinimum,
  fatalFailures,
  generationResetFailures,
}

/// A UTC-day aggregate. Storage remains bounded by days, while every cycle
/// contributes to rates and failure counts regardless of polling frequency.
class SyncStabilityBucket {
  SyncStabilityBucket({
    required this.firstAt,
    required this.lastAt,
    required Map<String, int> counts,
  }) : _counts = Map.unmodifiable(counts);

  final DateTime firstAt;
  final DateTime lastAt;
  final Map<String, int> _counts;
  int count(String key) => _counts[key] ?? 0;
  String get day => firstAt.toUtc().toIso8601String().substring(0, 10);

  factory SyncStabilityBucket.sample(
    SyncStabilitySample sample, {
    bool recovered = false,
  }) => SyncStabilityBucket(
    firstAt: sample.at.toUtc(),
    lastAt: sample.at.toUtc(),
    counts: {
      'cycles': 1,
      'successful_cycles': sample.success ? 1 : 0,
      'retryable_failures': sample.retryableFailures,
      'fatal_failures': sample.fatalFailures,
      'local_wins': sample.localWins,
      'ignored_rows': sample.ignoredRows,
      'generation_resets': sample.generationResets,
      'generation_reset_failures': sample.generationResetFailures,
      'recovered_cycles': recovered ? 1 : 0,
    },
  );

  SyncStabilityBucket merge(SyncStabilityBucket other) => SyncStabilityBucket(
    firstAt: firstAt.isBefore(other.firstAt) ? firstAt : other.firstAt,
    lastAt: lastAt.isAfter(other.lastAt) ? lastAt : other.lastAt,
    counts: {for (final key in _countKeys) key: count(key) + other.count(key)},
  );

  Map<String, Object?> toJson() => {
    'first_at': firstAt.toIso8601String(),
    'last_at': lastAt.toIso8601String(),
    for (final key in _countKeys) key: count(key),
  };

  static SyncStabilityBucket? tryParse(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final first = json['first_at'];
    final last = json['last_at'];
    if (first is! String || last is! String) return null;
    final firstAt = DateTime.tryParse(first)?.toUtc();
    final lastAt = DateTime.tryParse(last)?.toUtc();
    if (firstAt == null || lastAt == null || lastAt.isBefore(firstAt)) {
      return null;
    }
    final counts = {
      for (final key in _countKeys) key: _nonNegativeInt(json[key]),
    };
    if (counts['cycles'] == 0 ||
        counts['successful_cycles']! > counts['cycles']!) {
      return null;
    }
    return SyncStabilityBucket(
      firstAt: firstAt,
      lastAt: lastAt,
      counts: counts,
    );
  }
}

const _countKeys = {
  'cycles',
  'successful_cycles',
  'retryable_failures',
  'fatal_failures',
  'local_wins',
  'ignored_rows',
  'generation_resets',
  'generation_reset_failures',
  'recovered_cycles',
};

List<SyncStabilityBucket> _bucketsFromSamples(
  List<SyncStabilitySample> samples,
) {
  final sorted = List<SyncStabilitySample>.of(samples)
    ..sort((a, b) => a.at.compareTo(b.at));
  final days = <String, SyncStabilityBucket>{};
  bool? previousSuccess;
  for (final sample in sorted) {
    final bucket = SyncStabilityBucket.sample(
      sample,
      recovered: previousSuccess == false && sample.success,
    );
    days[bucket.day] = days[bucket.day]?.merge(bucket) ?? bucket;
    previousSuccess = sample.success;
  }
  return List.unmodifiable(days.values);
}

class SyncStabilityReport {
  SyncStabilityReport({
    required List<SyncStabilitySample> samples,
    this.minimumSamples = 10,
    this.minimumSuccessRate = 0.95,
    this.minimumWindowDuration = const Duration(days: 14),
  }) : buckets = _bucketsFromSamples(samples);

  SyncStabilityReport.fromBuckets({
    required List<SyncStabilityBucket> buckets,
    this.minimumSamples = 10,
    this.minimumSuccessRate = 0.95,
    this.minimumWindowDuration = const Duration(days: 14),
  }) : buckets = List.unmodifiable(
         List<SyncStabilityBucket>.of(buckets)
           ..sort((a, b) => a.firstAt.compareTo(b.firstAt)),
       );

  final List<SyncStabilityBucket> buckets;
  int get cycleCount => _sum('cycles');
  int _sum(String key) =>
      buckets.fold(0, (total, bucket) => total + bucket.count(key));
  final int minimumSamples;
  final double minimumSuccessRate;
  final Duration minimumWindowDuration;

  int get successfulCycles => _sum('successful_cycles');
  int get failedCycles => cycleCount - successfulCycles;
  int get retryableFailures => _sum('retryable_failures');
  int get fatalFailures => _sum('fatal_failures');
  int get localWins => _sum('local_wins');
  int get ignoredRows => _sum('ignored_rows');
  int get generationResets => _sum('generation_resets');
  int get generationResetFailures => _sum('generation_reset_failures');
  int get recoveredCycles => _sum('recovered_cycles');

  Duration get observedDuration => buckets.isEmpty
      ? Duration.zero
      : buckets.last.lastAt.difference(buckets.first.firstAt).abs();
  double get successRate => buckets.isEmpty ? 0 : successfulCycles / cycleCount;

  DateTime? get windowStart =>
      buckets.isEmpty ? null : buckets.first.firstAt.toUtc();
  DateTime? get windowEnd =>
      buckets.isEmpty ? null : buckets.last.lastAt.toUtc();
  int get remainingSamples {
    final remaining = minimumSamples - cycleCount;
    return remaining > 0 ? remaining : 0;
  }

  Duration get remainingWindowDuration {
    final remaining = minimumWindowDuration - observedDuration;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  List<SyncStabilityGateIssue> get gateIssues => <SyncStabilityGateIssue>[
    if (cycleCount < minimumSamples) SyncStabilityGateIssue.insufficientSamples,
    if (observedDuration < minimumWindowDuration)
      SyncStabilityGateIssue.insufficientDuration,
    if (buckets.isNotEmpty && successRate < minimumSuccessRate)
      SyncStabilityGateIssue.successRateBelowMinimum,
    if (fatalFailures > 0) SyncStabilityGateIssue.fatalFailures,
    if (generationResetFailures > 0)
      SyncStabilityGateIssue.generationResetFailures,
  ];

  SyncStabilityGateStatus get gateStatus {
    final issues = gateIssues;
    if (issues.contains(SyncStabilityGateIssue.insufficientSamples) ||
        issues.contains(SyncStabilityGateIssue.insufficientDuration)) {
      return SyncStabilityGateStatus.insufficientData;
    }
    if (issues.isNotEmpty) {
      return SyncStabilityGateStatus.failing;
    }
    return SyncStabilityGateStatus.passing;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'window_start': windowStart?.toIso8601String(),
    'window_end': windowEnd?.toIso8601String(),
    'sample_count': cycleCount,
    'successful_cycles': successfulCycles,
    'failed_cycles': failedCycles,
    'retryable_failures': retryableFailures,
    'fatal_failures': fatalFailures,
    'local_wins': localWins,
    'ignored_rows': ignoredRows,
    'generation_resets': generationResets,
    'generation_reset_failures': generationResetFailures,
    'recovered_cycles': recoveredCycles,
    'observed_duration_hours': observedDuration.inHours,
    'success_rate': successRate,
    'minimum_samples': minimumSamples,
    'minimum_success_rate': minimumSuccessRate,
    'minimum_window_hours': minimumWindowDuration.inHours,
    'remaining_samples': remainingSamples,
    'remaining_window_hours': remainingWindowDuration.inHours,
    'gate_issues': gateIssues.map((issue) => issue.name).toList(),
    'gate_status': gateStatus.name,
  };
}

abstract interface class SyncStabilityRecorder {
  Future<void> record(SyncStabilitySample sample);
}

class DriftSyncStabilityStore implements SyncStabilityRecorder {
  DriftSyncStabilityStore(
    this._db, {
    required this.ownerUserId,
    this.retentionDays = kSyncStabilityRetentionDays,
  }) : assert(retentionDays >= 15);

  final AppDatabase _db;
  final String ownerUserId;
  final int retentionDays;
  String get _storageKey =>
      'sync.stability.daily.${base64Url.encode(utf8.encode(ownerUserId))}';

  Future<Map<String, Object?>> _read() async {
    final row = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: <Variable<Object>>[Variable.withString(_storageKey)],
        )
        .getSingleOrNull();
    if (row == null) return {};
    try {
      final decoded = jsonDecode(row.read<String>('value'));
      return decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  List<SyncStabilityBucket> _buckets(Map<String, Object?> record) {
    final raw = record['days'];
    if (raw is! List<Object?>) return [];
    return raw
        .map(SyncStabilityBucket.tryParse)
        .whereType<SyncStabilityBucket>()
        .toList()
      ..sort((a, b) => a.firstAt.compareTo(b.firstAt));
  }

  Future<SyncStabilityReport> readReport() async =>
      SyncStabilityReport.fromBuckets(buckets: _buckets(await _read()));

  @override
  Future<void> record(SyncStabilitySample sample) => _db.transaction(() async {
    final previous = await _read();
    final buckets = {
      for (final bucket in _buckets(previous)) bucket.day: bucket,
    };
    final latest = DateTime.tryParse(previous['latest_at'] as String? ?? '')
        ?.toUtc();
    final at = sample.at.toUtc();
    final newest = latest != null && latest.isAfter(at) ? latest : at;
    final cutoff = DateTime.utc(
      newest.year,
      newest.month,
      newest.day,
    ).subtract(Duration(days: retentionDays - 1));
    if (at.isBefore(cutoff)) return;
    // Recovery counts follow completed-cycle order. The engine serializes
    // cycles; delayed timestamps do not alter the observed outcome sequence.
    final bucket = SyncStabilityBucket.sample(
      sample,
      recovered: previous['last_success'] == false && sample.success,
    );
    buckets[bucket.day] = buckets[bucket.day]?.merge(bucket) ?? bucket;
    final retained =
        buckets.values.where((b) => !b.lastAt.isBefore(cutoff)).toList()
          ..sort((a, b) => a.firstAt.compareTo(b.firstAt));
    await _db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [
        _storageKey,
        jsonEncode({
          'latest_at': newest.toIso8601String(),
          'last_success': sample.success,
          'days': [for (final day in retained) day.toJson()],
        }),
      ],
    );
  });
}

int _nonNegativeInt(Object? value) => value is int && value >= 0 ? value : 0;
