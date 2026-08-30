import 'package:decimal/decimal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_granularity.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_trend_section.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('keeps net worth primary and exposes direct range controls', (
    tester,
  ) async {
    await _setSurface(tester, width: 390);
    await tester.pumpWidget(_wrap(trend: _trend()));
    await tester.pumpAndSettle();

    expect(find.text('Wealth trend'), findsOneWidget);
    expect(_chart(tester).series.single.points.last.y, 1200);
    expect(find.text('Assets'), findsNothing);
    expect(find.text('Liabilities'), findsNothing);

    await tester.tap(find.text('1Y'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3M'));
    await tester.pumpAndSettle();
    expect(find.text('3M'), findsOneWidget);
    expect(_chart(tester).series.single.points.last.y, 1200);
  });

  testWidgets('remains overflow-safe at 320dp and 1.5x text scale', (
    tester,
  ) async {
    await _setSurface(tester, width: 320);
    await tester.pumpWidget(_wrap(trend: _trend(), textScale: 1.5));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wealth-trend-section')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses only the latest complete suffix as the delta baseline', (
    tester,
  ) async {
    await _setSurface(tester, width: 390);
    final trend = _trendWithQualities([
      (100, TrendPointQuality.estimated),
      (1000, TrendPointQuality.complete),
      (1200, TrendPointQuality.complete),
    ]);
    await tester.pumpWidget(_wrap(trend: trend));
    await tester.pumpAndSettle();

    final series = _chart(tester).series.single;
    expect(series.points.map((point) => point.y), [1000, 1200]);
    expect(series.emphasis, SeriesEmphasis.solid);
    expect(find.text('—'), findsNothing);
    expect(find.textContaining('Earlier incomplete'), findsOneWidget);
  });

  testWidgets('estimate-only trend is dashed and has no period delta', (
    tester,
  ) async {
    await _setSurface(tester, width: 390);
    final trend = _trendWithQualities([
      (1000, TrendPointQuality.estimated),
      (1200, TrendPointQuality.estimated),
    ]);
    await tester.pumpWidget(_wrap(trend: trend));
    await tester.pumpAndSettle();

    expect(_chart(tester).series.single.emphasis, SeriesEmphasis.dashed);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('Estimated from cost basis'), findsOneWidget);
  });

  testWidgets('header scrubs the readout and restores the latest value', (
    tester,
  ) async {
    await _setSurface(tester, width: 390);
    await tester.pumpWidget(_wrap(trend: _trend()));
    await tester.pumpAndSettle();

    // Resting: the header readout shows the latest net worth.
    expect(find.text('\$1,200'), findsOneWidget);

    final chartRect = tester.getRect(
      find.byKey(const ValueKey('wealth-trend-chart')),
    );
    final gesture = await tester.startGesture(
      Offset(chartRect.left + 4, chartRect.center.dy),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await tester.pump();

    // While scrubbing, the header shows the scrubbed point's value instead.
    expect(find.text('\$1,000'), findsOneWidget);
    expect(find.text('\$1,200'), findsNothing);

    await gesture.up();
    await tester.pump();
    expect(find.text('\$1,200'), findsOneWidget);
    expect(find.text('\$1,000'), findsNothing);
  });
}

NwLineChart _chart(WidgetTester tester) =>
    tester.widget<NwLineChart>(find.byType(NwLineChart));

Widget _wrap({required DashboardTrend trend, double textScale = 1}) {
  return ProviderScope(
    overrides: [
      dashboardBaseCurrencyProvider.overrideWith((_) => trend.baseCurrency),
      dashboardTrendProvider.overrideWith((_, _) async => trend),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: WealthTrendSection(),
          ),
        ),
      ),
    ),
  );
}

DashboardTrend _trend() {
  final range = DashboardTimeRange.resolve(
    preset: DashboardRangePreset.y1,
    now: DateTime.utc(2026, 7, 12),
  );
  return DashboardTrend(
    range: range,
    baseCurrency: 'USD',
    points: [
      _point(DateTime.utc(2025, 7, 12), assets: 1500, liabilities: 500),
      _point(DateTime.utc(2026, 1, 12), assets: 1650, liabilities: 550),
      _point(DateTime.utc(2026, 7, 12), assets: 1800, liabilities: 600),
    ],
  );
}

DashboardTrend _trendWithQualities(
  List<(int value, TrendPointQuality quality)> values,
) {
  final from = DateTime.utc(2026, 1, 1);
  final to = from.add(Duration(days: values.length - 1));
  return DashboardTrend(
    range: DashboardTimeRange(
      preset: DashboardRangePreset.custom,
      from: from,
      to: to,
      granularity: NetWorthGranularity.day,
    ),
    baseCurrency: 'USD',
    points: [
      for (var i = 0; i < values.length; i++)
        TrendPoint(
          asOf: from.add(Duration(days: i)),
          assets: Money(Decimal.fromInt(values[i].$1), 'USD'),
          liabilities: Money.zero('USD'),
          netWorth: Money(Decimal.fromInt(values[i].$1), 'USD'),
          quality: values[i].$2,
        ),
    ],
  );
}

TrendPoint _point(
  DateTime asOf, {
  required int assets,
  required int liabilities,
}) {
  final assetMoney = Money(Decimal.fromInt(assets), 'USD');
  final liabilityMoney = Money(Decimal.fromInt(liabilities), 'USD');
  return TrendPoint(
    asOf: asOf,
    assets: assetMoney,
    liabilities: liabilityMoney,
    netWorth: assetMoney - liabilityMoney,
  );
}

Future<void> _setSurface(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
