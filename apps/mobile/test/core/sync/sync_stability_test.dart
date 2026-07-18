import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/sync_stability.dart';

import '../../core/persistence/test_database.dart';

void main() {
  test('gate requires enough samples and rejects fatal failures', () {
    final now = DateTime.utc(2026, 7, 18);
    SyncStabilitySample sample({
      required DateTime at,
      bool success = true,
      int fatal = 0,
      int resetFailures = 0,
    }) {
      return SyncStabilitySample(
        at: at,
        success: success,
        retryableFailures: success || fatal > 0 ? 0 : 1,
        fatalFailures: fatal,
        localWins: 0,
        ignoredRows: 0,
        generationResets: 0,
        generationResetFailures: resetFailures,
      );
    }

    List<SyncStabilitySample> samples(int count) => List.generate(
      count,
      (index) => sample(at: now.add(Duration(days: index * 2))),
    );

    final insufficient = SyncStabilityReport(samples: samples(9));
    expect(insufficient.gateStatus, SyncStabilityGateStatus.insufficientData);
    expect(insufficient.remainingSamples, 1);
    expect(insufficient.remainingWindowDuration, Duration.zero);
    expect(insufficient.gateIssues, <SyncStabilityGateIssue>[
      SyncStabilityGateIssue.insufficientSamples,
    ]);

    final passing = SyncStabilityReport(samples: samples(20));
    expect(passing.gateStatus, SyncStabilityGateStatus.passing);
    expect(passing.gateIssues, isEmpty);

    final fatal = SyncStabilityReport(
      samples: <SyncStabilitySample>[
        ...samples(19),
        sample(at: now.add(const Duration(days: 38)), success: false, fatal: 1),
      ],
    );
    expect(fatal.gateStatus, SyncStabilityGateStatus.failing);
    expect(fatal.gateIssues, <SyncStabilityGateIssue>[
      SyncStabilityGateIssue.fatalFailures,
    ]);

    final belowSuccess = SyncStabilityReport(
      samples: <SyncStabilitySample>[
        ...samples(9),
        sample(at: now.add(const Duration(days: 18)), success: false),
      ],
    );
    expect(belowSuccess.gateStatus, SyncStabilityGateStatus.failing);
    expect(belowSuccess.gateIssues, <SyncStabilityGateIssue>[
      SyncStabilityGateIssue.successRateBelowMinimum,
    ]);

    final resetFailure = SyncStabilityReport(
      samples: <SyncStabilitySample>[
        ...samples(9),
        sample(at: now.add(const Duration(days: 18)), resetFailures: 1),
      ],
    );
    expect(resetFailure.gateIssues, <SyncStabilityGateIssue>[
      SyncStabilityGateIssue.generationResetFailures,
    ]);

    final shortWindow = SyncStabilityReport(
      samples: List<SyncStabilitySample>.generate(
        10,
        (index) => sample(at: now.add(Duration(days: index))),
      ),
    );
    expect(shortWindow.remainingSamples, 0);
    expect(shortWindow.remainingWindowDuration, const Duration(days: 5));
    expect(shortWindow.gateIssues, <SyncStabilityGateIssue>[
      SyncStabilityGateIssue.insufficientDuration,
    ]);
  });

  test('store keeps a privacy-safe bounded rolling window', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = DriftSyncStabilityStore(db, windowSize: 3);

    for (var i = 0; i < 5; i++) {
      await store.record(
        SyncStabilitySample(
          at: DateTime.utc(2026, 7, 18).add(Duration(minutes: i)),
          success: i.isEven,
          retryableFailures: i.isEven ? 0 : 1,
          fatalFailures: 0,
          localWins: i,
          ignoredRows: 0,
          generationResets: 0,
          generationResetFailures: 0,
        ),
      );
    }

    final samples = await store.readSamples();
    expect(samples, hasLength(3));
    expect(samples.first.localWins, 2);
    expect(samples.last.localWins, 4);
    final report = await store.readReport();
    expect(report.toJson().toString(), isNot(contains('id')));
    expect(
      report.toJson().keys,
      unorderedEquals(<String>{
        'window_start',
        'window_end',
        'sample_count',
        'successful_cycles',
        'failed_cycles',
        'retryable_failures',
        'fatal_failures',
        'local_wins',
        'ignored_rows',
        'generation_resets',
        'generation_reset_failures',
        'recovered_cycles',
        'observed_duration_hours',
        'success_rate',
        'minimum_samples',
        'minimum_success_rate',
        'minimum_window_hours',
        'remaining_samples',
        'remaining_window_hours',
        'gate_issues',
        'gate_status',
      }),
    );
  });

  test('store orders delayed samples before bounding the window', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = DriftSyncStabilityStore(db, windowSize: 3);
    final start = DateTime.utc(2026, 7, 1);

    for (final day in <int>[4, 0, 3, 1, 2]) {
      await store.record(
        SyncStabilitySample(
          at: start.add(Duration(days: day)),
          success: true,
          retryableFailures: 0,
          fatalFailures: 0,
          localWins: day,
          ignoredRows: 0,
          generationResets: 0,
          generationResetFailures: 0,
        ),
      );
    }

    final samples = await store.readSamples();
    expect(samples.map((sample) => sample.localWins), <int>[2, 3, 4]);
    final report = await store.readReport();
    expect(report.windowStart, start.add(const Duration(days: 2)));
    expect(report.windowEnd, start.add(const Duration(days: 4)));
  });
}
