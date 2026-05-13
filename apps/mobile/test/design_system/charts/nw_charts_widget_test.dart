import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  final baseFTheme = brightness == Brightness.dark
      ? FThemes.slate.dark.desktop
      : FThemes.slate.light.desktop;
  final fTheme = baseFTheme.copyWith(
    colors: baseFTheme.colors.copyWith(
      primary: AccentColors.primary(brightness),
      primaryForeground: AccentColors.onPrimary(brightness),
      background: brightness == Brightness.dark
          ? baseFTheme.colors.background
          : const Color(0xFFF5F7F9),
    ),
  );
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: FTheme(
      data: fTheme,
      child: MarketColorsScope(
        colors: MarketColors.fromMode(
          MarketColorMode.redUpGreenDown,
          brightness: brightness,
        ),
        child: Scaffold(body: SizedBox(width: 400, height: 250, child: child)),
      ),
    ),
  );
}

void main() {
  group('NwLineChart', () {
    testWidgets('renders empty placeholder when no series have points', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NwLineChart(series: [])));
      expect(find.byType(EmptyChartPlaceholder), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('renders LineChart for non-empty series', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            series: [
              ChartSeries(
                name: 'main',
                points: List.generate(
                  10,
                  (i) => ChartPoint(x: i.toDouble(), y: i.toDouble()),
                ),
              ),
            ],
            xAxis: const TimeAxis(format: AxisDateFormat.yearOnly),
          ),
        ),
      );
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('auto-downsamples when series exceeds default target', (
      tester,
    ) async {
      // 1800 points should compact to <= 500.
      late LineChart captured;
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            series: [
              ChartSeries(
                name: 'main',
                points: List.generate(
                  1800,
                  (i) => ChartPoint(x: i.toDouble(), y: i.toDouble()),
                ),
              ),
            ],
            xAxis: const TimeAxis(format: AxisDateFormat.yearOnly),
          ),
        ),
      );
      captured = tester.widget<LineChart>(find.byType(LineChart));
      expect(
        captured.data.lineBarsData.first.spots.length,
        lessThanOrEqualTo(500),
      );
    });

    testWidgets('downsample: false preserves the original spot count', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            downsample: false,
            series: [
              ChartSeries(
                name: 'main',
                points: List.generate(
                  800,
                  (i) => ChartPoint(x: i.toDouble(), y: i.toDouble()),
                ),
              ),
            ],
            xAxis: const TimeAxis(format: AxisDateFormat.yearOnly),
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.spots.length, 800);
    });

    testWidgets('uses theme primary color for SeriesIntent.primary', (
      tester,
    ) async {
      late ColorScheme scheme;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) {
              scheme = Theme.of(ctx).colorScheme;
              return const NwLineChart(
                series: [
                  ChartSeries(
                    name: 'p',
                    points: [ChartPoint(x: 0, y: 0), ChartPoint(x: 1, y: 1)],
                  ),
                ],
              );
            },
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.color, scheme.primary);
    });

    testWidgets('projection intent renders dashed', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwLineChart(
            series: [
              ChartSeries(
                name: 'projection',
                intent: SeriesIntent.projection,
                points: [ChartPoint(x: 0, y: 0), ChartPoint(x: 1, y: 1)],
              ),
            ],
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.dashArray, isNotNull);
    });

    testWidgets('renders curved lines by default', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            series: [
              ChartSeries(
                name: 'main',
                points: List.generate(
                  10,
                  (i) => ChartPoint(x: i.toDouble(), y: i.toDouble()),
                ),
              ),
            ],
            xAxis: const TimeAxis(format: AxisDateFormat.yearOnly),
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.isCurved, isTrue);
    });

    testWidgets('filled: true uses gradient for area fill', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            filled: true,
            series: [
              ChartSeries(
                name: 'area',
                points: List.generate(
                  5,
                  (i) => ChartPoint(x: i.toDouble(), y: i * 10.0),
                ),
              ),
            ],
            xAxis: const TimeAxis(format: AxisDateFormat.yearOnly),
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final bar = chart.data.lineBarsData.first;
      expect(bar.belowBarData.show, isTrue);
      expect(bar.belowBarData.gradient, isNotNull);
    });

    testWidgets('multi-series: comparison series have reduced opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            series: [
              ChartSeries(
                name: 'primary',
                points: List.generate(
                  5,
                  (i) => ChartPoint(x: i.toDouble(), y: i * 10.0),
                ),
              ),
              ChartSeries(
                name: 'benchmark',
                intent: SeriesIntent.benchmark,
                points: List.generate(
                  5,
                  (i) => ChartPoint(x: i.toDouble(), y: i * 5.0),
                ),
              ),
            ],
            xAxis: const TimeAxis(format: AxisDateFormat.yearOnly),
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      // Primary series should be at full opacity.
      final primary = chart.data.lineBarsData[0];
      expect(primary.color!.a, closeTo(1.0, 0.01));
      // Comparison series should be at 60% opacity.
      final comparison = chart.data.lineBarsData[1];
      expect(comparison.color!.a, closeTo(0.6, 0.05));
      expect(comparison.dashArray, isNotNull);
    });

    testWidgets('ValueAxis.showGrid defaults to false', (tester) async {
      late ValueAxis captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) {
              captured = const ValueAxis();
              return const NwLineChart(
                series: [
                  ChartSeries(
                    name: 'p',
                    points: [ChartPoint(x: 0, y: 0), ChartPoint(x: 1, y: 1)],
                  ),
                ],
              );
            },
          ),
        ),
      );
      expect(captured.showGrid, isFalse);
    });
  });

  group('NwAreaChart', () {
    testWidgets('stacked: true accumulates Y across series', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwAreaChart(
            stacked: true,
            series: [
              ChartSeries(
                name: 'a',
                points: [ChartPoint(x: 0, y: 1), ChartPoint(x: 1, y: 1)],
              ),
              ChartSeries(
                name: 'b',
                points: [ChartPoint(x: 0, y: 2), ChartPoint(x: 1, y: 2)],
              ),
            ],
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      // Top series should be at 3 (1+2), not 2.
      final topSpots = chart.data.lineBarsData.last.spots;
      expect(topSpots.first.y, 3);
      expect(topSpots.last.y, 3);
    });
  });

  group('NwBarChart', () {
    testWidgets('renders one group per category', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwBarChart(
            series: [
              CategorySeries(
                name: 's',
                data: [
                  CategoryDatum(label: 'Q1', value: 10),
                  CategoryDatum(label: 'Q2', value: 20),
                  CategoryDatum(label: 'Q3', value: 15),
                ],
              ),
            ],
          ),
        ),
      );
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 3);
    });

    testWidgets('stacked: true builds rod stack items', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwBarChart(
            stacked: true,
            series: [
              CategorySeries(
                name: 's1',
                data: [CategoryDatum(label: 'Q1', value: 10)],
              ),
              CategorySeries(
                name: 's2',
                data: [CategoryDatum(label: 'Q1', value: 5)],
              ),
            ],
          ),
        ),
      );
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final rod = chart.data.barGroups.first.barRods.first;
      expect(rod.rodStackItems.length, 2);
      expect(rod.toY, 15);
    });

    testWidgets('empty series → placeholder', (tester) async {
      await tester.pumpWidget(_wrap(const NwBarChart(series: [])));
      expect(find.byType(EmptyChartPlaceholder), findsOneWidget);
    });
  });

  group('NwPieChart', () {
    testWidgets('renders one section per slice', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwPieChart(
            slices: [
              Slice(label: 'Stocks', value: 60),
              Slice(label: 'Bonds', value: 30),
              Slice(label: 'Cash', value: 10),
            ],
          ),
        ),
      );
      final pie = tester.widget<PieChart>(find.byType(PieChart));
      expect(pie.data.sections.length, 3);
    });

    testWidgets('hides label on slices below minLabelPercent', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwPieChart(
            minLabelPercent: 5,
            slices: [
              Slice(label: 'Big', value: 95),
              Slice(label: 'Tiny', value: 2),
              Slice(label: 'Mid', value: 3),
            ],
          ),
        ),
      );
      final pie = tester.widget<PieChart>(find.byType(PieChart));
      // Sum = 100. Tiny=2% and Mid=3% are both below 5% threshold.
      expect(pie.data.sections[0].title, isNotEmpty);
      expect(pie.data.sections[1].title, isEmpty);
      expect(pie.data.sections[2].title, isEmpty);
    });

    testWidgets('empty slices → placeholder', (tester) async {
      await tester.pumpWidget(_wrap(const NwPieChart(slices: [])));
      expect(find.byType(EmptyChartPlaceholder), findsOneWidget);
    });

    testWidgets('all-zero slices → placeholder', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwPieChart(
            slices: [
              Slice(label: 'a', value: 0),
              Slice(label: 'b', value: 0),
            ],
          ),
        ),
      );
      expect(find.byType(EmptyChartPlaceholder), findsOneWidget);
    });

    testWidgets('center slot shows total by default', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwPieChart(
            slices: [
              Slice(label: 'Stocks', value: 60),
              Slice(label: 'Bonds', value: 30),
              Slice(label: 'Cash', value: 10),
            ],
          ),
        ),
      );
      // Total = 100, should display "100" and "Total" in center.
      expect(find.text('100'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('sectionsSpace defaults to 3', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NwPieChart(
            slices: [
              Slice(label: 'A', value: 50),
              Slice(label: 'B', value: 50),
            ],
          ),
        ),
      );
      final pie = tester.widget<PieChart>(find.byType(PieChart));
      expect(pie.data.sectionsSpace, 3);
    });

    testWidgets('hole defaults to 0.62', (tester) async {
      // Verify the default hole value by checking centerSpaceRadius.
      // centerSpaceRadius = hole * 80 = 0.62 * 80 = 49.6
      await tester.pumpWidget(
        _wrap(
          const NwPieChart(
            slices: [
              Slice(label: 'A', value: 50),
              Slice(label: 'B', value: 50),
            ],
          ),
        ),
      );
      final pie = tester.widget<PieChart>(find.byType(PieChart));
      expect(pie.data.centerSpaceRadius, closeTo(49.6, 0.1));
    });
  });
}
