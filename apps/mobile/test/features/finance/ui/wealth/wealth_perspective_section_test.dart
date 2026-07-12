import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_perspective_section.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Money _cny(String amount) => Money(Decimal.parse(amount), 'CNY');

DashboardSnapshot _snapshot() {
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 24),
    baseCurrency: 'CNY',
    allocations: [
      CategoryAllocation(
        category: AssetCategory.stock,
        totalInBase: _cny('20000'),
        items: [
          CategoryItem(
            id: 'aapl',
            name: 'AAPL',
            subtitle: null,
            valueInBase: _cny('12000'),
            nativeAmount: Decimal.parse('160'),
            nativeCurrency: 'USD',
          ),
          CategoryItem(
            id: '600519',
            name: 'Moutai',
            subtitle: null,
            valueInBase: _cny('8000'),
            nativeAmount: Decimal.parse('8000'),
            nativeCurrency: 'CNY',
          ),
        ],
      ),
      CategoryAllocation(
        category: AssetCategory.cash,
        totalInBase: _cny('5000'),
        items: [
          CategoryItem(
            id: 'wallet',
            name: 'Wallet',
            subtitle: null,
            valueInBase: _cny('5000'),
            nativeAmount: Decimal.parse('5000'),
            nativeCurrency: 'CNY',
          ),
        ],
      ),
    ],
    totalAssets: _cny('25000'),
    totalLiabilities: _cny('0'),
    netWorth: _cny('25000'),
  );
}

DashboardSnapshot _singleCurrencySnapshot() {
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 24),
    baseCurrency: 'CNY',
    allocations: [
      CategoryAllocation(
        category: AssetCategory.stock,
        totalInBase: _cny('20000'),
        items: [
          CategoryItem(
            id: '600519',
            name: 'Moutai',
            subtitle: null,
            valueInBase: _cny('20000'),
            nativeAmount: Decimal.parse('20000'),
            nativeCurrency: 'CNY',
          ),
        ],
      ),
      CategoryAllocation(
        category: AssetCategory.cash,
        totalInBase: _cny('5000'),
        items: [
          CategoryItem(
            id: 'wallet',
            name: 'Wallet',
            subtitle: null,
            valueInBase: _cny('5000'),
            nativeAmount: Decimal.parse('5000'),
            nativeCurrency: 'CNY',
          ),
        ],
      ),
    ],
    totalAssets: _cny('25000'),
    totalLiabilities: _cny('0'),
    netWorth: _cny('25000'),
  );
}

DashboardSnapshot _singleCategorySnapshot() {
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 24),
    baseCurrency: 'CNY',
    allocations: [
      CategoryAllocation(
        category: AssetCategory.cash,
        totalInBase: _cny('5000'),
        items: [
          CategoryItem(
            id: 'wallet',
            name: 'Wallet',
            subtitle: null,
            valueInBase: _cny('5000'),
            nativeAmount: Decimal.parse('5000'),
            nativeCurrency: 'CNY',
          ),
        ],
      ),
    ],
    totalAssets: _cny('5000'),
    totalLiabilities: _cny('0'),
    netWorth: _cny('5000'),
  );
}

Widget _wrap({DashboardSnapshot? snapshot}) {
  return ProviderScope(
    overrides: [
      dashboardSnapshotProvider.overrideWith(
        (ref) async => snapshot ?? _snapshot(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: const Scaffold(body: WealthPerspectiveSection()),
      ),
    ),
  );
}

void main() {
  testWidgets('defaults to by-category and shows one row per category', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Allocation'), findsOneWidget);
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('By currency'), findsOneWidget);
    expect(find.byKey(const ValueKey('allocation-composition-bar')), findsOne);
    expect(find.byKey(const ValueKey('allocation-bucket-stock')), findsOne);
    expect(find.byKey(const ValueKey('allocation-bucket-cash')), findsOne);
    expect(
      find.bySemanticsLabel(RegExp(r'Stocks, 2 holdings')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'Cash, 1 holding')), findsOneWidget);
  });

  testWidgets('tapping By currency flips the section to currency buckets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('By currency'));
    await tester.pumpAndSettle();

    // Currency dimension buckets the rows by USD / CNY.
    expect(find.byKey(const ValueKey('allocation-bucket-USD')), findsOne);
    expect(find.byKey(const ValueKey('allocation-bucket-CNY')), findsOne);
    // Category labels no longer appear in the body rows (the toggle
    // chip itself doesn't read "Stocks" / "Cash").
    expect(find.text('Stocks'), findsNothing);
  });

  testWidgets('opens category details from an allocation row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('allocation-bucket-stock')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('wealth-perspective-detail')),
      findsOneWidget,
    );
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('Moutai'), findsOneWidget);
    expect(find.text('Wallet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('currency details contain only holdings in that currency', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text('By currency'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('allocation-bucket-USD')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('wealth-perspective-detail')),
      findsOneWidget,
    );
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('Moutai'), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the empty state when the snapshot has no holdings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final empty = DashboardSnapshot(
      asOf: DateTime.utc(2026, 5, 24),
      baseCurrency: 'CNY',
      allocations: const [],
      totalAssets: _cny('0'),
      totalLiabilities: _cny('0'),
      netWorth: _cny('0'),
    );

    await tester.pumpWidget(_wrap(snapshot: empty));
    await tester.pumpAndSettle();

    expect(find.textContaining('No holdings yet'), findsOneWidget);
  });

  testWidgets('keeps header and allocation rows compact on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Allocation'), findsOneWidget);
    expect(find.byKey(const ValueKey('allocation-bucket-stock')), findsOne);
    expect(find.byKey(const ValueKey('allocation-bucket-cash')), findsOne);
  });

  testWidgets('hides the perspective toggle for a single currency', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(snapshot: _singleCurrencySnapshot()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('By category'), findsNothing);
    expect(find.text('By currency'), findsNothing);
    expect(find.byKey(const ValueKey('allocation-composition-bar')), findsOne);
    expect(find.byKey(const ValueKey('allocation-bucket-stock')), findsOne);
    expect(find.byKey(const ValueKey('allocation-bucket-cash')), findsOne);
  });

  testWidgets('simplifies a single-category allocation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(snapshot: _singleCategorySnapshot()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('allocation-composition-bar')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('allocation-bucket-cash')), findsOne);
    expect(find.text('100.0%'), findsNothing);
  });
}
