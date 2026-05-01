import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/features/home/ui/allocation_card.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: day(2026, 4, 1),
      updatedByDevice: 't',
      hlc: Hlc.zero('t'),
    );

Asset _cash(String id, String price, [String currency = 'CNY']) => Asset(
      id: id,
      type: AssetType.cash,
      symbol: id,
      currency: currency,
      lastPrice: d(price),
      sync: _meta(),
    );

Liability _liability({
  required String id,
  required String name,
  required String principal,
}) {
  return Liability(
    id: id,
    type: LiabilityType.mortgage,
    name: name,
    principal: d(principal),
    interestRate: d('0.045'),
    currency: 'CNY',
    sync: _meta(),
  );
}

ProviderScope _wrap({
  required Widget child,
  required SharedPreferences prefs,
  List<Asset> manualAssets = const [],
  List<PhysicalAsset> physicalAssets = const [],
  List<Liability> liabilities = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      manualAssetsStreamProvider.overrideWith(
        (ref) => Stream.value(manualAssets),
      ),
      physicalAssetsListProvider.overrideWith(
        (ref) => Stream.value(physicalAssets),
      ),
      liabilitiesStreamProvider.overrideWith(
        (ref) => Stream.value(liabilities),
      ),
      fxRatesStreamProvider.overrideWith(
        (ref) => Stream<List<FxRate>>.value(const []),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'home page renders the empty state when no assets / liabilities exist',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester
        .pumpWidget(_wrap(prefs: prefs, child: const HomePage()));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    // Empty pie placeholder is shown.
    expect(find.byType(EmptyChartPlaceholder), findsWidgets);
  });

  testWidgets('home page renders allocation pie with category slices', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(
      prefs: prefs,
      manualAssets: [
        _cash('cash', '10000'),
      ],
      liabilities: [
        _liability(id: 'L', name: '房贷', principal: '5000'),
      ],
      child: const HomePage(),
    ));
    await tester.pumpAndSettle();
    // The pie chart is mounted.
    expect(find.byType(PieChart), findsOneWidget);
    // The trend chart is mounted (single non-empty series).
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('time range chips persist selection in the provider', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(_wrap(
      prefs: prefs,
      manualAssets: [_cash('cash', '10000')],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context, listen: false);
        return const HomePage();
      }),
    ));
    await tester.pumpAndSettle();

    // Default selection is 1Y.
    expect(
      container.read(dashboardSelectedRangeProvider),
      DashboardRangePreset.y1,
    );

    // Tap the "1M" chip — find by localized label.
    await tester.tap(find.text('1M'));
    await tester.pumpAndSettle();
    expect(
      container.read(dashboardSelectedRangeProvider),
      DashboardRangePreset.m1,
    );
  });

  testWidgets('drill-down sheet opens with the category items', (
    tester,
  ) async {
    final snapshot = DashboardSnapshot(
      asOf: day(2026, 4, 29),
      baseCurrency: 'CNY',
      allocations: [
        CategoryAllocation(
          category: AssetCategory.cash,
          totalInBase: Money(d('10000'), 'CNY'),
          items: [
            CategoryItem(
              id: 'cash-1',
              name: '工资卡',
              subtitle: '招商银行',
              valueInBase: Money(d('10000'), 'CNY'),
              nativeAmount: d('10000'),
              nativeCurrency: 'CNY',
            ),
          ],
        ),
      ],
      totalAssets: Money(d('10000'), 'CNY'),
      totalLiabilities: Money(Decimal.zero, 'CNY'),
      netWorth: Money(d('10000'), 'CNY'),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AllocationCard(snapshot: snapshot)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the legend row → opens the drill-down sheet listing the asset.
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryDrillDownSheet), findsOneWidget);
    expect(find.text('工资卡'), findsOneWidget);
    expect(find.text('招商银行'), findsOneWidget);
  });
}

