import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test('rebalance picker providers never emit foreign rows', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final outbox = InMemoryOutboxStore();
    final ownerAccounts = AccountRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'owner-a'),
    );
    final foreignAccounts = AccountRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'owner-b'),
    );
    final ownerAssets = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'owner-a'),
    );
    final foreignAssets = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'owner-b'),
    );
    await ownerAccounts.create(
      type: AccountCategory.broker,
      name: 'Owner Broker',
      currency: 'USD',
    );
    await foreignAccounts.create(
      type: AccountCategory.broker,
      name: 'Foreign Secret Broker',
      currency: 'USD',
    );
    await ownerAssets.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Owner Apple',
    );
    await foreignAssets.upsertSecurity(
      symbol: 'MSFT',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Foreign Secret Microsoft',
    );
    final container = ProviderContainer(
      overrides: [
        activeUserIdProvider.overrideWithValue('owner-a'),
        accountRepositoryProvider.overrideWith((_) async => ownerAccounts),
        securitiesAssetRepositoryProvider.overrideWith(
          (_) async => ownerAssets,
        ),
      ],
    );
    addTearDown(container.dispose);

    final accountsSubscription = container.listen(
      rebalanceOwnedAccountsProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final assetsSubscription = container.listen(
      rebalanceOwnedSecuritiesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(accountsSubscription.close);
    addTearDown(assetsSubscription.close);
    final accounts = await container.read(
      rebalanceOwnedAccountsProvider.future,
    );
    final assets = await container.read(
      rebalanceOwnedSecuritiesProvider.future,
    );

    expect(accounts.map((account) => account.name), ['Owner Broker']);
    expect(assets.map((asset) => asset.symbol), ['AAPL']);
    expect(
      accounts.map((account) => account.name),
      isNot(contains('Foreign Secret Broker')),
    );
    expect(
      assets.map((asset) => asset.name),
      isNot(contains('Foreign Secret Microsoft')),
    );
  });
}
