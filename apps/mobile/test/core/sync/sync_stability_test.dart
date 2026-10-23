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

  SyncStabilitySample cycle(
    DateTime at, {
    bool success = true,
    int fatal = 0,
  }) => SyncStabilitySample(
    at: at,
    success: success,
    retryableFailures: success ? 0 : 1,
    fatalFailures: fatal,
    localWins: 0,
    ignoredRows: 0,
    generationResets: 0,
    generationResetFailures: 0,
  );

  test(
    'frequent polling preserves fourteen-day evidence and exact rates',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = DriftSyncStabilityStore(db, ownerUserId: 'user-1');
      final start = DateTime.utc(2026, 7, 1);
      await store.record(cycle(start));
      for (var i = 0; i < 120; i++) {
        await store.record(
          cycle(
            start.add(Duration(days: 15, seconds: i * 30)),
            success: i != 0,
          ),
        );
      }
      final report = await store.readReport();
      expect(report.buckets.length, 2);
      expect(report.cycleCount, 121);
      expect(report.successfulCycles, 120);
      expect(report.failedCycles, 1);
      expect(report.recoveredCycles, 1);
      expect(report.observedDuration.inDays, 15);
      expect(report.gateStatus, SyncStabilityGateStatus.passing);
      expect(report.toJson()['sample_count'], 121);
      expect(report.toJson().toString(), isNot(contains('user-1')));
    },
  );

  test(
    'retention bounds days without losing failures inside the window',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = DriftSyncStabilityStore(db, ownerUserId: 'user-1');
      final start = DateTime.utc(2026, 7, 1);
      for (var day = 0; day < 40; day++) {
        await store.record(cycle(start.add(Duration(days: day))));
      }
      await store.record(
        cycle(start.add(const Duration(days: 15)), success: false, fatal: 1),
      );
      await store.record(cycle(start)); // delayed, outside retention
      final report = await store.readReport();
      expect(report.buckets.length, 30);
      expect(report.cycleCount, 31);
      expect(report.fatalFailures, 1);
      expect(report.windowStart, start.add(const Duration(days: 10)));
      expect(report.windowEnd, start.add(const Duration(days: 39)));
      expect(report.gateStatus, SyncStabilityGateStatus.failing);
    },
  );

  test(
    'concurrent recording is atomic and owners never share evidence',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final first = DriftSyncStabilityStore(db, ownerUserId: 'first');
      final second = DriftSyncStabilityStore(db, ownerUserId: 'second');
      await Future.wait([
        for (var i = 0; i < 20; i++)
          first.record(cycle(DateTime.utc(2026, 7, 1, 0, i))),
      ]);
      await second.record(
        cycle(DateTime.utc(2026, 7, 1), success: false, fatal: 1),
      );
      expect((await first.readReport()).cycleCount, 20);
      expect((await first.readReport()).fatalFailures, 0);
      expect((await second.readReport()).cycleCount, 1);
      expect((await second.readReport()).fatalFailures, 1);
    },
  );
}
