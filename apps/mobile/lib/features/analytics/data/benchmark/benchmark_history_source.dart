import '../../../../core/logging/app_logger.dart';
import '../../../../domain/entities/historical_bar.dart';
import '../../../../domain/services/market_data_service.dart';
import '../../../../features/finance/data/market/exceptions.dart';
import '../../domain/benchmark/benchmark_comparison.dart';
import '../../domain/benchmark/benchmark_index.dart';

/// Pulls historical price paths for [BenchmarkIndex] instances. Decoupled
/// from [MarketDataService] so the comparison feature can run in tests
/// against an in-memory fake without the composite cache / provider chain.
abstract class BenchmarkHistorySource {
  /// Daily closes for [index] in `[from, to]` (inclusive, UTC). The
  /// returned list is sorted ascending by date and may be empty when the
  /// provider has no coverage. Implementations must not throw on missing
  /// data — return `[]` and let the comparison service render the empty
  /// state.
  Future<List<TimeSeriesPoint>> seriesFor({
    required BenchmarkIndex index,
    required DateTime from,
    required DateTime to,
  });
}

/// Default [BenchmarkHistorySource] backed by the workspace
/// [MarketDataService]. Bars are converted to closes using
/// `adjustedClose` when present (to neutralize splits / dividends on
/// foreign indices) and falling back to `close`.
class MarketDataBenchmarkHistorySource implements BenchmarkHistorySource {
  MarketDataBenchmarkHistorySource({required MarketDataService marketData})
    : _marketData = marketData;

  final MarketDataService _marketData;

  @override
  Future<List<TimeSeriesPoint>> seriesFor({
    required BenchmarkIndex index,
    required DateTime from,
    required DateTime to,
  }) async {
    final info = benchmarkInfoFor(index);
    try {
      final response = await _marketData.getHistorical(
        info.symbol,
        from: from,
        to: to,
        interval: BarInterval.day,
        market: info.market,
      );
      return _toPoints(response.data);
    } on NoMarketDataAvailableException catch (e) {
      AppLogger.instance.w(
        'Benchmark ${index.name} (${info.symbol}) has no market-data coverage: $e',
      );
      return const [];
    } on MarketDataException catch (e) {
      AppLogger.instance.w(
        'Benchmark ${index.name} (${info.symbol}) failed to load: $e',
      );
      return const [];
    }
  }

  static List<TimeSeriesPoint> _toPoints(Iterable<HistoricalBar> bars) {
    final out = <TimeSeriesPoint>[];
    for (final bar in bars) {
      final close = bar.adjustedClose ?? bar.close;
      out.add(TimeSeriesPoint(asOf: bar.asOf, value: close.toDouble()));
    }
    return out;
  }
}
