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

  test(
    'partial detection never resolves signals from another detector',
    () async {
      final now = DateTime.utc(2026, 7, 1);
      await repository.reconcile(const [
        FinancialSignalCandidate(
          sourceKey: 'runway-risk',
          kind: FinancialInboxKind.runwayRisk,
          priority: FinancialInboxPriority.important,
          count: 1,
          route: '/plan/runway',
          evidence: {'data_completeness': 0.5},
        ),
      ], now: now);

      final visible = await repository.detectAll(const [], now: now);

      expect(visible.single.sourceKey, 'runway-risk');
    },
  );

  test('action link preserves evidence and detection timestamps', () async {
    final firstDetected = DateTime.utc(2026, 7, 1);
    final item = (await repository.reconcile(const [
      FinancialSignalCandidate(
        sourceKey: 'balance-mismatch:2026-07',
        kind: FinancialInboxKind.balanceMismatch,
        priority: FinancialInboxPriority.important,
        count: 2,
        route: '/activity/monthly-close',
        evidence: {'period': '2026-07', 'mismatch_count': 2},
      ),
    ], now: firstDetected)).single;

    await repository.linkAction(
      item.id,
      actionId: 'action-1',
      now: DateTime.utc(2026, 7, 2),
    );
    final linked = (await repository.listVisible(
      now: DateTime.utc(2026, 7, 2),
    )).single;

    expect(linked.actionId, 'action-1');
    expect(linked.count, 2);
    expect(linked.evidence['period'], '2026-07');
    expect(linked.evidence, isNot(contains('count')));
    expect(linked.firstDetectedAt.isAtSameMomentAs(firstDetected), isTrue);
    expect(linked.lastDetectedAt.isAtSameMomentAs(firstDetected), isTrue);

    await repository.detectAll([
      const FinancialSignalCandidate(
        sourceKey: 'balance-mismatch:2026-07',
        kind: FinancialInboxKind.balanceMismatch,
        priority: FinancialInboxPriority.important,
        count: 3,
        route: '/activity/monthly-close',
        evidence: {'period': '2026-07', 'mismatch_count': 3},
      ),
    ], now: DateTime.utc(2026, 7, 3));
    final redetected = (await repository.listVisible(
      now: DateTime.utc(2026, 7, 3),
    )).single;
    expect(redetected.actionId, 'action-1');
    expect(redetected.count, 3);
  });
}
