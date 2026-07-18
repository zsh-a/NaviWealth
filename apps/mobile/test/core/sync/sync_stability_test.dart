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
    }) {
      return SyncStabilitySample(
        at: at,
        success: success,
        retryableFailures: success || fatal > 0 ? 0 : 1,
        fatalFailures: fatal,
        localWins: 0,
        ignoredRows: 0,
        generationResets: 0,
        generationResetFailures: 0,
      );
    }

    List<SyncStabilitySample> samples(int count) => List.generate(
      count,
      (index) => sample(at: now.add(Duration(days: index * 2))),
    );

    expect(
      SyncStabilityReport(samples: samples(9)).gateStatus,
      SyncStabilityGateStatus.insufficientData,
    );
    expect(
      SyncStabilityReport(samples: samples(20)).gateStatus,
      SyncStabilityGateStatus.passing,
    );
    expect(
      SyncStabilityReport(
        samples: <SyncStabilitySample>[
          ...samples(19),
          sample(
            at: now.add(const Duration(days: 38)),
            success: false,
            fatal: 1,
          ),
        ],
      ).gateStatus,
      SyncStabilityGateStatus.failing,
    );
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
    expect(
      (await store.readReport()).toJson().toString(),
      isNot(contains('id')),
    );
  });
}
