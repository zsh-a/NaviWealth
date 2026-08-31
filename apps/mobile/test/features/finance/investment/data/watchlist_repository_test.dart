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
      final restored = await repo.add(
        symbol: item.symbol,
        market: item.market,
        rules: item.alertRules,
      );
      expect(restored.id, item.id);
      expect(restored.alertRules.above, Decimal.parse('200'));
      expect(await repo.listActive('u-test'), hasLength(1));
      ops = outbox.queued;
      // Insert + update + delete + restore each enqueue one dirty pointer at
      // the same row.
      expect(ops, hasLength(4));
      expect(
        ops.every((o) => o.table == 'watchlist_items' && o.rowId == item.id),
        isTrue,
      );
    },
  );

  test(
    'syncs collections and preserves memberships across item undo',
    () async {
      final db = makeTestDatabase();
      final outbox = InMemoryOutboxStore();
      final repo = WatchlistRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
      );
      addTearDown(db.close);

      final growth = await repo.createCollection('Growth');
      final income = await repo.createCollection('Income');
      final item = await repo.add(
        symbol: 'aapl',
        market: AssetMarket.usStock,
        collectionIds: [growth.id, income.id],
      );

      expect(await repo.watchCollections('u-test').first, hasLength(2));
      var members = await repo.watchCollectionMembers('u-test').first;
      expect(members.map((entry) => entry.collectionId).toSet(), {
        growth.id,
        income.id,
      });
      expect(members.map((entry) => entry.id).toSet(), hasLength(2));
      expect(
        outbox.queued.map((entry) => entry.table),
        containsAll(<String>[
          'watchlist_collections',
          'watchlist_items',
          'watchlist_collection_members',
        ]),
      );

      await repo.setCollectionsForItem(item: item, collectionIds: {growth.id});
      members = await repo.watchCollectionMembers('u-test').first;
      expect(members.single.collectionId, growth.id);

      final removedCollectionIds = await repo.remove(item);
      expect(removedCollectionIds, [growth.id]);
      expect(await repo.watchCollectionMembers('u-test').first, isEmpty);

      await repo.add(
        symbol: item.symbol,
        market: item.market,
        collectionIds: removedCollectionIds,
      );
      members = await repo.watchCollectionMembers('u-test').first;
      expect(members.single.collectionId, growth.id);

      await repo.deleteCollection(growth);
      expect(await repo.watchCollectionMembers('u-test').first, isEmpty);
      expect(
        (await repo.watchCollections('u-test').first).map(
          (entry) => entry.name,
        ),
        ['Income'],
      );
      expect(await repo.listActive('u-test'), hasLength(1));
    },
  );

  test('adds and removes multiple collection memberships atomically', () async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final repo = WatchlistRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);

    final collection = await repo.createCollection('Batch');
    final aapl = await repo.add(symbol: 'AAPL', market: AssetMarket.usStock);
    final msft = await repo.add(symbol: 'MSFT', market: AssetMarket.usStock);

    await repo.addItemsToCollection(
      items: [aapl, msft],
      collectionId: collection.id,
    );
    var members = await repo.watchCollectionMembers('u-test').first;
    expect(members.map((member) => member.watchlistItemId).toSet(), {
      aapl.id,
      msft.id,
    });

    await repo.removeItemsFromCollection(
      items: [aapl, msft],
      collectionId: collection.id,
    );
    members = await repo.watchCollectionMembers('u-test').first;
    expect(members, isEmpty);
    expect(
      outbox.queued.where(
        (entry) => entry.table == 'watchlist_collection_members',
      ),
      hasLength(4),
    );
  });

  test('persists complete collection and member orderings', () async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final repo = WatchlistRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
    addTearDown(db.close);

    final growth = await repo.createCollection('Growth');
    final income = await repo.createCollection('Income');
    final aapl = await repo.add(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      collectionIds: [growth.id],
    );
    final msft = await repo.add(
      symbol: 'MSFT',
      market: AssetMarket.usStock,
      collectionIds: [growth.id],
    );

    await expectLater(repo.reorderCollections([growth]), throwsStateError);
    await expectLater(repo.reorderCollections(const []), throwsStateError);

    await repo.reorderCollections([income, growth]);
    final collections = await repo.watchCollections('u-test').first;
    expect(collections.map((entry) => entry.name), ['Income', 'Growth']);
    expect(collections.map((entry) => entry.sortRank), [0, 1024]);

    await expectLater(
      repo.reorderItemsInCollection(
        collectionId: growth.id,
        orderedItems: [aapl],
      ),
      throwsStateError,
    );
    await expectLater(
      repo.reorderItemsInCollection(
        collectionId: growth.id,
        orderedItems: const [],
      ),
      throwsStateError,
    );

    await repo.reorderItemsInCollection(
      collectionId: growth.id,
      orderedItems: [msft, aapl],
    );
    final members = await repo.watchCollectionMembers('u-test').first;
    expect(members.map((entry) => entry.watchlistItemId), [msft.id, aapl.id]);
    expect(members.map((entry) => entry.sortRank), [0, 1024]);
  });
}
