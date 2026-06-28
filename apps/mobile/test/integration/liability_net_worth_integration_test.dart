// Integration test (real Drift): a liability write moves the dashboard
// net-worth read model. Where account_net_worth_integration_test proves
// the chain resolves for an empty ledger, this proves it *reacts* to data —
// the strongest signal that repository → Drift → amortization schedule →
// LiabilitySummary → DashboardAggregator is wired end to end.
//
// See docs/development/testing-strategy.md §4 "Integration (real chain)".

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';

import 'support/integration_env.dart';

void main() {
  group('Integration: liability moves net worth (real Drift)', () {
    test(
      'creating a 120k CNY loan drives net worth to -120k',
      () async {
        final env = await IntegrationEnv.create();
        final repo = await env.container.read(liabilityRepositoryProvider.future);

        // Zero interest + equal-principal over 12 months → the generated
        // amortization schedule's principal payments sum back to the
        // principal, so remainingPrincipal == 120000 with nothing paid.
        await repo.create(
          type: LiabilityType.consumerLoan,
          name: 'Integration Loan',
          principal: Decimal.fromInt(120000),
          interestRate: Decimal.zero,
          currency: 'CNY', // matches kDefaultBaseCurrency → no FX needed
          termMonths: 12,
          startDate: DateTime(2020, 1, 1),
          paymentMethod: RepaymentMethod.equalPrincipal,
        );

        // Keep the chain alive: the dashboard provider folds in the
        // liability stream and its per-id summary family.
        env.keepAlive(liabilitiesStreamProvider);
        env.keepAlive(dashboardSnapshotProvider);

        final snapshot =
            await env.container.read(dashboardSnapshotProvider.future);

        expect(snapshot.totalAssets.amount.toDouble(), 0.0);
        expect(snapshot.totalLiabilities.amount.toDouble(), 120000.0);
        expect(snapshot.netWorth.amount.toDouble(), -120000.0);
      },
      tags: 'integration',
    );
  });
}
