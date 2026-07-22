import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/investment/data/dca_plan_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/dca/dca_simulator.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test(
    'persists, advances, pauses, and removes a recurring DCA plan',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = DcaPlanRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(),
      );
      final due = DateTime.utc(2026, 7, 22);

      final created = await repository.create(
        allocations: [
          DcaAllocation(symbol: 'VOO', weight: Decimal.parse('0.6')),
          DcaAllocation(symbol: 'QQQ', weight: Decimal.parse('0.4')),
        ],
        amountPerContribution: Decimal.fromInt(1000),
        currency: 'usd',
        market: AssetMarket.usStock,
        frequency: DcaFrequency.monthly,
        nextDueAt: due,
      );

      expect(created.currency, 'USD');
      expect(created.allocations.map((item) => item.symbol), ['VOO', 'QQQ']);
      expect(await repository.watchAll().first, hasLength(1));

      await repository.markExecuted(created, due);
      final advanced = (await repository.watchAll().first).single;
      expect(advanced.lastExecutedAt?.toUtc(), due);
      expect(advanced.nextDueAt.toUtc(), DateTime.utc(2026, 8, 22));

      await repository.setEnabled(advanced, false);
      final paused = (await repository.watchAll().first).single;
      expect(paused.enabled, isFalse);

      await repository.remove(paused);
      expect(await repository.watchAll().first, isEmpty);
    },
  );
}
