import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/services/market_data_service.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/finance/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/finance/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';

class _FakeMarketData implements MarketDataService {
  _FakeMarketData({this.bars = const [], this.error});

  final List<HistoricalBar> bars;
  final MarketDataException? error;
  String? lastSymbol;
  AssetMarket? lastMarket;
  DateTime? lastFrom;
  DateTime? lastTo;

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    lastSymbol = symbol;
    lastMarket = market;
    lastFrom = from;
    lastTo = to;
    if (error != null) throw error!;
    return MarketResponse(
      data: bars,
      freshness: DataFreshness.live,
      source: 'fake',
      fetchedAt: DateTime.utc(2025, 1, 1),
    );
  }

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) => throw UnimplementedError();

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) => throw UnimplementedError();
}

HistoricalBar _bar(DateTime d, String close, {String? adj}) {
  return HistoricalBar(
    symbol: 'X',
    asOf: d,
    open: Decimal.parse(close),
    high: Decimal.parse(close),
    low: Decimal.parse(close),
    close: Decimal.parse(close),
    adjustedClose: adj == null ? null : Decimal.parse(adj),
  );
}

void main() {
  test(
    'routes to MarketDataService with the catalogue symbol + market',
    () async {
      final fake = _FakeMarketData(
        bars: [
          _bar(DateTime.utc(2024, 1, 2), '4750'),
          _bar(DateTime.utc(2024, 6, 1), '5200'),
        ],
      );
      final source = MarketDataBenchmarkHistorySource(marketData: fake);
      final from = DateTime.utc(2024, 1, 1);
      final to = DateTime.utc(2024, 12, 31);

      final points = await source.seriesFor(
        index: BenchmarkIndex.sp500,
        from: from,
        to: to,
      );

      expect(fake.lastSymbol, '^GSPC');
      expect(fake.lastMarket, AssetMarket.usStock);
      expect(fake.lastFrom, from);
      expect(fake.lastTo, to);
      expect(points, hasLength(2));
      expect(points.first.value, 4750);
    },
  );

  test('prefers adjustedClose when present', () async {
    final fake = _FakeMarketData(
      bars: [_bar(DateTime.utc(2024, 1, 2), '100', adj: '95')],
    );
    final source = MarketDataBenchmarkHistorySource(marketData: fake);
    final points = await source.seriesFor(
      index: BenchmarkIndex.sp500,
      from: DateTime.utc(2024, 1, 1),
      to: DateTime.utc(2024, 12, 31),
    );
    expect(points.single.value, 95);
  });

  test('returns empty list on NoMarketDataAvailableException', () async {
    final source = MarketDataBenchmarkHistorySource(
      marketData: _FakeMarketData(
        error: const NoMarketDataAvailableException('offline'),
      ),
    );
    final points = await source.seriesFor(
      index: BenchmarkIndex.hsi,
      from: DateTime.utc(2024, 1, 1),
      to: DateTime.utc(2024, 12, 31),
    );
    expect(points, isEmpty);
  });

  test('returns empty list on generic MarketDataException', () async {
    final source = MarketDataBenchmarkHistorySource(
      marketData: _FakeMarketData(
        error: const ProviderResponseException('malformed', provider: 'fake'),
      ),
    );
    final points = await source.seriesFor(
      index: BenchmarkIndex.hs300,
      from: DateTime.utc(2024, 1, 1),
      to: DateTime.utc(2024, 12, 31),
    );
    expect(points, isEmpty);
  });
}
