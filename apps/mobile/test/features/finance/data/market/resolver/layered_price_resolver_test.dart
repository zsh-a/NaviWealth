import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/resolver/layered_price_resolver.dart';
import 'package:naviwealth/features/finance/data/market/resolver/price_resolver.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import '../../../../../core/persistence/test_database.dart';
import '../../../../../features/finance/data/repositories/_stub_stamper.dart';
import '../fake_clock.dart';

/// In-memory [MarketDataService] with scriptable per-symbol behaviour.
class _FakeMarketDataService implements MarketDataService {
  final Map<String, MarketResponse<Quote>> quotes = {};
  final Map<String, MarketResponse<List<HistoricalBar>>> history = {};
  int quoteCalls = 0;
  int historyCalls = 0;

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) async {
    quoteCalls++;
    final r = quotes[symbol];
    if (r == null) {
      throw const NoMarketDataAvailableException('no quote');
    }
    return r;
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    historyCalls++;
    final r = history[symbol];
    if (r == null) {
      throw const NoMarketDataAvailableException('no history');
    }
    return r;
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) async => throw UnimplementedError();
}

Asset _asset({
  required String market,
  required String symbol,
  String currency = 'USD',
  AssetType type = AssetType.stock,
}) => Asset(
  id: Asset.idFor(assetMarketFromWire(market) ?? AssetMarket.unknown, symbol),
  type: type,
  symbol: symbol,
  currency: currency,
  market: market,
  sync: SyncMeta(
    ownerUserId: 'u-test',
    updatedAt: DateTime.utc(2026, 1, 1),
    updatedByDevice: 'dev',
    hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
  ),
);

void main() {
  late FakeClock clock;
  late _FakeMarketDataService market;
  late PriceRepository priceRepo;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 5, 14, 12));
    market = _FakeMarketDataService();
    final db = makeTestDatabase();
    addTearDown(db.close);
    priceRepo = PriceRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
  });

  LayeredPriceResolver buildResolver({PriceResolverPolicy? policy}) =>
      LayeredPriceResolver(
        market: market,
        prices: priceRepo,
        clock: clock,
        policy: policy ?? const PriceResolverPolicy(),
      );

  test('tier 2 wins when a fresh ledger row exists', () async {
    final asset = _asset(market: 'us_stock', symbol: 'AAPL');
    // Ledger row 1h old.
    await priceRepo.record(
      unit: asset.id,
      quoteCurrency: 'USD',
      observedOn: clock.now().subtract(const Duration(hours: 1)),
      perUnit: Decimal.parse('200.00'),
      source: 'manual',
    );
    // Provider would return 250 if asked.
    market.quotes['AAPL'] = MarketResponse(
      data: Quote(
        symbol: 'AAPL',
        currency: 'USD',
        price: Decimal.parse('250.00'),
        asOf: clock.now(),
      ),
      freshness: DataFreshness.live,
      source: 'yfinance',
      fetchedAt: clock.now(),
    );

    final r = await buildResolver().resolve(asset);

    expect(r, isNotNull);
    expect(r!.value, Decimal.parse('200.00'));
    expect(r.confidence, PriceConfidence.manual);
    expect(r.source, 'manual');
    expect(
      market.quoteCalls,
      0,
      reason: 'ledger fresh-tier should short-circuit',
    );
  });

  test(
    'tier 3 wins on empty ledger and yields realTime on a fresh quote',
    () async {
      final asset = _asset(market: 'us_stock', symbol: 'AAPL');
      market.quotes['AAPL'] = MarketResponse(
        data: Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('250.00'),
          asOf: clock.now(), // age = 0
        ),
        freshness: DataFreshness.live,
        source: 'yfinance',
        fetchedAt: clock.now(),
      );

      final r = await buildResolver().resolve(asset);

      expect(r!.value, Decimal.parse('250.00'));
      expect(r.confidence, PriceConfidence.realTime);
      expect(r.source, 'yfinance');
    },
  );

  test(
    'cachedFresh provider response maps to dailyClose, never realTime',
    () async {
      final asset = _asset(market: 'us_stock', symbol: 'AAPL');
      market.quotes['AAPL'] = MarketResponse(
        data: Quote(
          symbol: 'AAPL',
          currency: 'USD',
          price: Decimal.parse('250.00'),
          asOf: clock.now(),
        ),
        freshness: DataFreshness.cachedFresh,
        source: 'yfinance',
        fetchedAt: clock.now(),
      );

      final r = await buildResolver().resolve(asset);

      expect(r!.confidence, PriceConfidence.dailyClose);
    },
  );

  test('all live tiers fail + 30-day-old ledger → returned as stale', () async {
    final asset = _asset(market: 'us_stock', symbol: 'AAPL');
    await priceRepo.record(
      unit: asset.id,
      quoteCurrency: 'USD',
      observedOn: clock.now().subtract(const Duration(days: 30)),
      perUnit: Decimal.parse('180.00'),
      source: 'manual',
    );
    // No quote, no history → both live tiers throw NoMarketDataAvailable.

    final r = await buildResolver().resolve(asset);

    expect(r!.confidence, PriceConfidence.stale);
    expect(r.value, Decimal.parse('180.00'));
    expect(r.note, contains('forward-filled'));
  });

  test('past asOf skips live tier and falls back to historical bar', () async {
    final asset = _asset(market: 'us_stock', symbol: 'AAPL');
    // asOf 2 years ago — beyond liveLookback (1d).
    final pastAsOf = DateTime.utc(2024, 5, 14);
    market.history['AAPL'] = MarketResponse(
      data: [
        HistoricalBar(
          symbol: 'AAPL',
          asOf: DateTime.utc(2024, 5, 13),
          open: Decimal.parse('100'),
          high: Decimal.parse('105'),
          low: Decimal.parse('99'),
          close: Decimal.parse('103.50'),
        ),
        HistoricalBar(
          symbol: 'AAPL',
          asOf: DateTime.utc(2024, 5, 20), // after pastAsOf — ignored
          open: Decimal.parse('110'),
          high: Decimal.parse('115'),
          low: Decimal.parse('109'),
          close: Decimal.parse('113.50'),
        ),
      ],
      freshness: DataFreshness.live,
      source: 'yfinance',
      fetchedAt: clock.now(),
    );

    final r = await buildResolver().resolve(asset, asOf: pastAsOf);

    expect(r!.value, Decimal.parse('103.50'));
    expect(r.confidence, PriceConfidence.dailyClose);
    expect(r.source, startsWith('historical-bar:'));
    expect(
      market.quoteCalls,
      0,
      reason: 'live tier must be skipped for past asOf',
    );
  });

  test('manual-valuation assets skip the live tier entirely', () async {
    final cash = _asset(
      market: 'unknown',
      symbol: 'cash-cny',
      currency: 'CNY',
      type: AssetType.cash,
    );
    // No ledger row, no quote, no history → expect null without any provider call.
    final r = await buildResolver().resolve(cash);

    expect(r, isNull);
    expect(market.quoteCalls, 0);
    expect(market.historyCalls, 0);
  });

  test(
    'resolveMany fires at most N quote calls and respects ledger tier',
    () async {
      final assets = [
        _asset(market: 'us_stock', symbol: 'AAPL'),
        _asset(market: 'us_stock', symbol: 'GOOG'),
        _asset(market: 'us_stock', symbol: 'MSFT'),
      ];
      // AAPL has fresh ledger row — should NOT hit provider.
      await priceRepo.record(
        unit: assets[0].id,
        quoteCurrency: 'USD',
        observedOn: clock.now().subtract(const Duration(minutes: 30)),
        perUnit: Decimal.parse('200'),
        source: 'manual',
      );
      market.quotes['GOOG'] = MarketResponse(
        data: Quote(
          symbol: 'GOOG',
          currency: 'USD',
          price: Decimal.parse('150'),
          asOf: clock.now(),
        ),
        freshness: DataFreshness.live,
        source: 'yfinance',
        fetchedAt: clock.now(),
      );
      market.quotes['MSFT'] = MarketResponse(
        data: Quote(
          symbol: 'MSFT',
          currency: 'USD',
          price: Decimal.parse('400'),
          asOf: clock.now(),
        ),
        freshness: DataFreshness.live,
        source: 'yfinance',
        fetchedAt: clock.now(),
      );

      final out = await buildResolver().resolveMany(assets);

      expect(out, hasLength(3));
      expect(out[assets[0].id]!.confidence, PriceConfidence.manual);
      expect(out[assets[1].id]!.value, Decimal.parse('150'));
      expect(out[assets[2].id]!.value, Decimal.parse('400'));
      expect(
        market.quoteCalls,
        2,
        reason: 'AAPL served by ledger; GOOG+MSFT by provider',
      );
    },
  );

  test('live quote older than realTimeMaxAge downgrades to delayed', () async {
    final asset = _asset(market: 'us_stock', symbol: 'AAPL');
    market.quotes['AAPL'] = MarketResponse(
      data: Quote(
        symbol: 'AAPL',
        currency: 'USD',
        price: Decimal.parse('250'),
        // 10 minutes old — past realTimeMaxAge (5min), within delayedMaxAge (30min).
        asOf: clock.now().subtract(const Duration(minutes: 10)),
      ),
      freshness: DataFreshness.live,
      source: 'yfinance',
      fetchedAt: clock.now(),
    );

    final r = await buildResolver().resolve(asset);
    expect(r!.confidence, PriceConfidence.delayed);
  });
}
