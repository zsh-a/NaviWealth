import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: Scaffold(body: SizedBox(width: 400, height: 250, child: child)),
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
        _wrap(NwLineChart(
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
        )),
      );
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets(
        'auto-downsamples when series exceeds default target',
        (tester) async {
      // 1800 points should compact to <= 500.
      late LineChart captured;
      await tester.pumpWidget(
        _wrap(NwLineChart(
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
        )),
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
        _wrap(NwLineChart(
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
        )),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.spots.length, 800);
    });

    testWidgets('uses theme primary color for SeriesIntent.primary', (
      tester,
    ) async {
      late ColorScheme scheme;
      await tester.pumpWidget(
        _wrap(Builder(builder: (ctx) {
          scheme = Theme.of(ctx).colorScheme;
          return const NwLineChart(
            series: [
              ChartSeries(
                name: 'p',
                points: [
                  ChartPoint(x: 0, y: 0),
                  ChartPoint(x: 1, y: 1),
                ],
              ),
            ],
          );
        })),
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.color, scheme.primary);
    });

    testWidgets('projection intent renders dashed', (tester) async {
      await tester.pumpWidget(_wrap(const NwLineChart(
        series: [
          ChartSeries(
            name: 'projection',
            intent: SeriesIntent.projection,
            points: [
              ChartPoint(x: 0, y: 0),
              ChartPoint(x: 1, y: 1),
            ],
          ),
        ],
      )));
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.dashArray, isNotNull);
    });
  });

  group('NwAreaChart', () {
    testWidgets('stacked: true accumulates Y across series', (tester) async {
      await tester.pumpWidget(_wrap(const NwAreaChart(
        stacked: true,
        series: [
          ChartSeries(
            name: 'a',
            points: [
              ChartPoint(x: 0, y: 1),
              ChartPoint(x: 1, y: 1),
            ],
          ),
          ChartSeries(
            name: 'b',
            points: [
              ChartPoint(x: 0, y: 2),
              ChartPoint(x: 1, y: 2),
            ],
          ),
        ],
      )));
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      // Top series should be at 3 (1+2), not 2.
      final topSpots = chart.data.lineBarsData.last.spots;
      expect(topSpots.first.y, 3);
      expect(topSpots.last.y, 3);
    });
  });

  group('NwBarChart', () {
    testWidgets('renders one group per category', (tester) async {
      await tester.pumpWidget(_wrap(const NwBarChart(
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
      )));
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.length, 3);
    });

    testWidgets('stacked: true builds rod stack items', (tester) async {
      await tester.pumpWidget(_wrap(const NwBarChart(
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
      )));
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
      await tester.pumpWidget(_wrap(const NwPieChart(
        slices: [
          Slice(label: 'Stocks', value: 60),
          Slice(label: 'Bonds', value: 30),
          Slice(label: 'Cash', value: 10),
        ],
      )));
      final pie = tester.widget<PieChart>(find.byType(PieChart));
      expect(pie.data.sections.length, 3);
    });

    testWidgets('hides label on slices below minLabelPercent', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NwPieChart(
        minLabelPercent: 5,
        slices: [
          Slice(label: 'Big', value: 95),
          Slice(label: 'Tiny', value: 2),
          Slice(label: 'Mid', value: 3),
        ],
      )));
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
      await tester.pumpWidget(_wrap(const NwPieChart(slices: [
        Slice(label: 'a', value: 0),
        Slice(label: 'b', value: 0),
      ])));
      expect(find.byType(EmptyChartPlaceholder), findsOneWidget);
    });
  });
}
