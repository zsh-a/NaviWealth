// Integration test (real Drift): an asset write raises the dashboard
// net-worth read model — the positive-side counterpart to
// liability_net_worth_integration_test. A term deposit created through the
// real ManualAssetRepository records an append-only valuation observation
// that flows through the prices table → ManualAssetValuation →
// DashboardAggregator.
//
// See docs/testing-strategy.md §4 "Integration (real chain)".

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';

import 'support/integration_env.dart';

void main() {
  group('Integration: asset moves net worth (real Drift)', () {
    test(
      'a 50k CNY term deposit drives net worth to +50k',
      () async {
        final env = await IntegrationEnv.create();

        // Deposits belong to a ledger account; create one first.
        final accountRepo =
            await env.container.read(accountRepositoryProvider.future);
        final account = await accountRepo.create(
          type: AccountCategory.bank,
          name: 'Deposits',
          currency: 'CNY',
        );

        final assetRepo =
            await env.container.read(manualAssetRepositoryProvider.future);
        await assetRepo.createDeposit(
          accountId: account.id,
          type: AssetType.bankDepositTerm,
          name: 'Term Deposit',
          currency: 'CNY', // matches kDefaultBaseCurrency → no FX needed
          principal: Decimal.fromInt(50000),
          interestRate: Decimal.zero,
          currentValuation: Decimal.fromInt(50000),
        );

        // Keep the chain alive: manual assets + the price observations the
        // valuation read model folds in.
        env.keepAlive(manualAssetsStreamProvider);
        env.keepAlive(dashboardPriceRowsProvider);
        env.keepAlive(dashboardSnapshotProvider);

        final snapshot =
            await env.container.read(dashboardSnapshotProvider.future);

        expect(snapshot.totalAssets.amount.toDouble(), 50000.0);
        expect(snapshot.totalLiabilities.amount.toDouble(), 0.0);
        expect(snapshot.netWorth.amount.toDouble(), 50000.0);
      },
      tags: 'integration',
    );
  });
}
