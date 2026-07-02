import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test(
    'writes watchlist items through ProviderContainer and sync outbox',
    () async {
      final db = makeTestDatabase();
      final outbox = InMemoryOutboxStore();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          outboxStoreProvider.overrideWith((_) async => outbox),
          mutationStamperProvider.overrideWith((_) async => makeStubStamper()),
          currentUserIdProvider.overrideWith(
            (_) =>
                () async => 'u-test',
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);

      final repo = await container.read(watchlistRepositoryProvider.future);
      final item = await repo.add(
        symbol: 'aapl',
        market: AssetMarket.usStock,
        rules: PriceAlertRules(above: Decimal.parse('200')),
      );

      expect(item.id, 'us_stock:AAPL');
      expect(item.alertRules.above, Decimal.parse('200'));
      expect(await repo.listActive('u-test'), hasLength(1));

      var ops = outbox.queued;
      expect(ops.single.table, 'watchlist_items');
      expect(ops.single.rowId, 'us_stock:AAPL');

      await repo.updateAlertRules(
        item: item,
        rules: PriceAlertRules(below: Decimal.parse('150')),
      );
      await repo.remove(item);

      expect(await repo.listActive('u-test'), isEmpty);
      ops = outbox.queued;
      // insert + update + delete each enqueue one dirty pointer at the same
      // row.
      expect(ops, hasLength(3));
      expect(
        ops.every((o) => o.table == 'watchlist_items' && o.rowId == item.id),
        isTrue,
      );
    },
  );
}
