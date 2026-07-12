import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_trend_section.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('switches between net worth, asset, and liability series', (
    tester,
  ) async {
    await _setSurface(tester, width: 390);
    await tester.pumpWidget(_wrap(trend: _trend()));
    await tester.pumpAndSettle();

    expect(find.text('Wealth trend'), findsOneWidget);
    expect(_chart(tester).series.single.points.last.y, 1200);

    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(_chart(tester).series.single.points.last.y, 1800);

    await tester.tap(find.text('Liabilities'));
    await tester.pumpAndSettle();
    expect(_chart(tester).series.single.points.last.y, 600);

    await tester.tap(find.text('3M'));
    await tester.pumpAndSettle();
    final range = tester.widget<SegmentedRow<DashboardRangePreset>>(
      find.byType(SegmentedRow<DashboardRangePreset>),
    );
    expect(range.value, DashboardRangePreset.m3);
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
}

NwLineChart _chart(WidgetTester tester) =>
    tester.widget<NwLineChart>(find.byType(NwLineChart));

Widget _wrap({required DashboardTrend trend, double textScale = 1}) {
  return ProviderScope(
    overrides: [
      dashboardBaseCurrencyProvider.overrideWith((_) => trend.baseCurrency),
      dashboardTrendProvider.overrideWith((_) async => trend),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.s16),
          child: WealthTrendSection(),
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
