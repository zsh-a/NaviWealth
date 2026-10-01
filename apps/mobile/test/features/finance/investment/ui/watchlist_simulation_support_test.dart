import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_simulation_projection.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_simulation_support.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';

Decimal _sumOf(Iterable<String> texts) =>
    texts.fold(Decimal.zero, (sum, text) => sum + Decimal.parse(text));

void main() {
  test('quote inputs explain missing or loading snapshots', () {
    final missing = resolveWatchlistSimulationQuoteInputs(
      snapshots: [],
      positions: [_position('AAPL')],
    );
    final loading = resolveWatchlistSimulationQuoteInputs(
      snapshots: [],
      positions: [_position('AAPL')],
      loading: true,
    );
    expect(
      missing.reasonByItemId['AAPL'],
      WatchlistSimulationQuoteUnavailableReason.missing,
    );
    expect(
      loading.reasonByItemId['AAPL'],
      WatchlistSimulationQuoteUnavailableReason.loading,
    );
    expect(missing.changeByItemId['AAPL'], isNull);
    expect(missing.latestQuoteAt, isNull);
  });

  final unusable =
      <WatchlistSimulationQuoteUnavailableReason, WatchlistQuoteSnapshot>{
        WatchlistSimulationQuoteUnavailableReason.loading:
            WatchlistQuoteSnapshot(item: _item('AAPL'), isLoading: true),
        WatchlistSimulationQuoteUnavailableReason.requestFailed:
            WatchlistQuoteSnapshot(
              item: _item('AAPL'),
              error: StateError('unavailable'),
            ),
        WatchlistSimulationQuoteUnavailableReason.stale: _quote(
          'AAPL',
          stale: true,
        ),
        WatchlistSimulationQuoteUnavailableReason.previousCloseMissing: _quote(
          'AAPL',
          previousClose: null,
        ),
        WatchlistSimulationQuoteUnavailableReason.invalid: _quote(
          'AAPL',
          quoteSymbol: 'MSFT',
        ),
      };
  for (final entry in unusable.entries) {
    test('${entry.key} excludes the quote from projection and recording', () {
      final inputs = resolveWatchlistSimulationQuoteInputs(
        snapshots: [entry.value],
        positions: [_position('AAPL')],
      );
      expect(inputs.reasonByItemId['AAPL'], entry.key);
      expect(inputs.changeByItemId['AAPL'], isNull);
      expect(inputs.latestQuoteAt, isNull);
    });
  }
  test('invalid or zero price bases are excluded', () {
    for (final snapshot in [
      _quote('AAPL', price: 0),
      _quote('AAPL', previousClose: -100),
      _quote('AAPL', previousClose: 0),
    ]) {
      final inputs = resolveWatchlistSimulationQuoteInputs(
        snapshots: [snapshot],
        positions: [_position('AAPL')],
      );
      expect(inputs.changeByItemId['AAPL'], isNull);
      expect(inputs.reasonByItemId, isNotEmpty);
    }
  });
  test('only the latest eligible UTC day is shared across holdings', () {
    final inputs = resolveWatchlistSimulationQuoteInputs(
      snapshots: [
        _quote('AAPL', at: DateTime.parse('2026-10-02T00:30:00+08:00')),
        _quote('MSFT', at: DateTime.utc(2026, 10, 2)),
        _quote('OTHER', at: DateTime.utc(2026, 10, 3)),
      ],
      positions: [_position('AAPL'), _position('MSFT')],
    );
    expect(
      inputs.reasonByItemId['AAPL'],
      WatchlistSimulationQuoteUnavailableReason.differentDay,
    );
    expect(inputs.quoteAtByItemId['AAPL']!.toUtc().day, 1);
    expect(inputs.changeByItemId['MSFT'], Decimal.parse('0.01'));
    expect(inputs.latestQuoteAt, DateTime.utc(2026, 10, 2));
  });
  test('a stale newer quote cannot advance the observation day', () {
    final inputs = resolveWatchlistSimulationQuoteInputs(
      snapshots: [
        _quote('AAPL'),
        _quote('MSFT', stale: true, at: DateTime.utc(2026, 10, 3)),
      ],
      positions: [_position('AAPL'), _position('MSFT')],
    );
    expect(inputs.changeByItemId['AAPL'], Decimal.parse('0.01'));
    expect(inputs.latestQuoteAt, DateTime.utc(2026, 10, 1));
  });

  test('A-share provider aliases remain eligible for the same instrument', () {
    for (final (symbol, quoteSymbol) in [
      ('600519', 'SH600519'),
      ('600519.SS', '600519.SH'),
      ('sz000001', '000001.SZ'),
      ('920002', 'BJ920002'),
    ]) {
      final inputs = resolveWatchlistSimulationQuoteInputs(
        snapshots: [
          _quote(symbol, quoteSymbol: quoteSymbol, market: AssetMarket.cnA),
        ],
        positions: [_position(symbol)],
      );
      expect(inputs.changeByItemId[symbol], Decimal.parse('0.01'));
      expect(inputs.reasonByItemId, isEmpty);
    }
  });

  test('different A-share exchanges cannot supply a holding quote', () {
    final inputs = resolveWatchlistSimulationQuoteInputs(
      snapshots: [
        _quote('000001', quoteSymbol: 'SH000001', market: AssetMarket.cnA),
      ],
      positions: [_position('000001')],
    );
    expect(
      inputs.reasonByItemId['000001'],
      WatchlistSimulationQuoteUnavailableReason.invalid,
    );
    expect(inputs.latestQuoteAt, isNull);
  });

  test('equal split prints two decimals that still total the budget', () {
    final texts = watchlistSimulationSplitPercentTexts(
      ids: const ['a', 'b', 'c'],
      totalPercent: Decimal.fromInt(100),
    );

    expect(texts.values, ['33.33', '33.33', '33.34']);
    expect(_sumOf(texts.values), Decimal.fromInt(100));
  });

  test('equal split respects virtual cash', () {
    final texts = watchlistSimulationSplitPercentTexts(
      ids: const ['a', 'b', 'c'],
      totalPercent: Decimal.fromInt(90),
    );

    expect(texts.values, ['30.00', '30.00', '30.00']);
    expect(_sumOf(texts.values) + Decimal.fromInt(10), Decimal.fromInt(100));
  });

  test('equal split is empty without ids', () {
    expect(
      watchlistSimulationSplitPercentTexts(
        ids: const [],
        totalPercent: Decimal.fromInt(100),
      ),
      isEmpty,
    );
  });

  test('snapping stored ratios yields a valid 100% starting state', () {
    final ratios = equalWatchlistSimulationWeights([
      'a',
      'b',
      'c',
      'd',
      'e',
      'f',
    ]);

    final texts = watchlistSimulationSnapPercentTexts(
      ids: ratios.keys.toList(growable: false),
      ratiosById: ratios,
      cashPercentText: '0',
    );

    expect(texts, hasLength(6));
    expect(_sumOf(texts.values), Decimal.fromInt(100));
  });

  test('snapping keeps the cash allocation out of the position budget', () {
    final ratios = <String, Decimal>{
      'a': Decimal.parse('0.33333333'),
      'b': Decimal.parse('0.33333333'),
      'c': Decimal.parse('0.33333334'),
    };

    final texts = watchlistSimulationSnapPercentTexts(
      ids: ratios.keys.toList(growable: false),
      ratiosById: ratios,
      cashPercentText: '10',
    );

    expect(texts.values, ['30.00', '30.00', '30.00']);
    expect(_sumOf(texts.values), Decimal.fromInt(90));
  });

  test('snapping falls back to an equal split when nothing is stored yet', () {
    final texts = watchlistSimulationSnapPercentTexts(
      ids: const ['a', 'b'],
      ratiosById: const {},
      cashPercentText: '20',
    );

    expect(texts.values, ['40.00', '40.00']);
    expect(_sumOf(texts.values), Decimal.fromInt(80));
  });

  test('percent text and ratio conversion round-trip at two decimals', () {
    expect(
      watchlistSimulationPercentText(Decimal.parse('0.16666667')),
      '16.67',
    );
    expect(watchlistSimulationPercentText(Decimal.zero), '0');
    expect(
      watchlistSimulationPercentToRatio(Decimal.parse('16.66')),
      Decimal.parse('0.1666'),
    );
  });

  test('symbol labels fall back to the encoded watchlist item id', () {
    expect(watchlistSimulationSymbolFromId('us_stock:AAPL'), 'AAPL');
    expect(watchlistSimulationSymbolFromId('AAPL'), 'AAPL');
    expect(
      watchlistSimulationSymbolLabel(null, fallbackId: 'hk_stock:0700'),
      '0700',
    );
  });
}

final _sync = SyncMeta(
  ownerUserId: 'owner',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);
WatchlistItem _item(
  String symbol, {
  AssetMarket market = AssetMarket.usStock,
}) => WatchlistItem(
  id: symbol,
  symbol: symbol,
  market: market,
  addedAt: DateTime.utc(2026),
  alertRules: const PriceAlertRules(),
  sync: _sync,
);
WatchlistSimulationPosition _position(String symbol) =>
    WatchlistSimulationPosition(
      id: symbol,
      simulationId: 'simulation',
      watchlistItemId: symbol,
      targetWeight: Decimal.parse('0.5'),
      createdAt: DateTime.utc(2026),
      sync: _sync,
    );
WatchlistQuoteSnapshot _quote(
  String symbol, {
  DateTime? at,
  bool stale = false,
  String? quoteSymbol,
  int price = 101,
  int? previousClose = 100,
  AssetMarket market = AssetMarket.usStock,
}) => WatchlistQuoteSnapshot(
  item: _item(symbol, market: market),
  response: MarketResponse(
    data: Quote(
      symbol: quoteSymbol ?? symbol,
      currency: 'USD',
      price: Decimal.fromInt(price),
      previousClose: previousClose == null
          ? null
          : Decimal.fromInt(previousClose),
      asOf: at ?? DateTime.utc(2026, 10, 1),
    ),
    freshness: stale ? DataFreshness.stale : DataFreshness.live,
    source: 'test',
    fetchedAt: at ?? DateTime.utc(2026, 10, 1),
  ),
);
