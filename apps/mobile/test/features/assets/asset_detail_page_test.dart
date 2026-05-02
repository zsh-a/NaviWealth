import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/db/providers.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/market/exceptions.dart';
import 'package:naviwealth/data/market/market_data_providers.dart';
import 'package:naviwealth/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/assets/asset_detail_page.dart';
import 'package:naviwealth/features/assets/asset_detail_providers.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/holding_computer.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../data/db/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _ConfigurableMarket implements MarketDataService {
  _ConfigurableMarket({this.searchResults = const [], this.searchError});

  final List<SymbolInfo> searchResults;
  final Object? searchError;

  int searchCalls = 0;

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) async {
    searchCalls++;
    if (searchError != null) {
      throw searchError!;
    }
    return MarketResponse(
      data: searchResults,
      freshness: DataFreshness.live,
      source: 'stub',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(String symbol, {AssetMarket? market}) {
    throw UnimplementedError();
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) {
    throw UnimplementedError();
  }
}

class _Harness {
  _Harness({
    required this.db,
    required this.outbox,
    required this.secRepo,
    required this.manualRepo,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final SecuritiesAssetRepository secRepo;
  final ManualAssetRepository manualRepo;

  static Future<_Harness> create() async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    return _Harness(
      db: db,
      outbox: outbox,
      secRepo: SecuritiesAssetRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      ),
      manualRepo: ManualAssetRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      ),
    );
  }

  Future<void> dispose() => db.close();
}

class _EmptyHoldingService implements HoldingService {
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async => {};
  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];
  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) =>
      throw UnimplementedError();
  @override
  Future<void> invalidateFrom(DateTime from) async {}
}

ProviderScope _wrap(_Harness h, MarketDataService market, String assetId) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((_) async => h.db),
      outboxStoreProvider.overrideWith((_) async => h.outbox),
      securitiesAssetRepositoryProvider.overrideWith((_) async => h.secRepo),
      manualAssetRepositoryProvider.overrideWith((_) async => h.manualRepo),
      marketDataServiceProvider.overrideWith((_) async => market),
      // Asset-detail cards depend on the holding pipeline + transactions
      // stream + price history. Stub the holding service to an empty
      // portfolio, the transactions stream to an empty list, and the price
      // history to a no-op replay so the cards render their empty states
      // without touching the real database / network.
      holdingServiceProvider.overrideWith((_) async => _EmptyHoldingService()),
      assetTransactionsStreamProvider.overrideWith(
        (ref, _) => Stream.value(const []),
      ),
      assetReplayProvider.overrideWith(
        (ref, _) async => const HoldingReplayResult(
          lots: [],
          realizedPnL: [],
          unfulfilledSells: [],
        ),
      ),
      assetPriceHistoryProvider.overrideWith(
        (ref, _) async => MarketResponse<List<HistoricalBar>>(
          data: const [],
          freshness: DataFreshness.live,
          source: 'stub',
          fetchedAt: DateTime.utc(2026, 5, 1),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: AssetDetailPage(assetId: assetId),
    ),
  );
}

void main() {
  late _Harness harness;

  setUp(() async {
    harness = await _Harness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets('"同步元数据" fills empty name without overwriting user fields',
      (tester) async {
    await harness.secRepo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
    );

    final market = _ConfigurableMarket(
      searchResults: const [
        SymbolInfo(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          market: AssetMarket.usStock,
          currency: 'USD',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(harness, market, 'us_stock:AAPL'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('asset-detail-sync-metadata')), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-detail-sync-metadata')));
    await tester.pumpAndSettle();

    expect(market.searchCalls, 1);
    expect(find.text('已补全元数据'), findsOneWidget);
    final asset = await harness.secRepo.findById('us_stock:AAPL');
    expect(asset!.name, 'Apple Inc.');

    // Expire the AppMessenger dismiss timer so the test ends cleanly.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('"同步元数据" leaves an existing user-edited name alone',
      (tester) async {
    await harness.secRepo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'My Apple',
    );

    final market = _ConfigurableMarket(
      searchResults: const [
        SymbolInfo(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          market: AssetMarket.usStock,
          currency: 'USD',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(harness, market, 'us_stock:AAPL'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset-detail-sync-metadata')));
    await tester.pumpAndSettle();

    expect(find.text('元数据已是最新'), findsOneWidget);
    final asset = await harness.secRepo.findById('us_stock:AAPL');
    expect(asset!.name, 'My Apple',
        reason: 'enrichment must not overwrite a user-supplied name');

    // Expire the AppMessenger dismiss timer so the test ends cleanly.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('"同步元数据" failure surfaces a friendly offline message',
      (tester) async {
    await harness.secRepo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
    );

    final market = _ConfigurableMarket(
      searchError: const NoMarketDataAvailableException('offline'),
    );

    await tester.pumpWidget(_wrap(harness, market, 'us_stock:AAPL'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('asset-detail-sync-metadata')));
    await tester.pumpAndSettle();

    expect(find.text('网络不可用，无法同步元数据'), findsOneWidget);
    final asset = await harness.secRepo.findById('us_stock:AAPL');
    expect(asset!.name, isNull,
        reason: 'a failed sync must not write a placeholder name');

    // Expire the AppMessenger dismiss timer so the test ends cleanly.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('renders holding / P&L / mini-chart cards from snapshot data',
      (tester) async {
    await harness.secRepo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
    );

    final snapshot = HoldingSnapshot(
      assetId: 'us_stock:AAPL',
      quantity: Decimal.parse('10'),
      costBasisInAssetCurrency: Decimal.parse('1500'),
      marketValueInAssetCurrency: Decimal.parse('1750'),
      assetCurrency: 'USD',
      costBasisInBase: Decimal.parse('1500'),
      marketValueInBase: Decimal.parse('1750'),
      unrealizedPnlInBase: Decimal.parse('250'),
      weight: Decimal.parse('1'),
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 5, 1),
    );
    final history = [
      HistoricalBar(
        symbol: 'AAPL',
        asOf: DateTime.utc(2026, 4, 30),
        open: Decimal.parse('170'),
        high: Decimal.parse('171'),
        low: Decimal.parse('169'),
        close: Decimal.parse('170'),
      ),
      HistoricalBar(
        symbol: 'AAPL',
        asOf: DateTime.utc(2026, 5, 1),
        open: Decimal.parse('170'),
        high: Decimal.parse('176'),
        low: Decimal.parse('170'),
        close: Decimal.parse('175'),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => harness.db),
          outboxStoreProvider.overrideWith((_) async => harness.outbox),
          securitiesAssetRepositoryProvider
              .overrideWith((_) async => harness.secRepo),
          manualAssetRepositoryProvider
              .overrideWith((_) async => harness.manualRepo),
          marketDataServiceProvider
              .overrideWith((_) async => _ConfigurableMarket()),
          holdingServiceProvider.overrideWith(
            (_) async =>
                _StubHoldingService({'us_stock:AAPL': snapshot}),
          ),
          assetTransactionsStreamProvider.overrideWith(
            (ref, _) => Stream.value(const []),
          ),
          assetReplayProvider.overrideWith(
            (ref, _) async => const HoldingReplayResult(
              lots: [],
              realizedPnL: [],
              unfulfilledSells: [],
            ),
          ),
          assetPriceHistoryProvider.overrideWith(
            (ref, _) async => MarketResponse<List<HistoricalBar>>(
              data: history,
              freshness: DataFreshness.live,
              source: 'stub',
              fetchedAt: DateTime.utc(2026, 5, 1),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AssetDetailPage(assetId: 'us_stock:AAPL'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Holding card surfaces quantity + cost + market value.
    expect(find.text('当前数量'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('当前市值'), findsOneWidget);
    // Unrealized P&L row, daily change row, and 30-day chart all render.
    expect(find.text('未实现盈亏'), findsOneWidget);
    expect(find.text('今日变动'), findsOneWidget);
    expect(find.text('近 30 日走势'), findsOneWidget);
  });
}

class _StubHoldingService implements HoldingService {
  _StubHoldingService(this._snapshots);
  final Map<String, HoldingSnapshot> _snapshots;
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      _snapshots;
  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];
  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) =>
      throw UnimplementedError();
  @override
  Future<void> invalidateFrom(DateTime from) async {}
}
