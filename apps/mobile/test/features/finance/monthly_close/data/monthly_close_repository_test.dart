import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/monthly_close/data/monthly_close_repository.dart';
import 'package:naviwealth/features/finance/monthly_close/domain/monthly_close.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late MonthlyCloseRepository repository;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = MonthlyCloseRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() => db.close());

  test('verified evidence closes and preserves its snapshot', () async {
    final evidence = _evidence(MonthlyCloseStepState.verified);
    final closed = await repository.close(
      periodMonth: '2026-07',
      evidence: evidence,
      snapshot: const <String, Object?>{'open_inbox_count': 0},
      now: DateTime.utc(2026, 7, 31),
    );

    expect(closed.isClosed, isTrue);
    expect(closed.evidence.isVerified, isTrue);
    expect(closed.snapshot['open_inbox_count'], 0);
    expect(await outbox.depth(), 1);
  });

  test('blocked evidence requires and records an explicit override', () async {
    final evidence = _evidence(MonthlyCloseStepState.blocked);
    expect(
      () => repository.close(
        periodMonth: '2026-07',
        evidence: evidence,
        snapshot: const <String, Object?>{},
        now: DateTime.utc(2026, 7, 31),
      ),
      throwsStateError,
    );

    final closed = await repository.close(
      periodMonth: '2026-07',
      evidence: evidence,
      snapshot: const <String, Object?>{},
      overrideReason: 'Statement pending',
      now: DateTime.utc(2026, 7, 31),
    );
    expect(closed.status, 'overridden');
    expect(closed.overrideReason, 'Statement pending');
  });

  test(
    'begin makes close duration resumable and exposes previous close',
    () async {
      final evidence = _evidence(MonthlyCloseStepState.verified);
      final startedAt = DateTime.utc(2026, 7, 1, 10);
      final started = await repository.begin(
        periodMonth: '2026-07',
        evidence: evidence,
        snapshot: const <String, Object?>{},
        now: startedAt,
      );
      final repeated = await repository.begin(
        periodMonth: '2026-07',
        evidence: evidence,
        snapshot: const <String, Object?>{},
        now: startedAt.add(const Duration(hours: 1)),
      );

      expect(repeated.id, started.id);
      expect(repeated.startedAt.isAtSameMomentAs(startedAt), isTrue);
      await repository.close(
        periodMonth: '2026-07',
        evidence: evidence,
        snapshot: const <String, Object?>{'close_duration_ms': 600000},
        now: startedAt.add(const Duration(minutes: 10)),
      );
      final previous = await repository.watchPreviousClosed('2026-08').first;
      expect(previous?.periodMonth, '2026-07');
      expect(previous?.snapshot['close_duration_ms'], 600000);
      expect(await outbox.depth(), 2);
    },
  );

  test('comparison reports only signal changes since previous close', () {
    final previous = MonthlyClose(
      id: 'close-1',
      periodMonth: '2026-06',
      evidence: _evidence(MonthlyCloseStepState.verified),
      snapshot: const <String, Object?>{
        'active_signal_keys': ['old', 'shared'],
        'close_duration_ms': 120000,
      },
      status: 'closed',
      startedAt: DateTime.utc(2026, 6, 30),
      closedAt: DateTime.utc(2026, 6, 30, 0, 2),
    );
    final current = MonthlyCloseEvidence(
      states: <MonthlyCloseStep, MonthlyCloseStepState>{
        for (final step in MonthlyCloseStep.values)
          step: MonthlyCloseStepState.verified,
      },
      details: const <String, Object?>{
        'active_signal_keys': ['shared', 'new'],
      },
    );

    final comparison = compareMonthlyCloseEvidence(
      current: current,
      previous: previous,
    );
    expect(comparison.newSignalKeys, {'new'});
    expect(comparison.clearedSignalKeys, {'old'});
    expect(comparison.previousDuration, const Duration(minutes: 2));
  });
}

MonthlyCloseEvidence _evidence(MonthlyCloseStepState state) =>
    MonthlyCloseEvidence(
      states: <MonthlyCloseStep, MonthlyCloseStepState>{
        for (final step in MonthlyCloseStep.values) step: state,
      },
      details: const <String, Object?>{},
    );
