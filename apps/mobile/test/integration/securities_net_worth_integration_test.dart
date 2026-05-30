// Integration test (real Drift): a securities buy raises the dashboard
// net-worth read model. This is the deepest input path — a trade is
// recorded as double-entry postings, the HoldingService reconstructs the
// position from the ledger, and a (faked) price source values it. It
// completes the read-model coverage alongside the asset / liability tests.
//
// The live price resolver is replaced with a fixed-price fake so the test
// is deterministic and never reaches the network (docs/testing-strategy.md
// §4, §7 P1 item "securities trades").

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/domain/services/price_resolver.dart';
import 'package:naviwealth/domain/values/price_confidence.dart';
import 'package:naviwealth/domain/values/resolved_price.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

import 'support/integration_env.dart';

/// Values every asset at a fixed price — keeps the holdings pipeline
/// deterministic and offline.
class _FixedPriceResolver implements PriceResolver {
  const _FixedPriceResolver(this.price, this.currency, this.asOf);

  final Decimal price;
  final String currency;
  final DateTime asOf;

  ResolvedPrice _p() => ResolvedPrice(
        value: price,
        currency: currency,
        confidence: PriceConfidence.realTime,
        source: 'test',
        asOf: asOf,
        fetchedAt: asOf,
      );

  @override
  Future<ResolvedPrice?> resolve(Asset asset, {DateTime? asOf}) async => _p();

  @override
  Future<Map<String, ResolvedPrice?>> resolveMany(
    Iterable<Asset> assets, {
    DateTime? asOf,
  }) async =>
      {for (final a in assets) a.id: _p()};
}

void main() {
  group('Integration: securities trade moves net worth (real Drift)', () {
    test(
      'buying 100 shares @ 20 CNY drives net worth to +2000',
      () async {
        final env = await IntegrationEnv.create(
          extraOverrides: [
            priceResolverProvider.overrideWith(
              (ref) async =>
                  _FixedPriceResolver(Decimal.fromInt(20), 'CNY', DateTime(2026)),
            ),
          ],
        );

        await _seedLedger(env.db);

        // Record the buy through the real journal-entry repository.
        final jeRepo =
            await env.container.read(journalEntryRepositoryProvider.future);
        final build = JournalEntryBuilders.buy(
          date: DateTime.utc(2026, 1, 10),
          accountId: 'broker',
          cashAccountId: 'cash',
          assetUnit: 'NASDAQ:AAPL',
          qty: Decimal.fromInt(100),
          price: Decimal.fromInt(20),
          quoteCurrency: 'CNY',
        );
        await jeRepo.create(entry: build.entry, postings: build.postings);

        env.keepAlive(allAssetsStreamProvider);
        env.keepAlive(holdingsSnapshotProvider);
        env.keepAlive(dashboardSnapshotProvider);

        // Holding reconstructed from the ledger, valued by the fake source.
        final holdings =
            await env.container.read(holdingsSnapshotProvider.future);
        final aapl = holdings['NASDAQ:AAPL'];
        expect(aapl, isNotNull, reason: 'buy should produce an AAPL holding');
        expect(aapl!.quantity.toDouble(), 100.0);
        expect(aapl.marketValueInBase.toDouble(), 2000.0);

        // ...and it flows through to dashboard net worth.
        final snapshot =
            await env.container.read(dashboardSnapshotProvider.future);
        expect(snapshot.totalAssets.amount.toDouble(), 2000.0);
        expect(snapshot.netWorth.amount.toDouble(), 2000.0);
      },
      tags: 'integration',
    );
  });
}

/// Seeds the ledger accounts and the security row the buy posting refers
/// to. Inserted directly (mirroring portfolio_return_service_test) so the
/// double-entry account sides are explicit.
Future<void> _seedLedger(AppDatabase db) async {
  Future<void> account(String id, AccountCategory type, AccountSide side) {
    return db.into(db.accounts).insert(
          AccountsCompanion.insert(
            id: id,
            type: type,
            category: Value(side),
            name: id,
            currency: 'CNY',
            ownerUserId: 'u-test',
            updatedAt: DateTime.utc(2026),
            updatedByDevice: 'dev-test',
            hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
          ),
        );
  }

  await account('broker', AccountCategory.broker, AccountSide.asset);
  await account('cash', AccountCategory.bank, AccountSide.asset);

  await db.into(db.assets).insert(
        AssetsCompanion.insert(
          id: 'NASDAQ:AAPL',
          type: AssetType.stock,
          symbol: 'AAPL',
          currency: 'CNY',
          market: const Value('NASDAQ'),
          ownerUserId: 'u-test',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'dev-test',
          hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
        ),
      );
}
