import 'dart:convert';

import 'package:drift/drift.dart';

import '../persistence/app_database.dart';

const kSyncStabilityWindowSize = 50;

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

  Map<String, Object> toJson() => <String, Object>{
    'at': at.toUtc().toIso8601String(),
    'success': success,
    'retryable_failures': retryableFailures,
    'fatal_failures': fatalFailures,
    'local_wins': localWins,
    'ignored_rows': ignoredRows,
    'generation_resets': generationResets,
    'generation_reset_failures': generationResetFailures,
  };

  static SyncStabilitySample? tryParse(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final at = DateTime.tryParse(value['at'] as String? ?? '');
    final success = value['success'];
    if (at == null || success is! bool) return null;
    return SyncStabilitySample(
      at: at.toUtc(),
      success: success,
      retryableFailures: _nonNegativeInt(value['retryable_failures']),
      fatalFailures: _nonNegativeInt(value['fatal_failures']),
      localWins: _nonNegativeInt(value['local_wins']),
      ignoredRows: _nonNegativeInt(value['ignored_rows']),
      generationResets: _nonNegativeInt(value['generation_resets']),
      generationResetFailures: _nonNegativeInt(
        value['generation_reset_failures'],
      ),
    );
  }
}

enum SyncStabilityGateStatus { insufficientData, passing, failing }

enum SyncStabilityGateIssue {
  insufficientSamples,
  insufficientDuration,
  successRateBelowMinimum,
  fatalFailures,
  generationResetFailures,
}

class SyncStabilityReport {
  SyncStabilityReport({
    required List<SyncStabilitySample> samples,
    this.minimumSamples = 10,
    this.minimumSuccessRate = 0.95,
    this.minimumWindowDuration = const Duration(days: 14),
  }) : samples = List<SyncStabilitySample>.unmodifiable(
         List<SyncStabilitySample>.of(samples)
           ..sort((a, b) => a.at.compareTo(b.at)),
       );

  final List<SyncStabilitySample> samples;
  final int minimumSamples;
  final double minimumSuccessRate;
  final Duration minimumWindowDuration;

  int get successfulCycles => samples.where((item) => item.success).length;
  int get failedCycles => samples.length - successfulCycles;
  int get retryableFailures =>
      samples.fold(0, (sum, item) => sum + item.retryableFailures);
  int get fatalFailures =>
      samples.fold(0, (sum, item) => sum + item.fatalFailures);
  int get localWins => samples.fold(0, (sum, item) => sum + item.localWins);
  int get ignoredRows => samples.fold(0, (sum, item) => sum + item.ignoredRows);
  int get generationResets =>
      samples.fold(0, (sum, item) => sum + item.generationResets);
  int get generationResetFailures =>
      samples.fold(0, (sum, item) => sum + item.generationResetFailures);
  int get recoveredCycles {
    var count = 0;
    for (var index = 1; index < samples.length; index++) {
      if (!samples[index - 1].success && samples[index].success) count++;
    }
    return count;
  }

  Duration get observedDuration => samples.length < 2
      ? Duration.zero
      : samples.last.at.difference(samples.first.at).abs();
  double get successRate =>
      samples.isEmpty ? 0 : successfulCycles / samples.length;

  DateTime? get windowStart =>
      samples.isEmpty ? null : samples.first.at.toUtc();
  DateTime? get windowEnd => samples.isEmpty ? null : samples.last.at.toUtc();
  int get remainingSamples {
    final remaining = minimumSamples - samples.length;
    return remaining > 0 ? remaining : 0;
  }

  Duration get remainingWindowDuration {
    final remaining = minimumWindowDuration - observedDuration;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  List<SyncStabilityGateIssue> get gateIssues => <SyncStabilityGateIssue>[
    if (samples.length < minimumSamples)
      SyncStabilityGateIssue.insufficientSamples,
    if (observedDuration < minimumWindowDuration)
      SyncStabilityGateIssue.insufficientDuration,
    if (samples.isNotEmpty && successRate < minimumSuccessRate)
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
    'sample_count': samples.length,
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
    this.windowSize = kSyncStabilityWindowSize,
  });

  static const _storageKey = 'sync.stability.samples.v1';

  final AppDatabase _db;
  final int windowSize;

  Future<List<SyncStabilitySample>> readSamples() async {
    final row = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: <Variable<Object>>[Variable.withString(_storageKey)],
        )
        .getSingleOrNull();
    final encoded = row?.read<String>('value');
    if (encoded == null) return const <SyncStabilitySample>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) return const <SyncStabilitySample>[];
      return decoded
          .map(SyncStabilitySample.tryParse)
          .whereType<SyncStabilitySample>()
          .toList(growable: false);
    } on FormatException {
      return const <SyncStabilitySample>[];
    }
  }

  Future<SyncStabilityReport> readReport() async {
    return SyncStabilityReport(samples: await readSamples());
  }

  @override
  Future<void> record(SyncStabilitySample sample) async {
    final samples = <SyncStabilitySample>[...await readSamples(), sample]
      ..sort((a, b) => a.at.compareTo(b.at));
    final retained = samples.length <= windowSize
        ? samples
        : samples.sublist(samples.length - windowSize);
    await _db.customStatement(
      '''
      INSERT INTO sync_meta(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      <Object?>[
        _storageKey,
        jsonEncode(retained.map((item) => item.toJson()).toList()),
      ],
    );
  }
}

int _nonNegativeInt(Object? value) => value is int && value >= 0 ? value : 0;
