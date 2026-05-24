import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/charts/empty_chart_placeholder.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_providers.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/analytics/ui/benchmark/benchmark_comparison_card.dart';
import 'package:naviwealth/features/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _StubBenchmarkSource implements BenchmarkHistorySource {
  _StubBenchmarkSource(this._series);
  final Map<BenchmarkIndex, List<TimeSeriesPoint>> _series;

  @override
  Future<List<TimeSeriesPoint>> seriesFor({
    required BenchmarkIndex index,
    required DateTime from,
    required DateTime to,
  }) async {
    return _series[index] ?? const [];
  }
}

ProviderContainer _container({
  required List<TimeSeriesPoint> portfolio,
  required Map<BenchmarkIndex, List<TimeSeriesPoint>> series,
}) {
  return ProviderContainer(
    overrides: [
      benchmarkComparisonPortfolioSeriesProvider.overrideWith(
        (_) => AsyncValue.data(portfolio),
      ),
      benchmarkHistorySourceProvider.overrideWith(
        (_) async => _StubBenchmarkSource(series),
      ),
      // Pin the range chip so the resolved [DashboardTimeRange] is
      // deterministic — chronologically wrap the fixture data.
      benchmarkComparisonRangeProvider.overrideWith(
        (_) => DashboardRangePreset.y3,
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(child: BenchmarkComparisonCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GlobalMaterialLocalizations.delegate;
    GlobalWidgetsLocalizations.delegate;
    GlobalCupertinoLocalizations.delegate;
  });

  testWidgets(
    'renders chips for every catalogued benchmark and a default selection',
    (tester) async {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 365));
      final container = _container(
        portfolio: [
          TimeSeriesPoint(asOf: from, value: 1000),
          TimeSeriesPoint(asOf: now, value: 1100),
        ],
        series: {
          BenchmarkIndex.hs300: [
            TimeSeriesPoint(asOf: from, value: 4000),
            TimeSeriesPoint(asOf: now, value: 4400),
          ],
        },
      );
      addTearDown(container.dispose);
      await _pump(tester, container);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BenchmarkComparisonCard)),
      );
      expect(find.text(l10n.benchmarkIndexHs300), findsWidgets);
      expect(find.text(l10n.benchmarkIndexSp500), findsOneWidget);
      expect(find.text(l10n.benchmarkIndexNasdaq), findsOneWidget);
      expect(find.text(l10n.benchmarkIndexHsi), findsOneWidget);
      expect(find.text(l10n.benchmarkPortfolioAnnualizedLabel), findsOneWidget);
    },
  );

  testWidgets('toggling a benchmark chip updates the selection state', (
    tester,
  ) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 365));
    final container = _container(
      portfolio: [
        TimeSeriesPoint(asOf: from, value: 1000),
        TimeSeriesPoint(asOf: now, value: 1100),
      ],
      series: {
        BenchmarkIndex.hs300: [
          TimeSeriesPoint(asOf: from, value: 100),
          TimeSeriesPoint(asOf: now, value: 110),
        ],
        BenchmarkIndex.sp500: [
          TimeSeriesPoint(asOf: from, value: 4000),
          TimeSeriesPoint(asOf: now, value: 4500),
        ],
      },
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(BenchmarkComparisonCard)),
    );

    expect(container.read(benchmarkComparisonSelectionProvider), const [
      BenchmarkIndex.hs300,
    ]);
    await tester.tap(find.text(l10n.benchmarkIndexSp500));
    await tester.pumpAndSettle();

    expect(
      container.read(benchmarkComparisonSelectionProvider),
      containsAll(const [BenchmarkIndex.hs300, BenchmarkIndex.sp500]),
    );
  });

  testWidgets('renders the empty state when both sides have no data', (
    tester,
  ) async {
    final container = _container(portfolio: const [], series: const {});
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.byType(EmptyChartPlaceholder), findsOneWidget);
  });
}
