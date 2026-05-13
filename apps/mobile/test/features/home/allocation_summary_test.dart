import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/home/ui/allocation_summary.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

DashboardSnapshot _snapshot() {
  const currency = 'CNY';
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 14),
    baseCurrency: currency,
    allocations: [
      CategoryAllocation(
        category: AssetCategory.cash,
        totalInBase: Money(Decimal.parse('9000'), currency),
        items: [
          CategoryItem(
            id: 'cash',
            name: 'Cash',
            subtitle: null,
            valueInBase: Money(Decimal.parse('9000'), currency),
            nativeAmount: Decimal.parse('9000'),
            nativeCurrency: currency,
          ),
        ],
      ),
      CategoryAllocation(
        category: AssetCategory.stock,
        totalInBase: Money(Decimal.parse('1000'), currency),
        items: [
          CategoryItem(
            id: 'aapl',
            name: 'AAPL',
            subtitle: '10 · USD',
            valueInBase: Money(Decimal.parse('1000'), currency),
            nativeAmount: Decimal.parse('140'),
            nativeCurrency: 'USD',
          ),
        ],
      ),
    ],
    totalAssets: Money(Decimal.parse('10000'), currency),
    totalLiabilities: Money.zero(currency),
    netWorth: Money(Decimal.parse('10000'), currency),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: FTheme(
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('view breakdown opens allocation detail panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(AllocationSummary(snapshot: _snapshot())));

    await tester.tap(find.text('View breakdown'));
    await tester.pumpAndSettle();

    expect(find.text('Asset allocation'), findsOneWidget);
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Cash'), findsWidgets);
    await tester.tap(find.text('Stocks').last);
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsOneWidget);
  });
}
