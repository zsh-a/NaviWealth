import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  final baseFTheme = FTheme.neutral.light.desktop;
  final fTheme = FThemeData(
    touch: false,
    colors: baseFTheme.colors.copyWith(
      primary: AccentColors.primary(Brightness.light),
      primaryForeground: AccentColors.onPrimary(Brightness.light),
      background: const Color(0xFFF5F7F9),
    ),
  );
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: FTheme(
        data: fTheme,
        child: AppThemeScope(
          data: resolveAppTheme(
            const ThemeInputs(
              brightness: Brightness.light,
              marketMode: MarketColorMode.redUpGreenDown,
            ),
          ),
          child: Scaffold(
            body: SizedBox(width: 400, height: 250, child: child),
          ),
        ),
      ),
    ),
  );
}

const _barSeries = [
  CategorySeries(
    name: 'spend',
    data: [CategoryDatum(label: 'Mon', value: 10)],
  ),
];

const _slices = [Slice(label: 'a', value: 1), Slice(label: 'b', value: 2)];

void main() {
  group('NwBarChart entrance', () {
    testWidgets('plays a one-shot draw-in on first paint', (tester) async {
      await tester.pumpWidget(_wrap(const NwBarChart(series: _barSeries)));

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);

      await tester.pump(Motion.chartEnter);
      await tester.pump();

      // The reveal is a visual mask only: the chart never leaves the tree.
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('does not replay the reveal on rebuild', (tester) async {
      await tester.pumpWidget(_wrap(const NwBarChart(series: _barSeries)));
      await tester.pumpAndSettle();

      // Same State, new widget instance — the reveal must not restart.
      await tester.pumpWidget(_wrap(const NwBarChart(series: _barSeries)));
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('renders fully under reduce-motion', (tester) async {
      await tester.pumpWidget(
        _wrap(const NwBarChart(series: _barSeries), disableAnimations: true),
      );
      await tester.pump();

      expect(find.byType(BarChart), findsOneWidget);
    });
  });

  group('NwPieChart entrance', () {
    testWidgets('plays a one-shot radial draw-in on first paint', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NwPieChart(slices: _slices)));

      expect(find.byType(PieChart), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);

      await tester.pump(Motion.chartEnter);
      await tester.pump();

      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('does not replay the reveal on rebuild', (tester) async {
      await tester.pumpWidget(_wrap(const NwPieChart(slices: _slices)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const NwPieChart(slices: _slices)));
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('renders fully under reduce-motion', (tester) async {
      await tester.pumpWidget(
        _wrap(const NwPieChart(slices: _slices), disableAnimations: true),
      );
      await tester.pump();

      expect(find.byType(PieChart), findsOneWidget);
    });
  });
}
