import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/sync/fx_rate_sync_service.dart';
import 'package:naviwealth/features/finance/data/repositories/fx_rate_repository.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import '../../../../../core/persistence/test_database.dart';
import '../fake_clock.dart';

class _FakeMarketData implements MarketDataService {
  _FakeMarketData({required this.fetchedAt});

  final DateTime fetchedAt;
  DataFreshness quoteFreshness = DataFreshness.live;
  final Map<String, List<HistoricalBar>> historical = {};
  final Set<String> historyFailures = {};
  final Map<String, Decimal> quotes = {};
  final List<({String symbol, DateTime from, DateTime to})> historyRequests =
      [];
  final List<String> quoteRequests = [];

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) async {
    quoteRequests.add(symbol);
    final price = quotes[symbol];
    if (price == null) {
      throw const NoMarketDataAvailableException('quote unavailable');
    }
    return MarketResponse(
      data: Quote(
        symbol: symbol,
        currency: 'USD',
        price: price,
        asOf: fetchedAt,
      ),
      freshness: quoteFreshness,
      source: 'fake',
      fetchedAt: fetchedAt,
    );
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    historyRequests.add((symbol: symbol, from: from, to: to));
    if (historyFailures.contains(symbol)) {
      throw const NoMarketDataAvailableException('history unavailable');
    }
    return MarketResponse(
      data: historical[symbol] ?? const [],
      freshness: DataFreshness.live,
      source: 'fake',
      fetchedAt: fetchedAt,
    );
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) async => throw UnimplementedError();
}

HistoricalBar _bar({
  required String symbol,
  required DateTime date,
  required String close,
}) {
  final value = Decimal.parse(close);
  return HistoricalBar(
    symbol: symbol,
    asOf: date,
    open: value,
    high: value,
    low: value,
    close: value,
  );
}

void main() {
  late AppDatabase db;
  late FxRateRepository repo;

  setUp(() {
    db = makeTestDatabase();
    repo = FxRateRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('backfills every returned trading-day close', () async {
    final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 14, 12))
      ..historical['USDCNY=X'] = [
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 12),
          close: '7.18',
        ),
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 13),
          close: '7.19',
        ),
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 14),
          close: '7.20',
        ),
      ];
    final service = FxRateSyncService(
      marketData: market,
      fxRepo: repo,
      clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
      historyLookback: const Duration(days: 3),
    );

    expect(
      await service.syncRates(
        baseCurrency: 'USD',
        accountCurrencies: {'USD', 'CNY'},
      ),
      1,
    );
    expect(market.historyRequests, hasLength(1));
    expect(market.historyRequests.single.from, DateTime.utc(2026, 5, 12));
    expect(market.historyRequests.single.to, DateTime.utc(2026, 5, 14));
    expect(market.quoteRequests, isEmpty);

    final rates = await repo.listAll();
    expect(rates, hasLength(3));
    expect(rates.map((rate) => rate.date), [
      DateTime.utc(2026, 5, 12),
      DateTime.utc(2026, 5, 13),
      DateTime.utc(2026, 5, 14),
    ]);
    expect(rates.last.rate, Decimal.parse('7.20'));
  });

  test('incremental sync starts before the newest stored day', () async {
    await repo.upsertDaily(
      baseCurrency: 'USD',
      quoteCurrency: 'CNY',
      rate: Decimal.parse('7.10'),
      asOf: DateTime.utc(2026, 5, 10),
    );
    final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 14, 12))
      ..historical['USDCNY=X'] = [
        _bar(symbol: 'USDCNY=X', date: DateTime.utc(2026, 5, 8), close: '7.08'),
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 11),
          close: '7.11',
        ),
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 14),
          close: '7.14',
        ),
      ];
    final service = FxRateSyncService(
      marketData: market,
      fxRepo: repo,
      clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
      historyLookback: const Duration(days: 8),
      incrementalOverlap: const Duration(days: 7),
    );

    await service.syncRates(
      baseCurrency: 'USD',
      accountCurrencies: {'USD', 'CNY'},
    );

    expect(market.historyRequests.single.from, DateTime.utc(2026, 5, 7));
    final rates = await repo.listAll();
    expect(rates, hasLength(4));
    expect(rates.map((rate) => rate.date), [
      DateTime.utc(2026, 5, 8),
      DateTime.utc(2026, 5, 10),
      DateTime.utc(2026, 5, 11),
      DateTime.utc(2026, 5, 14),
    ]);
  });

  test('inverts every bar when only the reverse pair is available', () async {
    final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 14, 12))
      ..historyFailures.add('USDCNY=X')
      ..historical['CNYUSD=X'] = [
        _bar(
          symbol: 'CNYUSD=X',
          date: DateTime.utc(2026, 5, 14),
          close: '0.14',
        ),
      ];
    final service = FxRateSyncService(
      marketData: market,
      fxRepo: repo,
      clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
      historyLookback: const Duration(days: 1),
    );

    await service.syncRates(
      baseCurrency: 'USD',
      accountCurrencies: {'USD', 'CNY'},
    );

    expect(market.historyRequests.map((request) => request.symbol), [
      'USDCNY=X',
      'CNYUSD=X',
    ]);
    expect(market.quoteRequests, isEmpty);
    final rates = await repo.listAll();
    expect(rates.single.base, 'USD');
    expect(rates.single.quote, 'CNY');
    expect(rates.single.rate, Decimal.parse('7.14285714'));
  });

  test('repairs a long middle gap before syncing the recent tail', () async {
    await repo.upsertDaily(
      baseCurrency: 'USD',
      quoteCurrency: 'CNY',
      rate: Decimal.parse('7.10'),
      asOf: DateTime.utc(2026, 5, 10),
    );
    await repo.upsertDaily(
      baseCurrency: 'USD',
      quoteCurrency: 'CNY',
      rate: Decimal.parse('7.20'),
      asOf: DateTime.utc(2026, 5, 20),
    );
    final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 20, 12))
      ..historical['USDCNY=X'] = [
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 11),
          close: '7.11',
        ),
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 15),
          close: '7.15',
        ),
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 20),
          close: '7.20',
        ),
      ];
    final service = FxRateSyncService(
      marketData: market,
      fxRepo: repo,
      clock: FakeClock(DateTime.utc(2026, 5, 20, 12)),
      historyLookback: const Duration(days: 15),
      incrementalOverlap: const Duration(days: 7),
    );

    final result = await service.syncRatesDetailed(
      baseCurrency: 'USD',
      accountCurrencies: {'USD', 'CNY'},
    );

    expect(result.syncedPairs, {'USD/CNY'});
    expect(market.historyRequests.single.from, DateTime.utc(2026, 5, 11));
    expect((await repo.listAll()).map((rate) => rate.date), [
      DateTime.utc(2026, 5, 10),
      DateTime.utc(2026, 5, 11),
      DateTime.utc(2026, 5, 15),
      DateTime.utc(2026, 5, 20),
    ]);
  });

  test('does not persist a non-empty history with a middle gap', () async {
    final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 14, 12))
      ..historical['USDCNY=X'] = [
        _bar(symbol: 'USDCNY=X', date: DateTime.utc(2026, 5, 5), close: '7.10'),
        _bar(
          symbol: 'USDCNY=X',
          date: DateTime.utc(2026, 5, 14),
          close: '7.20',
        ),
      ];
    final service = FxRateSyncService(
      marketData: market,
      fxRepo: repo,
      clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
      historyLookback: const Duration(days: 10),
    );

    final result = await service.syncRatesDetailed(
      baseCurrency: 'USD',
      accountCurrencies: {'USD', 'CNY'},
    );

    expect(result.syncedPairs, isEmpty);
    expect(result.failures.keys, contains('USD/CNY'));
    expect(await repo.listAll(), isEmpty);
    expect(market.quoteRequests, isEmpty);
  });

  test(
    'falls back to the latest quote when historical data is unavailable',
    () async {
      final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 14, 12))
        ..historyFailures.addAll({'USDCNY=X', 'CNYUSD=X'})
        ..quotes['USDCNY=X'] = Decimal.parse('7.20');
      final service = FxRateSyncService(
        marketData: market,
        fxRepo: repo,
        clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
        historyLookback: const Duration(days: 30),
      );

      await service.syncRates(
        baseCurrency: 'USD',
        accountCurrencies: {'USD', 'CNY'},
      );

      expect(market.quoteRequests, ['USDCNY=X']);
      final rates = await repo.listAll();
      expect(rates.single.rate, Decimal.parse('7.20'));
      expect(rates.single.date, DateTime.utc(2026, 5, 14));
    },
  );

  test('reports failed pairs instead of silently returning zero', () async {
    final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 14, 12))
      ..historyFailures.addAll({'USDCNY=X', 'CNYUSD=X'});
    final service = FxRateSyncService(
      marketData: market,
      fxRepo: repo,
      clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
      historyLookback: const Duration(days: 30),
    );

    final result = await service.syncRatesDetailed(
      baseCurrency: 'USD',
      accountCurrencies: {'USD', 'CNY'},
    );

    expect(result.requestedPairs, {'USD/CNY'});
    expect(result.syncedPairs, isEmpty);
    expect(result.failures.keys, contains('USD/CNY'));
    expect(result.failureSummary, contains('USD/CNY'));
  });

  test('does not treat a stale quote fallback as a successful sync', () async {
    final market = _FakeMarketData(fetchedAt: DateTime.utc(2026, 5, 14, 12))
      ..quoteFreshness = DataFreshness.stale
      ..historyFailures.addAll({'USDCNY=X', 'CNYUSD=X'})
      ..quotes['USDCNY=X'] = Decimal.parse('7.20');
    final service = FxRateSyncService(
      marketData: market,
      fxRepo: repo,
      clock: FakeClock(DateTime.utc(2026, 5, 14, 12)),
      historyLookback: const Duration(days: 30),
    );

    final result = await service.syncRatesDetailed(
      baseCurrency: 'USD',
      accountCurrencies: {'USD', 'CNY'},
    );

    expect(result.syncedPairs, isEmpty);
    expect(result.failures.keys, contains('USD/CNY'));
    expect(await repo.listAll(), isEmpty);
  });
}
