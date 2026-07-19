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

  test('month closes only after every evidence step is complete', () async {
    for (final step in MonthlyCloseStep.values) {
      await repository.toggleStep(
        periodMonth: '2026-07',
        step: step,
        now: DateTime.utc(2026, 7, 19),
      );
    }
    final closed = await repository.close(
      periodMonth: '2026-07',
      now: DateTime.utc(2026, 7, 31),
    );

    expect(closed.isComplete, isTrue);
    expect(closed.closedAt, isNotNull);
    expect(await outbox.depth(), MonthlyCloseStep.values.length + 1);
  });
}
