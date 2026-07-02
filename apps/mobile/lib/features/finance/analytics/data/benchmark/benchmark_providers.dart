import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';

import '../../domain/benchmark/benchmark_comparison.dart';
import '../../domain/benchmark/benchmark_index.dart';
import 'benchmark_history_source.dart';

/// Currently active range preset for the benchmark comparison card. Lives
/// independently from [dashboardSelectedRangeProvider] so the analytics
/// surface and the home dashboard don't fight over the same chip state.
final benchmarkComparisonRangeProvider = StateProvider<DashboardRangePreset>(
  (ref) => DashboardRangePreset.y1,
);

/// Custom-range state used when [benchmarkComparisonRangeProvider] resolves
/// to [DashboardRangePreset.custom]. Mirrors the dashboard's pair shape so
/// the chip pickers can share helpers.
final benchmarkComparisonCustomRangeProvider =
    StateProvider<({DateTime from, DateTime to})?>((ref) => null);

/// User's currently picked benchmark indices. Defaults to a single entry
/// (HS 300) so the card has something to render on first paint without
/// blocking on multi-select. Held as a list rather than a set so chip
/// position colors stay stable across rebuilds.
final benchmarkComparisonSelectionProvider =
    StateProvider<List<BenchmarkIndex>>((ref) => const [BenchmarkIndex.hs300]);

/// Resolved [DashboardTimeRange] for the comparison card. Recomputes
/// whenever the preset / custom range changes.
final benchmarkComparisonTimeRangeProvider = Provider<DashboardTimeRange>((
  ref,
) {
  final preset = ref.watch(benchmarkComparisonRangeProvider);
  final custom = ref.watch(benchmarkComparisonCustomRangeProvider);
  return DashboardTimeRange.resolve(
    preset: preset,
    now: DateTime.now(),
    customFrom: custom?.from,
    customTo: custom?.to,
  );
});

/// Net-worth time series the comparison chart treats as the "portfolio"
/// curve. Reuses [DashboardTrendBuilder] — once the postings-derived
/// return read model is wired through Riverpod, the headline annualized
/// return can be overridden via
/// [BenchmarkComparisonService.compute]'s `overridePortfolioAnnualizedReturn`
/// while keeping this curve as the chart series.
final benchmarkComparisonPortfolioSeriesProvider =
    Provider<AsyncValue<List<TimeSeriesPoint>>>((ref) {
      final manual = ref.watch(dashboardManualAssetValuationsProvider);
      final physical = ref.watch(physicalAssetsListProvider);
      final liab = ref.watch(liabilitiesStreamProvider);
      final converter = ref.watch(dashboardCurrencyConverterProvider);
      final base = ref.watch(dashboardBaseCurrencyProvider);
      final range = ref.watch(benchmarkComparisonTimeRangeProvider);
      final schedules = ref.watch(dashboardLiabilitySchedulesProvider);

      if (manual.isLoading || physical.isLoading || liab.isLoading) {
        return const AsyncValue.loading();
      }
      final err = manual.error ?? physical.error ?? liab.error;
      if (err != null) {
        return AsyncValue.error(
          err,
          manual.stackTrace ??
              physical.stackTrace ??
              liab.stackTrace ??
              StackTrace.current,
        );
      }
      final builder = DashboardTrendBuilder(
        converter: converter,
        baseCurrency: base,
      );
      final trend = builder.build(
        range: range,
        manualAssets: manual.value ?? const [],
        physicalAssets: physical.value ?? const <PhysicalAsset>[],
        liabilities: liab.value ?? const <Liability>[],
        liabilitySchedules: schedules,
      );
      final points = [
        for (final point in trend.points)
          TimeSeriesPoint(
            asOf: point.asOf,
            value: point.netWorth.amount.toDouble(),
          ),
      ];
      return AsyncValue.data(points);
    });

/// Override hook for the [BenchmarkHistorySource]. Production wiring uses
/// the workspace [MarketDataService]; tests inject in-memory fakes.
final benchmarkHistorySourceProvider = FutureProvider<BenchmarkHistorySource>((
  ref,
) async {
  final marketData = await ref.watch(marketDataServiceProvider.future);
  return MarketDataBenchmarkHistorySource(marketData: marketData);
});

/// Per-benchmark historical price series. The auto-disposing family keys
/// the cache on the [BenchmarkIndex]; the date range is read inside the
/// provider so a range change naturally invalidates the call site via
/// `ref.watch(benchmarkComparisonTimeRangeProvider)`.
final benchmarkSeriesProvider = FutureProvider.autoDispose
    .family<List<TimeSeriesPoint>, BenchmarkIndex>((ref, index) async {
      final range = ref.watch(benchmarkComparisonTimeRangeProvider);
      final source = await ref.watch(benchmarkHistorySourceProvider.future);
      return source.seriesFor(index: index, from: range.from, to: range.to);
    });

/// Composite comparison result. Watches the portfolio curve + every
/// selected benchmark and runs the pure [BenchmarkComparisonService] to
/// produce the chart-ready output.
final benchmarkComparisonResultProvider =
    FutureProvider.autoDispose<BenchmarkComparisonResult>((ref) async {
      final range = ref.watch(benchmarkComparisonTimeRangeProvider);
      final selection = ref.watch(benchmarkComparisonSelectionProvider);
      final portfolioAsync = ref.watch(
        benchmarkComparisonPortfolioSeriesProvider,
      );
      final portfolio = await portfolioAsync.when(
        data: (d) => Future<List<TimeSeriesPoint>>.value(d),
        loading: () => Future<List<TimeSeriesPoint>>.value(const []),
        error: (e, st) => Future<List<TimeSeriesPoint>>.error(e, st),
      );
      final benchmarks = <BenchmarkIndex, List<TimeSeriesPoint>>{};
      for (final index in selection) {
        benchmarks[index] = await ref.watch(
          benchmarkSeriesProvider(index).future,
        );
      }
      return const BenchmarkComparisonService().compute(
        from: range.from,
        to: range.to,
        portfolio: portfolio,
        benchmarks: benchmarks,
        order: selection,
      );
    });
