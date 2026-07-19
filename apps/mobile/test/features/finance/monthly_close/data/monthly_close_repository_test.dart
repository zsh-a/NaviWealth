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
}

MonthlyCloseEvidence _evidence(MonthlyCloseStepState state) =>
    MonthlyCloseEvidence(
      states: <MonthlyCloseStep, MonthlyCloseStepState>{
        for (final step in MonthlyCloseStep.values) step: state,
      },
      details: const <String, Object?>{},
    );
