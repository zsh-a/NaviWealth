import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  final baseFTheme = brightness == Brightness.dark
      ? FTheme.neutral.dark.desktop
      : FTheme.neutral.light.desktop;
  final fTheme = FThemeData(
    touch: false,
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
      child: AppThemeScope(
        data: resolveAppTheme(
          ThemeInputs(
            brightness: brightness,
            marketMode: MarketColorMode.redUpGreenDown,
          ),
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

    testWidgets('provides fallback semantics and adjustable actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NwLineChart(
            series: [
              ChartSeries(
                name: 'Net worth',
                points: [ChartPoint(x: 0, y: 10), ChartPoint(x: 1, y: 12)],
              ),
            ],
          ),
        ),
      );

      final chartSemantics = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Net worth: 12.0',
      );
      expect(chartSemantics, findsOneWidget);
      final semanticsWidget = tester.widget<Semantics>(chartSemantics);
      expect(semanticsWidget.properties.onIncrease, isNotNull);
      expect(semanticsWidget.properties.onDecrease, isNotNull);
    });

    testWidgets('can hide resting data-point dots for dense trend charts', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            showDots: false,
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
      expect(chart.data.lineBarsData.first.dotData.show, isFalse);
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

    testWidgets('supports linear interpolation', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            interpolation: ChartInterpolation.linear,
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
      expect(chart.data.lineBarsData.first.isCurved, isFalse);
    });

    testWidgets('rebuilds cached chart data when presentation changes', (
      tester,
    ) async {
      const series = [
        ChartSeries(
          name: 'main',
          points: [ChartPoint(x: 0, y: 0), ChartPoint(x: 1, y: 1)],
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          const NwLineChart(
            interpolation: ChartInterpolation.linear,
            series: series,
          ),
        ),
      );
      var chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.isCurved, isFalse);

      await tester.pumpWidget(
        _wrap(
          const NwLineChart(
            interpolation: ChartInterpolation.curved,
            series: series,
          ),
        ),
      );
      chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.isCurved, isTrue);
    });

    testWidgets('curved shorthand overrides interpolation', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            interpolation: ChartInterpolation.curved,
            curved: false,
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
      expect(chart.data.lineBarsData.first.isCurved, isFalse);
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

    testWidgets('touch X label aligns to the selected plot point', (
      tester,
    ) async {
      final days = [
        DateTime(2026, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
      ];
      await tester.pumpWidget(
        _wrap(
          NwLineChart(
            series: [
              ChartSeries(
                name: 'main',
                points: [
                  for (var i = 0; i < days.length; i++)
                    ChartPoint(
                      x: days[i].millisecondsSinceEpoch.toDouble(),
                      y: i.toDouble(),
                    ),
                ],
              ),
            ],
            xAxis: const TimeAxis(format: AxisDateFormat.dayMonth),
            showXAxis: false,
            showTouchXAxisLabel: true,
          ),
        ),
      );

      final chartRect = tester.getRect(find.byType(LineChart));
      const leftAxisWidth = 44.0;
      final expectedCenterX =
          chartRect.left +
          leftAxisWidth +
          (chartRect.width - leftAxisWidth) / 2;
      final gesture = await tester.startGesture(
        Offset(expectedCenterX, chartRect.center.dy),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      await tester.pump();

      // Focused point shows the full, day-resolution date (tooltip
      // header + touch bubble) — not the coarse axis-tick format.
      final label = find.text('Jan 2, 2026');
      expect(label, findsNWidgets(2));
      expect(tester.getCenter(label.last).dx, closeTo(expectedCenterX, 8));

      await gesture.up();
    });

    testWidgets('showYAxis: false removes the left axis gutter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NwLineChart(
            showYAxis: false,
            showTouchXAxisLabel: true,
            series: [
              ChartSeries(
                name: 'main',
                points: [ChartPoint(x: 0, y: 0), ChartPoint(x: 1, y: 1)],
              ),
            ],
          ),
        ),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final leftTitles = chart.data.titlesData.leftTitles.sideTitles;
      expect(leftTitles.showTitles, isFalse);
      expect(leftTitles.reservedSize, 0);
    });

    testWidgets('hides value axis labels in amount privacy mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AmountPrivacyScope(
            hidden: true,
            child: NwLineChart(
              showYAxis: true,
              yAxis: ValueAxis(maxLabels: 3, showGrid: true),
              series: [
                ChartSeries(
                  name: 'private',
                  points: [ChartPoint(x: 0, y: 10), ChartPoint(x: 1, y: 20)],
                ),
              ],
            ),
          ),
        ),
      );

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final leftTitles = chart.data.titlesData.leftTitles.sideTitles;
      expect(leftTitles.showTitles, isFalse);
      expect(leftTitles.reservedSize, 0);
      expect(find.text(AmountPrivacyScope.mask), findsNothing);
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

    testWidgets('describes slices when no semantic label is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NwPieChart(
            slices: [
              Slice(label: 'Stocks', value: 75),
              Slice(label: 'Cash', value: 25),
            ],
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Stocks: 75.0%, Cash: 25.0%',
        ),
        findsOneWidget,
      );
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
