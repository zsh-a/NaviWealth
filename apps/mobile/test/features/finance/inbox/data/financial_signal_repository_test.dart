import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/inbox/data/financial_signal_repository.dart';
import 'package:naviwealth/features/finance/inbox/domain/financial_inbox.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late FinancialSignalRepository repository;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = FinancialSignalRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() => db.close());

  test('resolved signal reopens only when evidence changes', () async {
    const original = FinancialSignalCandidate(
      sourceKey: 'runway-risk',
      kind: FinancialInboxKind.runwayRisk,
      priority: FinancialInboxPriority.important,
      count: 1,
      route: '/plan/runway',
      evidence: {'balance': '-100'},
    );
    final first = await repository.reconcile([
      original,
    ], now: DateTime.utc(2026, 7, 1));
    expect(first, hasLength(1));
    await repository.resolve(first.single.id, now: DateTime.utc(2026, 7, 2));

    final unchanged = await repository.reconcile([
      original,
    ], now: DateTime.utc(2026, 7, 3));
    expect(unchanged, isEmpty);

    final changed = await repository.reconcile(const [
      FinancialSignalCandidate(
        sourceKey: 'runway-risk',
        kind: FinancialInboxKind.runwayRisk,
        priority: FinancialInboxPriority.important,
        count: 1,
        route: '/plan/runway',
        evidence: {'balance': '-200'},
      ),
    ], now: DateTime.utc(2026, 7, 4));
    expect(changed, hasLength(1));
    expect(await outbox.depth(), 3);
  });
}
