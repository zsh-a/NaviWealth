import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';
import 'package:naviwealth/features/finance/data/market/cache/corporate_action_candidate_cache.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

import '../../../../../core/persistence/test_database.dart';

void main() {
  group('CorporateActionCandidateCache', () {
    test(
      'round-trips normalized Decimal and provider identity fields',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final cache = CorporateActionCandidateCache(db: db);
        final fetchedAt = DateTime.utc(2026, 6, 1, 8);
        final action = MarketCorporateAction(
          id: 'eastmoney:RPT_SHAREBONUS_DET:600519:plan-1',
          source: 'eastmoney',
          dataset: 'RPT_SHAREBONUS_DET',
          sourceKey: '600519:plan-1',
          revisionHash: 'revision-1',
          identityStrength: MarketCorporateActionIdentityStrength.strong,
          symbol: '600519',
          market: AssetMarket.cnA,
          kind: MarketCorporateActionKind.distribution,
          status: MarketCorporateActionStatus.implemented,
          reportDate: DateTime.utc(2026, 3, 31),
          announcementDate: DateTime.utc(2026, 5, 10),
          recordDate: DateTime.utc(2026, 5, 20),
          exDate: DateTime.utc(2026, 5, 21),
          payDate: DateTime.utc(2026, 5, 21),
          currency: 'CNY',
          cashPerShare: Decimal.parse('2.386'),
          bonusRatio: Decimal.parse('0.1'),
          capitalizationRatio: Decimal.parse('0.2'),
          totalStockDistributionRatio: Decimal.parse('0.3'),
          note: 'implemented plan',
        );

        await cache.write(
          symbol: '600519',
          market: AssetMarket.cnA,
          result: CorporateActionFetchResult(
            provider: 'eastmoney',
            disposition: CorporateActionFetchDisposition.success,
            actions: [action],
            fetchedAt: fetchedAt,
          ),
        );

        final cached = await cache.read(
          symbol: '600519',
          market: AssetMarket.cnA,
        );
        expect(cached, isNotNull);
        expect(cached!.provider, 'eastmoney');
        expect(cached.disposition, CorporateActionFetchDisposition.success);
        expect(cached.fetchedAt, fetchedAt);
        expect(cached.actions, hasLength(1));
        final restored = cached.actions.single;
        expect(restored.id, action.id);
        expect(restored.revisionHash, 'revision-1');
        expect(restored.identityStrength, action.identityStrength);
        expect(restored.cashPerShare, Decimal.parse('2.386'));
        expect(restored.bonusRatio, Decimal.parse('0.1'));
        expect(restored.capitalizationRatio, Decimal.parse('0.2'));
        expect(restored.totalStockDistributionRatio, Decimal.parse('0.3'));
        expect(restored.recordDate, DateTime.utc(2026, 5, 20));
      },
    );

    test(
      'authoritative empty replaces old candidates but remains cached',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final cache = CorporateActionCandidateCache(db: db);
        final action = MarketCorporateAction(
          id: 'yfinance:chart:AAPL:dividend:1',
          source: 'yfinance',
          dataset: 'chart',
          sourceKey: 'AAPL:dividend:1',
          revisionHash: 'revision-1',
          identityStrength: MarketCorporateActionIdentityStrength.weak,
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          kind: MarketCorporateActionKind.distribution,
          status: MarketCorporateActionStatus.unknown,
          exDate: DateTime.utc(2026, 4, 1),
          currency: 'USD',
          cashPerShare: Decimal.parse('0.25'),
        );
        await cache.write(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          result: CorporateActionFetchResult(
            provider: 'yfinance',
            disposition: CorporateActionFetchDisposition.success,
            actions: [action],
            fetchedAt: DateTime.utc(2026, 3, 1),
          ),
        );

        await cache.write(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
          result: CorporateActionFetchResult(
            provider: 'yfinance',
            disposition: CorporateActionFetchDisposition.authoritativeEmpty,
            actions: const [],
            fetchedAt: DateTime.utc(2026, 3, 2),
          ),
        );

        final cached = await cache.read(
          symbol: 'AAPL',
          market: AssetMarket.usStock,
        );
        expect(
          cached?.disposition,
          CorporateActionFetchDisposition.authoritativeEmpty,
        );
        expect(cached?.actions, isEmpty);
        final count = await db
            .customSelect(
              'SELECT COUNT(*) AS count '
              'FROM market_corporate_action_candidates',
            )
            .getSingle();
        expect(count.read<int>('count'), 0);
      },
    );

    test('cache tables stay outside Sync v3', () {
      expect(
        kSyncableTables,
        isNot(contains('market_corporate_action_candidates')),
      );
      expect(
        kSyncableTables,
        isNot(contains('market_corporate_action_fetch_states')),
      );
    });
  });
}
