import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/allocation_summary.dart';
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

DashboardSnapshot _wideSnapshot() {
  const currency = 'CNY';
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 14),
    baseCurrency: currency,
    allocations: [
      _allocation(AssetCategory.stock, '5000', currency),
      _allocation(AssetCategory.cash, '3000', currency),
      _allocation(AssetCategory.etf, '2000', currency),
      _allocation(AssetCategory.crypto, '1000', currency),
      _allocation(AssetCategory.realEstate, '500', currency),
    ],
    totalAssets: Money(Decimal.parse('11500'), currency),
    totalLiabilities: Money.zero(currency),
    netWorth: Money(Decimal.parse('11500'), currency),
  );
}

CategoryAllocation _allocation(
  AssetCategory category,
  String amount,
  String currency,
) {
  return CategoryAllocation(
    category: category,
    totalInBase: Money(Decimal.parse(amount), currency),
    items: [
      CategoryItem(
        id: category.name,
        name: category.name,
        subtitle: null,
        valueInBase: Money(Decimal.parse(amount), currency),
        nativeAmount: Decimal.parse(amount),
        nativeCurrency: currency,
      ),
    ],
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
  testWidgets('aggregates smaller allocation rows into Other', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(AllocationSummary(snapshot: _wideSnapshot())),
    );

    expect(find.text('Stocks'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('ETFs'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Crypto'), findsNothing);
    expect(find.text('Real estate'), findsNothing);
  });

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

  testWidgets('view breakdown opens mobile allocation sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(429, 673));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(AllocationSummary(snapshot: _snapshot())));

    await tester.tap(find.text('View breakdown'));
    await tester.pumpAndSettle();

    expect(find.text('Asset allocation'), findsOneWidget);
    expect(find.text('Class'), findsOneWidget);
    expect(find.text('Cash'), findsWidgets);
  });
}
