// Integration test (real Drift): account persistence + the dashboard
// net-worth read model. This is the seed of the "Integration (real chain)"
// layer in docs/development/testing-strategy.md §4 — it runs the production provider
// graph (repository → Drift → stream providers → DashboardAggregator)
// against a real in-memory database, faking only auth + the HLC stamper.
//
// Tagged `integration` so the suite can be split from the unit gate.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';

import 'support/integration_env.dart';

void main() {
  group('Integration: account + net-worth read model (real Drift)', () {
    test(
      'a created account is durable and visible through the live stream',
      () async {
        final env = await IntegrationEnv.create();
        final repo = await env.container.read(accountRepositoryProvider.future);

        final account = await repo.create(
          type: AccountCategory.bank,
          name: 'Schwab',
          currency: 'USD',
        );

        // Direct read-back through the real Drift query.
        final listed = await repo.listActive();
        expect(
          listed.map((a) => a.id),
          contains(account.id),
          reason: 'created account should persist in the accounts table',
        );

        // ...and through the production stream-provider chain the UI watches.
        env.keepAlive(accountsStreamProvider);
        final streamed = await env.container.read(accountsStreamProvider.future);
        expect(
          streamed.map((a) => a.name),
          contains('Schwab'),
          reason: 'accountsStreamProvider should emit the new account',
        );
      },
      tags: 'integration',
    );

    test(
      'dashboard net-worth read model resolves to zero for an empty ledger',
      () async {
        final env = await IntegrationEnv.create();

        // Exercises the full read model: stream providers → currency
        // converter → DashboardAggregator, all against the real DB.
        env.keepAlive(dashboardSnapshotProvider);
        final snapshot = await env.container.read(dashboardSnapshotProvider.future);

        expect(snapshot.netWorth.amount.toDouble(), 0.0);
        expect(snapshot.totalAssets.amount.toDouble(), 0.0);
        expect(snapshot.totalLiabilities.amount.toDouble(), 0.0);
      },
      tags: 'integration',
    );
  });
}
