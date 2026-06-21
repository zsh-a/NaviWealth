import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/investment/data/corporate_action_repository.dart';
import 'package:naviwealth/features/investment/domain/models/corporate_actions.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';
import '../../../features/finance/data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late CorporateActionRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = CorporateActionRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'round-trips every corporate action kind and queues sync rows',
    () async {
      final actions = <CorporateAction>[
        CashDividendAction(
          id: 'cash-1',
          assetId: 'us_stock:AAPL',
          effectiveDate: DateTime.utc(2026, 1, 10),
          transactionId: 'tx-cash-1',
          accountId: 'brokerage:ibkr',
          currency: 'USD',
          amountPerShare: Decimal.parse('0.25'),
          withholdingTax: Decimal.parse('1.50'),
        ),
        StockDividendAction(
          id: 'stock-1',
          assetId: 'hk_stock:00700',
          effectiveDate: DateTime.utc(2026, 2, 10),
          bonusRatio: Decimal.parse('0.1'),
        ),
        SplitAction(
          id: 'split-1',
          assetId: 'us_stock:NVDA',
          effectiveDate: DateTime.utc(2026, 3, 10),
          ratio: Decimal.parse('10'),
        ),
        RightsIssueAction(
          id: 'rights-1',
          assetId: 'hk_stock:00005',
          effectiveDate: DateTime.utc(2026, 4, 10),
          transactionId: 'tx-rights-1',
          accountId: 'brokerage:hk',
          currency: 'HKD',
          subscribedQuantity: Decimal.parse('100'),
          pricePerUnit: Decimal.parse('12.34'),
          fee: Decimal.parse('8'),
        ),
        DripAction(
          id: 'drip-1',
          assetId: 'us_stock:SCHD',
          effectiveDate: DateTime.utc(2026, 5, 10),
          transactionId: 'tx-drip-1',
          accountId: 'brokerage:ibkr',
          currency: 'USD',
          amountPerShare: Decimal.parse('0.72'),
          pricePerUnit: Decimal.parse('75.12'),
          withholdingTax: Decimal.parse('0.30'),
          fee: Decimal.zero,
        ),
      ];

      for (final action in actions) {
        await repo.upsert(action);
      }

      final stored = await repo.listDeclared('u-test');
      expect(stored.map((a) => a.id).toSet(), actions.map((a) => a.id).toSet());
      expect(stored.first.id, 'drip-1');
      expect(stored.last.id, 'cash-1');
      final byId = {for (final action in stored) action.id: action};
      expect(byId['cash-1'], isA<CashDividendAction>());
      expect(
        (byId['cash-1']! as CashDividendAction).amountPerShare,
        Decimal.parse('0.25'),
      );
      expect(byId['stock-1'], isA<StockDividendAction>());
      expect(
        (byId['stock-1']! as StockDividendAction).bonusRatio,
        Decimal.parse('0.1'),
      );
      expect(byId['split-1'], isA<SplitAction>());
      expect((byId['split-1']! as SplitAction).ratio, Decimal.parse('10'));
      expect(byId['rights-1'], isA<RightsIssueAction>());
      expect(
        (byId['rights-1']! as RightsIssueAction).subscribedQuantity,
        Decimal.parse('100'),
      );
      expect(byId['drip-1'], isA<DripAction>());
      expect(
        (byId['drip-1']! as DripAction).pricePerUnit,
        Decimal.parse('75.12'),
      );

      final ops = outbox.queued;
      expect(ops, hasLength(actions.length));
      expect(ops.every((op) => op.table == 'corporate_actions'), isTrue);
      expect(
        ops.map((op) => op.rowId).toSet(),
        actions.map((a) => a.id).toSet(),
      );
    },
  );

  test('upsert replaces the existing business record by id', () async {
    final original = CashDividendAction(
      id: 'cash-1',
      assetId: 'us_stock:AAPL',
      effectiveDate: DateTime.utc(2026, 1, 10),
      transactionId: 'tx-cash-1',
      accountId: 'brokerage:ibkr',
      currency: 'USD',
      amountPerShare: Decimal.parse('0.25'),
      withholdingTax: Decimal.zero,
    );
    final corrected = CashDividendAction(
      id: original.id,
      assetId: original.assetId,
      effectiveDate: original.effectiveDate,
      transactionId: original.transactionId,
      accountId: original.accountId,
      currency: original.currency,
      amountPerShare: Decimal.parse('0.30'),
      withholdingTax: Decimal.parse('0.01'),
    );

    await repo.upsert(original);
    await repo.upsert(corrected);

    final stored = await repo.listDeclared('u-test');
    expect(stored, hasLength(1));
    final action = stored.single as CashDividendAction;
    expect(action.id, corrected.id);
    expect(action.amountPerShare, Decimal.parse('0.30'));
    expect(action.withholdingTax, Decimal.parse('0.01'));
    expect(outbox.queued, hasLength(2));
    expect(outbox.queued.every((op) => op.rowId == 'cash-1'), isTrue);
  });
}
