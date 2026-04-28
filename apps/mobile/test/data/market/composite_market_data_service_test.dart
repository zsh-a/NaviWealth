import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/market/cache/cache_policy.dart';
import 'package:naviwealth/data/market/cache/quote_cache.dart';
import 'package:naviwealth/data/market/composite_market_data_service.dart';
import 'package:naviwealth/data/market/exceptions.dart';
import 'package:naviwealth/data/market/metrics/market_metrics.dart';
import 'package:naviwealth/data/market/providers/market_provider.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';

import '../db/test_database.dart';
import 'fake_clock.dart';

class _FakeProvider implements MarketProvider {
  _FakeProvider({
    required this.name,
    required this.supportedMarkets,
    this.quoteResult,
    this.historyResult,
    this.searchResult,
    this.quoteError,
    this.historyError,
  });

  @override
  final String name;
  @override
  final Set<AssetMarket> supportedMarkets;

  Quote? quoteResult;
  List<HistoricalBar>? historyResult;
  List<SymbolInfo>? searchResult;
  Object? quoteError;
  Object? historyError;

  int quoteCalls = 0;
  int historyCalls = 0;
  int searchCalls = 0;

  @override
  Future<Quote> getQuote(String symbol) async {
    quoteCalls++;
    if (quoteError != null) throw quoteError!;
    return quoteResult!;
  }

  @override
  Future<List<HistoricalBar>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
  }) async {
    historyCalls++;
    if (historyError != null) throw historyError!;
    return historyResult ?? const [];
  }

  @override
  Future<List<SymbolInfo>> searchSymbol(String query) async {
    searchCalls++;
    return searchResult ?? const [];
  }
}

void main() {
  group('CompositeMarketDataService.getQuote', () {
    test('returns live quote and writes through to cache', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final cache = MarketCache(db: db, clock: clock);
      final provider = _FakeProvider(
        name: 'fake',
        supportedMarkets: {AssetMarket.usStock},
        quoteResult: Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('250'),
          asOf: clock.now(),
        ),
      );
      final svc = CompositeMarketDataService(
        providers: [provider],
        cache: cache,
        clock: clock,
      );

      final r = await svc.getQuote('AAPL');

      expect(r.freshness, DataFreshness.live);
      expect(r.data.price, Decimal.parse('250'));

      // Second call within fresh TTL is served from cache.
      provider.quoteResult = Quote(
        symbol: 'AAPL',
        currency: 'USD',
        price: Decimal.parse('999'),
        asOf: clock.now(),
      );
      final r2 = await svc.getQuote('AAPL');
      expect(r2.freshness, DataFreshness.cachedFresh);
      expect(r2.data.price, Decimal.parse('250'));
      expect(provider.quoteCalls, 1);
    });

    test(
      'falls through providers and emits fallback metric on error',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final clock = FakeClock();
        final metrics = MarketMetrics();
        addTearDown(metrics.dispose);

        final p1 = _FakeProvider(
          name: 'p1',
          supportedMarkets: {AssetMarket.usStock},
          quoteError: const NetworkException('boom', provider: 'p1'),
        );
        final p2 = _FakeProvider(
          name: 'p2',
          supportedMarkets: {AssetMarket.usStock},
          quoteResult: Quote(
            symbol: 'AAPL',
            currency: 'USD',
            price: Decimal.parse('250'),
            asOf: clock.now(),
          ),
        );
        final svc = CompositeMarketDataService(
          providers: [p1, p2],
          cache: MarketCache(db: db, clock: clock),
          clock: clock,
          metrics: metrics,
        );

        final r = await svc.getQuote('AAPL');
        expect(r.source, 'p2');
        expect(r.freshness, DataFreshness.live);
        expect(metrics.snapshot().fallbacks['p1→p2'], 1);
      },
    );

    test('serves stale cache when all providers fail', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final cache = MarketCache(
        db: db,
        clock: clock,
        policy: const MarketCachePolicy(
          quoteFresh: Duration(seconds: 60),
          quoteStaleWindow: Duration(hours: 1),
        ),
      );
      // Seed cache with a fresh quote, then advance past the fresh TTL.
      await cache.writeQuote(
        Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('100'),
          asOf: clock.now(),
        ),
        source: 'seed',
      );
      clock.advance(const Duration(minutes: 5));

      final p = _FakeProvider(
        name: 'p',
        supportedMarkets: {AssetMarket.usStock},
        quoteError: const NetworkException('boom', provider: 'p'),
      );
      final svc = CompositeMarketDataService(
        providers: [p],
        cache: cache,
        clock: clock,
      );

      final r = await svc.getQuote('AAPL');
      expect(r.freshness, DataFreshness.stale);
      expect(r.source, 'seed');
      expect(r.data.price, Decimal.parse('100'));
    });

    test(
      'throws NoMarketDataAvailableException when no cache + all fail',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final clock = FakeClock();
        final p = _FakeProvider(
          name: 'p',
          supportedMarkets: {AssetMarket.usStock},
          quoteError: const NetworkException('boom', provider: 'p'),
        );
        final svc = CompositeMarketDataService(
          providers: [p],
          cache: MarketCache(db: db, clock: clock),
          clock: clock,
        );

        expect(
          () => svc.getQuote('AAPL'),
          throwsA(isA<NoMarketDataAvailableException>()),
        );
      },
    );

    test('routes by market when provided', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final pUs = _FakeProvider(
        name: 'us',
        supportedMarkets: {AssetMarket.usStock},
        quoteResult: Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('250'),
          asOf: clock.now(),
        ),
      );
      final pCrypto = _FakeProvider(
        name: 'crypto',
        supportedMarkets: {AssetMarket.crypto},
        quoteResult: Quote(
          symbol: 'BTC',
          currency: 'USD',
          price: Decimal.parse('60000'),
          asOf: clock.now(),
        ),
      );
      final svc = CompositeMarketDataService(
        providers: [pUs, pCrypto],
        cache: MarketCache(db: db, clock: clock),
        clock: clock,
      );

      await svc.getQuote('AAPL', market: AssetMarket.usStock);
      expect(pUs.quoteCalls, 1);
      expect(pCrypto.quoteCalls, 0);

      await svc.getQuote('BTC', market: AssetMarket.crypto);
      expect(pCrypto.quoteCalls, 1);
      expect(pUs.quoteCalls, 1);
    });
  });

  group('CompositeMarketDataService.getHistorical', () {
    test(
      'serves stale cache when provider fails and prior data exists',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final clock = FakeClock();
        final cache = MarketCache(
          db: db,
          clock: clock,
          policy: const MarketCachePolicy(
            historyFresh: Duration(hours: 1),
            historyStaleWindow: Duration(days: 30),
          ),
        );
        HistoricalBar bar(int day, num price) => HistoricalBar(
          symbol: 'AAPL',
          asOf: DateTime.utc(2026, 4, day),
          open: Decimal.parse(price.toString()),
          high: Decimal.parse(price.toString()),
          low: Decimal.parse(price.toString()),
          close: Decimal.parse(price.toString()),
        );
        await cache.writeHistory(
          [bar(1, 100), bar(2, 101)],
          interval: BarInterval.day,
          source: 'seed',
        );
        clock.advance(const Duration(days: 2));

        final p = _FakeProvider(
          name: 'p',
          supportedMarkets: {AssetMarket.usStock},
          historyError: const NetworkException('boom', provider: 'p'),
        );
        final svc = CompositeMarketDataService(
          providers: [p],
          cache: cache,
          clock: clock,
        );

        final r = await svc.getHistorical(
          'AAPL',
          from: DateTime.utc(2026, 4, 1),
          to: DateTime.utc(2026, 4, 2),
          interval: BarInterval.day,
        );
        expect(r.freshness, DataFreshness.stale);
        expect(r.data, hasLength(2));
      },
    );

    test('skips providers that throw UnsupportedError', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final p1 = _FakeProvider(
        name: 'sina',
        supportedMarkets: {AssetMarket.cnA},
        historyError: UnsupportedError('no history'),
      );
      final p2 = _FakeProvider(
        name: 'yfinance',
        supportedMarkets: {AssetMarket.cnA},
        historyResult: [
          HistoricalBar(
            symbol: 'SH600519',
            asOf: DateTime.utc(2026, 4, 1),
            open: Decimal.parse('1500'),
            high: Decimal.parse('1510'),
            low: Decimal.parse('1490'),
            close: Decimal.parse('1505'),
          ),
        ],
      );
      final svc = CompositeMarketDataService(
        providers: [p1, p2],
        cache: MarketCache(db: db, clock: clock),
        clock: clock,
      );

      final r = await svc.getHistorical(
        'SH600519',
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 4, 2),
        interval: BarInterval.day,
      );

      expect(r.source, 'yfinance');
      expect(p1.historyCalls, 1);
      expect(p2.historyCalls, 1);
    });
  });

  group('CompositeMarketDataService.searchSymbol', () {
    test('aggregates results across providers and de-duplicates', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final p1 = _FakeProvider(
        name: 'p1',
        supportedMarkets: const {AssetMarket.usStock},
        searchResult: const [
          SymbolInfo(
            symbol: 'AAPL',
            name: 'Apple',
            market: AssetMarket.usStock,
          ),
        ],
      );
      final p2 = _FakeProvider(
        name: 'p2',
        supportedMarkets: const {AssetMarket.usStock},
        searchResult: const [
          SymbolInfo(
            symbol: 'AAPL',
            name: 'Apple Inc.',
            market: AssetMarket.usStock,
          ),
          SymbolInfo(
            symbol: 'MSFT',
            name: 'Microsoft',
            market: AssetMarket.usStock,
          ),
        ],
      );
      final svc = CompositeMarketDataService(
        providers: [p1, p2],
        cache: MarketCache(db: db, clock: clock),
        clock: clock,
      );

      final r = await svc.searchSymbol('app');
      final symbols = r.data.map((s) => s.symbol).toSet();
      expect(symbols, {'AAPL', 'MSFT'});
    });
  });
}
