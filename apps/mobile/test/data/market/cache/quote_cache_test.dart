import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/market/cache/cache_policy.dart';
import 'package:naviwealth/data/market/cache/quote_cache.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';

import '../../db/test_database.dart';
import '../fake_clock.dart';

void main() {
  group('MarketCache.quotes', () {
    test('writes then reads back as cachedFresh inside the TTL', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final cache = MarketCache(db: db, clock: clock);
      final quote = Quote(
        symbol: 'AAPL',
        currency: 'USD',
        price: Decimal.parse('250.10'),
        asOf: clock.now(),
        previousClose: Decimal.parse('249.00'),
      );

      await cache.writeQuote(quote, source: 'yfinance');
      clock.advance(const Duration(seconds: 30));
      final hit = await cache.readQuote('AAPL');

      expect(hit, isNotNull);
      expect(hit!.freshness, DataFreshness.cachedFresh);
      expect(hit.quote.price, Decimal.parse('250.10'));
      expect(hit.quote.previousClose, Decimal.parse('249.00'));
      expect(hit.source, 'yfinance');
    });

    test('default quote TTL keeps same-day quotes fresh', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final cache = MarketCache(db: db, clock: clock);

      await cache.writeQuote(
        Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('100'),
          asOf: clock.now(),
        ),
        source: 'yfinance',
      );
      clock.advance(const Duration(hours: 23));

      final hit = await cache.readQuote('AAPL');
      expect(hit, isNotNull);
      expect(hit!.freshness, DataFreshness.cachedFresh);
    });

    test('reports stale beyond fresh TTL but inside stale window', () async {
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
      await cache.writeQuote(
        Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('100'),
          asOf: clock.now(),
        ),
        source: 'yfinance',
      );
      clock.advance(const Duration(minutes: 5));

      final hit = await cache.readQuote('AAPL');
      expect(hit, isNotNull);
      expect(hit!.freshness, DataFreshness.stale);
    });

    test('returns null beyond the stale window', () async {
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
      await cache.writeQuote(
        Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('100'),
          asOf: clock.now(),
        ),
        source: 'yfinance',
      );
      clock.advance(const Duration(hours: 2));

      expect(await cache.readQuote('AAPL'), isNull);
    });

    test('source filter narrows results', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final cache = MarketCache(db: db, clock: clock);
      Quote q(String sym, num price) => Quote(
        symbol: sym,
        currency: 'USD',
        price: Decimal.parse(price.toString()),
        asOf: clock.now(),
      );
      await cache.writeQuote(q('AAPL', 100), source: 'yfinance');
      await cache.writeQuote(q('AAPL', 101), source: 'finnhub');

      final yf = await cache.readQuote('AAPL', source: 'yfinance');
      final fh = await cache.readQuote('AAPL', source: 'finnhub');
      expect(yf!.quote.price, Decimal.parse('100'));
      expect(fh!.quote.price, Decimal.parse('101'));
    });
  });

  group('MarketCache.history', () {
    test('round-trips bars in the requested range', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final cache = MarketCache(db: db, clock: clock);

      HistoricalBar bar(int day, num price) => HistoricalBar(
        symbol: 'AAPL',
        asOf: DateTime.utc(2026, 4, day),
        open: Decimal.parse(price.toString()),
        high: Decimal.parse((price + 1).toString()),
        low: Decimal.parse((price - 1).toString()),
        close: Decimal.parse(price.toString()),
        volume: 1000,
      );

      await cache.writeHistory(
        [bar(1, 100), bar(2, 101), bar(3, 102)],
        interval: BarInterval.day,
        source: 'yfinance',
      );

      final hit = await cache.readHistory(
        symbol: 'AAPL',
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 4, 3),
        interval: BarInterval.day,
      );
      expect(hit, isNotNull);
      expect(hit!.bars, hasLength(3));
      expect(hit.bars.first.close, Decimal.parse('100'));
      expect(hit.bars.last.close, Decimal.parse('102'));
      expect(hit.freshness, DataFreshness.cachedFresh);
    });
  });

  group('MarketCache.search', () {
    test('serialises and rehydrates SymbolInfo', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = FakeClock();
      final cache = MarketCache(db: db, clock: clock);

      final results = [
        const SymbolInfo(
          symbol: 'AAPL',
          name: 'Apple',
          market: AssetMarket.usStock,
          currency: 'USD',
          exchange: 'NMS',
          assetType: 'EQUITY',
        ),
        const SymbolInfo(
          symbol: 'BTC',
          name: 'Bitcoin',
          market: AssetMarket.crypto,
          exchange: 'bitcoin',
          assetType: 'CRYPTOCURRENCY',
        ),
      ];

      await cache.writeSearch('apple', results, source: 'yfinance');
      final hit = await cache.readSearch('  Apple ');

      expect(hit, isNotNull);
      expect(hit!.results, hasLength(2));
      expect(hit.results[0].market, AssetMarket.usStock);
      expect(hit.results[1].market, AssetMarket.crypto);
      expect(hit.results[1].exchange, 'bitcoin');
    });
  });
}
