import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/market/services/corporate_actions_service.dart';
import 'package:naviwealth/features/finance/investment/data/event_timeline_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test(
    'reconciliation fetches and materializes paper dividend references',
    () async {
      final db = makeTestDatabase();
      final outbox = InMemoryOutboxStore();
      final repository = WatchlistSimulationRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
      );
      final simulation = await repository.create(
        collectionId: 'collection-cn',
        name: 'Automatic dividend references',
        baseCurrency: 'CNY',
        startingCapital: Decimal.parse('100000'),
        targetWeights: {'cn_a:600519': Decimal.one},
        cashWeight: Decimal.zero,
        holdingInputs: {
          'cn_a:600519': WatchlistSimulationHoldingInput(
            symbol: '600519',
            market: AssetMarket.cnA,
            rawPrice: Decimal.parse('200'),
            priceCurrency: 'CNY',
            priceAsOf: DateTime.utc(2023, 11, 14),
            priceSource: 'fixture',
          ),
        },
      );
      final position =
          (await repository
                  .watchPositions(
                    ownerUserId: 'u-test',
                    simulationId: simulation.id,
                  )
                  .first)
              .single;
      final item = WatchlistItem(
        id: 'cn_a:600519',
        symbol: '600519',
        market: AssetMarket.cnA,
        addedAt: simulation.createdAt,
        alertRules: const PriceAlertRules(),
        sync: simulation.sync,
      );
      final provider = _FixtureCorporateActionProvider();
      final service = CorporateActionsService(
        providers: [provider],
        logger: AppLogger(
          environment: AppEnvironment.dev,
          crashReporter: const NoopCrashReporter(),
        ),
        now: () => DateTime.utc(2024, 6, 1),
      );
      final container = ProviderContainer(
        overrides: [
          watchlistSimulationRepositoryProvider.overrideWith(
            (_) async => repository,
          ),
          watchlistSimulationsProvider.overrideWith(
            (_) => Stream.value([simulation]),
          ),
          watchlistSimulationPositionsProvider.overrideWith(
            (_, _) => Stream.value([position]),
          ),
          watchlistItemsProvider.overrideWith((_) => Stream.value([item])),
          corporateActionsServiceProvider.overrideWith((_) async => service),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      final reconciliationProvider =
          watchlistSimulationActionReconciliationProvider(simulation.id);
      final subscription = container.listen(reconciliationProvider, (_, _) {});
      addTearDown(subscription.close);
      final summary = await container.read(reconciliationProvider.future);

      expect(provider.fetchCount, 1);
      expect(summary.materializedCount, 1);
      expect(summary.failedSymbolCount, 0);
      expect(summary.unsupportedSymbolCount, 0);
      final records = await repository
          .watchActionEntries(
            ownerUserId: 'u-test',
            simulationId: simulation.id,
          )
          .first;
      expect(records, hasLength(1));
      expect(records.single.symbol, '600519');
      expect(records.single.cashPerShare, Decimal.parse('2.5'));
      expect(records.single.eligibleQuantity, Decimal.parse('500'));
      expect(records.single.grossAmount, Decimal.parse('1250.0'));
      expect(
        records.single.paperState,
        WatchlistSimulationPaperActionState.entitlementRecorded,
      );
    },
  );
}

class _FixtureCorporateActionProvider implements CorporateActionProvider {
  int fetchCount = 0;

  @override
  String get name => 'fixture';

  @override
  CorporateActionProviderCapabilities get capabilities =>
      const CorporateActionProviderCapabilities(
        supportedMarkets: {AssetMarket.cnA},
        supportsRecordDate: true,
        supportsPayDate: true,
        supportsRevisions: true,
        availableOnWeb: true,
      );

  @override
  Future<CorporateActionFetchResult> fetch(
    CorporateActionFetchRequest request,
  ) async {
    fetchCount++;
    return CorporateActionFetchResult(
      provider: name,
      disposition: CorporateActionFetchDisposition.success,
      actions: [
        MarketCorporateAction(
          id: 'fixture:dividend:600519:2024',
          source: name,
          dataset: 'fixture_dividends',
          sourceKey: '600519:2024',
          revisionHash: 'revision-1',
          identityStrength: MarketCorporateActionIdentityStrength.strong,
          symbol: request.symbol,
          market: request.market,
          kind: MarketCorporateActionKind.distribution,
          status: MarketCorporateActionStatus.implemented,
          recordDate: DateTime.utc(2024, 6, 20),
          exDate: DateTime.utc(2024, 6, 21),
          payDate: DateTime.utc(2024, 6, 21),
          currency: 'CNY',
          cashPerShare: Decimal.parse('2.5'),
        ),
      ],
      fetchedAt: DateTime.utc(2024, 6, 1),
    );
  }
}
