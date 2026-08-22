import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/finance/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/application/planning_hub_status.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/features/finance/ui/plan_hub_page.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_hub_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets(
    'Plan hub keeps all planning capabilities visible while loading',
    (tester) async {
      await _setDesktopSurface(tester);
      await tester.pumpWidget(
        _wrap(
          overrides: [
            fireDashboardViewProvider.overrideWith(
              (_) => const AsyncValue.loading(),
            ),
            planningHubStatusProvider.overrideWith(
              (_) => const PlanningHubStatus.loading(),
            ),
          ],
          child: const PlanHubPage(),
        ),
      );
      await tester.pump();

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Financial outlook'), findsOneWidget);
      expect(find.text('Money runway'), findsOneWidget);
      expect(find.text('Financial independence'), findsOneWidget);
      expect(find.text('Active investment plans'), findsOneWidget);
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('Income Planner'), findsNothing);
      expect(find.text('Scenario analytics'), findsNothing);
      expect(find.text('Scenarios'), findsNothing);
      expect(find.text('Goals'), findsNothing);
    },
  );

  testWidgets('Plan hub pairs outlook with active plans on wide canvas', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _wrap(
        overrides: [
          fireDashboardViewProvider.overrideWith(
            (_) => const AsyncValue.loading(),
          ),
          planningHubStatusProvider.overrideWith(
            (_) => PlanningHubStatus(
              runway: PlanningRunwayStatus.healthy,
              pendingLifeEventReviews: 0,
              rebalance: PlanningRebalanceStatus.active,
              rebalanceDriftPct: 0.08,
              budgetCount: 1,
              budgetSignal: null,
              budgetProgress: 0.4,
              dcaPlanCount: 1,
              dcaNextDueAt: DateTime.utc(2026, 8, 8),
              dcaDue: false,
              wheelCycleCount: 0,
              wheelOpenPositionCount: 0,
              isLoading: false,
              hasError: false,
            ),
          ),
        ],
        child: const PlanHubPage(),
      ),
    );
    await tester.pump();

    final outlook = tester.getRect(
      find.byKey(const ValueKey('plan-outlook-section')),
    );
    final investments = tester.getRect(
      find.byKey(const ValueKey('plan-investments-section')),
    );
    expect(investments.top, outlook.top);
    expect(investments.left, greaterThan(outlook.right));
    expect(investments.width, greaterThan(outlook.width * 1.9));
  });

  testWidgets('Wealth hub hides placeholder-only entries', (tester) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _wrap(
        overrides: [
          accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
          accountBalancesByIdProvider.overrideWith(
            (_) => Stream.value(const {}),
          ),
          dashboardSnapshotProvider.overrideWith(
            (_) async => DashboardSnapshot.empty(
              asOf: DateTime.utc(2026, 6, 1),
              baseCurrency: 'USD',
            ),
          ),
        ],
        child: const WealthHubPage(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Holdings'), findsOneWidget);
    expect(find.text('Liabilities'), findsWidgets);
    expect(find.text('Wealth items'), findsOneWidget);
    expect(find.text('Dividend Center'), findsNothing);
    expect(find.text('Income projection'), findsNothing);
  });

  testWidgets('Wealth add menu exposes asset types without a second sheet', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      _wrap(
        overrides: [
          accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
          accountBalancesByIdProvider.overrideWith(
            (_) => Stream.value(const {}),
          ),
          dashboardSnapshotProvider.overrideWith(
            (_) async => DashboardSnapshot.empty(
              asOf: DateTime.utc(2026, 6, 1),
              baseCurrency: 'USD',
            ),
          ),
        ],
        child: const WealthHubPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.accountFormCreateTitle), findsOneWidget);
    expect(find.text(l10n.assetsAddCashTitle), findsOneWidget);
    expect(find.text(l10n.assetsAddDepositTitle), findsOneWidget);
    expect(find.text(l10n.physicalAssetAddRealEstate), findsOneWidget);
    expect(find.text(l10n.superFabLiability), findsOneWidget);
  });

  testWidgets(
    'Wealth hub pairs object navigation with the trend on wide canvas',
    (tester) async {
      await _setDesktopSurface(tester);
      await tester.pumpWidget(
        _wrap(
          overrides: [
            accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
            accountBalancesByIdProvider.overrideWith(
              (_) => Stream.value(const {}),
            ),
            dashboardSnapshotProvider.overrideWith(
              (_) async => DashboardSnapshot(
                asOf: DateTime.utc(2026, 6, 1),
                baseCurrency: 'USD',
                allocations: const [],
                totalAssets: Money(Decimal.fromInt(100000), 'USD'),
                totalLiabilities: Money(Decimal.fromInt(10000), 'USD'),
                netWorth: Money(Decimal.fromInt(90000), 'USD'),
              ),
            ),
            dashboardBaseCurrencyProvider.overrideWith((_) => 'USD'),
            dashboardTrendProvider.overrideWith((_, _) async => _trend()),
          ],
          child: const WealthHubPage(),
        ),
      );
      await tester.pumpAndSettle();

      final destinations = tester.getRect(
        find.byKey(const ValueKey('wealth-destinations')),
      );
      final trend = tester.getRect(
        find.byKey(const ValueKey('wealth-trend-section')),
      );
      final perspective = tester.getRect(
        find.byKey(const ValueKey('wealth-perspective-section')),
      );

      expect(destinations.top, trend.top);
      expect(trend.left, greaterThan(destinations.right));
      expect(trend.width, greaterThan(destinations.width * 1.9));
      expect(perspective.top, greaterThan(trend.bottom));
    },
  );
}

DashboardTrend _trend() {
  final range = DashboardTimeRange.resolve(
    preset: DashboardRangePreset.y1,
    now: DateTime.utc(2026, 6, 1),
  );
  TrendPoint point(DateTime asOf, int value) => TrendPoint(
    asOf: asOf,
    assets: Money(Decimal.fromInt(value), 'USD'),
    liabilities: Money.zero('USD'),
    netWorth: Money(Decimal.fromInt(value), 'USD'),
  );
  return DashboardTrend(
    range: range,
    baseCurrency: 'USD',
    points: [
      point(DateTime.utc(2025, 6, 1), 80000),
      point(DateTime.utc(2026, 6, 1), 90000),
    ],
  );
}

Widget _wrap({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FTheme(data: FTheme.neutral.light.desktop, child: child),
    ),
  );
}

Future<void> _setDesktopSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
