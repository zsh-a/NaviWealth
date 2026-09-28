import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/market/native/market_snapshot_cache.dart';
import 'package:naviwealth/features/finance/data/market/native/native_market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import '../../../../../core/persistence/test_database.dart';
import '../fake_clock.dart';

class _DartMarkets implements MarketDataService {
  int calls = 0;
  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) async {
    calls++;
    return MarketResponse(
      data: Quote(
        symbol: symbol,
        currency: 'USD',
        price: Decimal.one,
        asOf: DateTime.utc(2026),
      ),
      freshness: DataFreshness.live,
      source: 'dartMarkets',
      fetchedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async => throw UnimplementedError();
  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) async {
    calls++;
    return MarketResponse(
      data: const [],
      freshness: DataFreshness.live,
      source: 'dartMarkets-search',
      fetchedAt: DateTime.utc(2026),
    );
  }
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late _DartMarkets dartMarkets;
  late NativeMarketDataService service;
  late Map<String, Object?> Function(Map<String, Object?>) payload;
  var requests = 0;
  var offline = false;

  Map<String, Object?> quote(Map<String, Object?> query) => {
    'symbol': query['symbol'],
    'currency': 'CNY',
    'price': '1234.5678901234',
    'previous_close': '1230.01',
    'observed_at': '2026-04-28T07:00:00Z',
    'previous_close_only': false,
  };
  Map<String, Object?> history(Map<String, Object?> query) => {
    'symbol': query['symbol'],
    'adjustment': 'raw',
    'coverage': {
      'requested_from': query['from'],
      'requested_to': query['to'],
      'first': '2026-04-27',
      'last': '2026-04-28',
      'boundary_check_passed': true,
      'warnings': ['calendar-gap screening'],
    },
    'bars': [
      for (final day in ['2026-04-27', '2026-04-28'])
        {
          'date': day,
          'open': '10',
          'high': '12',
          'low': '9',
          'close': '11',
          'volume_shares': '1000',
        },
    ],
  };
  Future<String> request(String raw) async {
    requests++;
    if (offline) throw Exception('offline');
    final query = Map<String, Object?>.from(jsonDecode(raw) as Map);
    return jsonEncode({
      'version': 1,
      'ok': {
        'data': payload(query),
        'source': 'tencent',
        'fetched_at': clock.now().toIso8601String(),
        'freshness': 'network',
        'warnings': <String>[],
        'attempts': [
          {'kind': 'network', 'provider': 'sina', 'message': 'failed'},
        ],
      },
    });
  }

  NativeMarketDataService create({MarketSnapshotCache? cache}) =>
      NativeMarketDataService(
        dartMarkets: dartMarkets,
        cache: cache ?? MarketSnapshotCache(db),
        clock: clock,
        request: request,
      );
  Future<MarketResponse<List<HistoricalBar>>> getHistory({DateTime? from}) =>
      service.getHistorical(
        '600519',
        from: from ?? DateTime.utc(2026, 4, 27),
        to: DateTime.utc(2026, 4, 28),
        market: AssetMarket.cnA,
      );

  setUp(() {
    db = makeTestDatabase();
    clock = FakeClock();
    dartMarkets = _DartMarkets();
    requests = 0;
    offline = false;
    payload = quote;
    service = create();
  });
  tearDown(() => db.close());

  for (final platform in TargetPlatform.values) {
    test(
      'production registration selects native market on supported platforms: $platform',
      () async {
        final nativeEnabled =
            platform == TargetPlatform.android ||
            platform == TargetPlatform.macOS;
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => db),
            if (nativeEnabled)
              sinaProviderProvider.overrideWith(
                (ref) => throw StateError(
                  'Native routes must not construct the Dart Sina adapter',
                ),
              ),
          ],
        );
        addTearDown(container.dispose);
        final selected = await container.read(marketDataServiceProvider.future);
        expect(
          container.read(marketProviderChainProvider).map((p) => p.name),
          nativeEnabled
              ? ['yfinance', 'coingecko']
              : ['sina', 'yfinance', 'coingecko'],
        );
        expect(selected is NativeMarketDataService, nativeEnabled);
      },
    );
  }

  test(
    'aliases share cache and concurrent fetch; no precision/time loss',
    () async {
      final responses = await Future.wait([
        service.getQuote('600519'),
        service.getQuote('SH600519'),
        service.getQuote('600519.SS'),
      ]);
      expect(requests, 1);
      expect(responses.map((r) => r.data.symbol), [
        '600519',
        'SH600519',
        '600519.SS',
      ]);
      expect(responses.first.diagnostics['canonical_symbol'], '600519.SH');
      expect(responses.first.data.price, Decimal.parse('1234.5678901234'));
      expect(responses.first.data.asOf, DateTime.utc(2026, 4, 28, 7));
      // New service instance proves this is Drift persistence, not a hot map.
      final cached = await create().getQuote('600519.SH');
      expect(cached.freshness, DataFreshness.cachedFresh);
      expect(cached.source, 'tencent');
      expect(cached.diagnostics['attempts'], isNotEmpty);
      expect(requests, 1);
      expect(dartMarkets.calls, 0);
    },
  );

  test('BSE 920 and explicit index namespaces remain distinct', () async {
    expect(canonicalAShare('920002'), '920002.BJ');
    expect(canonicalAShare('000001'), '000001.SZ');
    expect(canonicalAShare('sh000001'), '000001.SH');
    expect((await service.getQuote('920002')).data.symbol, '920002');
  });

  test('offline falls back with original fetch time, then expires', () async {
    final live = await service.getQuote('600519');
    clock.advance(const Duration(days: 2));
    offline = true;
    final stale = await service.getQuote('600519');
    expect(stale.freshness, DataFreshness.stale);
    expect(stale.fetchedAt, live.fetchedAt);
    clock.advance(const Duration(days: 6));
    await expectLater(
      service.getQuote('600519'),
      throwsA(isA<NoMarketDataAvailableException>()),
    );
    expect(dartMarkets.calls, 0);
  });

  test('other markets and metadata retain the dartMarkets route', () async {
    expect((await service.getQuote('AAPL')).source, 'dartMarkets');
    expect(
      (await service.getQuote('600519', market: AssetMarket.usStock)).source,
      'dartMarkets',
    );
    expect(
      (await service.searchSymbol('茅台', market: AssetMarket.cnA)).source,
      'dartMarkets-search',
    );
    expect(requests, 0);
  });

  test(
    'raw history preserves trading dates and coverage across cache reads',
    () async {
      payload = history;
      final live = await getHistory();
      expect(live.data.first.asOf, DateTime.utc(2026, 4, 27));
      expect(live.data.every((bar) => bar.symbol == '600519'), isTrue);
      expect(live.data.first.close, Decimal.fromInt(11));
      expect(live.data.first.adjustedClose, isNull);
      expect(live.diagnostics['adjustment'], 'raw');
      final cached = await getHistory();
      expect(cached.diagnostics['coverage'], live.diagnostics['coverage']);
      expect(cached.freshness, DataFreshness.cachedFresh);
      expect(requests, 1);
    },
  );

  test(
    'different history windows cannot masquerade as cached coverage',
    () async {
      payload = history;
      await getHistory();
      offline = true;
      await expectLater(
        getHistory(from: DateTime.utc(2026, 4, 1)),
        throwsA(isA<NoMarketDataAvailableException>()),
      );
    },
  );

  for (final defect in ['adjustment', 'coverage', 'identity', 'prices']) {
    test('rejects $defect mismatch and does not cache it', () async {
      payload = (query) {
        final result = history(query);
        switch (defect) {
          case 'adjustment':
            result['adjustment'] = 'forward';
          case 'coverage':
            (result['coverage']! as Map)['boundary_check_passed'] = false;
          case 'identity':
            result['symbol'] = '000001.SZ';
          case 'prices':
            ((result['bars']! as List).first as Map)['close'] = '999';
        }
        return result;
      };
      await expectLater(
        getHistory(),
        throwsA(isA<NoMarketDataAvailableException>()),
      );
      expect(await db.select(db.marketDataSnapshots).get(), isEmpty);
    });
  }

  test('cache failure does not discard usable network data', () async {
    service = create(cache: _BrokenCache(db));
    expect((await service.getQuote('600519')).freshness, DataFreshness.live);
  });

  test('unsupported intervals do not enter either upstream chain', () async {
    await expectLater(
      service.getHistorical(
        '600519',
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 4, 28),
        interval: BarInterval.week,
      ),
      throwsUnsupportedError,
    );
    expect(requests, 0);
    expect(dartMarkets.calls, 0);
  });
}

class _BrokenCache extends MarketSnapshotCache {
  _BrokenCache(super.db);
  @override
  Future<String?> read(String key) async => throw Exception('disk read');
  @override
  Future<void> write(String key, String envelope, DateTime fetchedAt) async =>
      throw Exception('disk write');
}
