import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_calculator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';
import 'package:naviwealth/features/finance/ui/plan_hub_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(FireDashboardView view) => _wrapAsync(AsyncValue.data(view));

Widget _wrapAsync(AsyncValue<FireDashboardView> view, {double textScale = 1}) =>
    ProviderScope(
      overrides: [fireDashboardViewProvider.overrideWith((ref) => view)],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const PlanHubPage(),
      ),
    );

Widget _wrapRouter(FireDashboardView view) => ProviderScope(
  overrides: [
    fireDashboardViewProvider.overrideWith((ref) => AsyncValue.data(view)),
  ],
  child: MaterialApp.router(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: GoRouter(
      initialLocation: AppRoutes.plan,
      routes: [
        GoRoute(path: AppRoutes.plan, builder: (_, _) => const PlanHubPage()),
        GoRoute(
          path: AppRoutes.planFire,
          builder: (_, _) => const Text('fire-route'),
        ),
        GoRoute(
          path: AppRoutes.planRebalance,
          builder: (_, _) => const Text('rebalance-route'),
        ),
        GoRoute(
          path: AppRoutes.planBudget,
          builder: (_, _) => const Text('budget-route'),
        ),
        GoRoute(
          path: AppRoutes.planDca,
          builder: (_, _) => const Text('dca-route'),
        ),
        GoRoute(
          path: AppRoutes.planWheel,
          builder: (_, _) => const Text('wheel-route'),
        ),
        GoRoute(
          path: AppRoutes.planIncome,
          builder: (_, _) => const Text('income-route'),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('renders stable loading skeleton while FIRE view loads', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapAsync(const AsyncValue.loading()));
    await tester.pump();

    expect(find.byType(PlanHubPage), findsOneWidget);
    expect(find.text('FIRE'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNWidgets(2));
    expect(find.text(l10n.planCoreSectionTitle), findsOneWidget);
    expect(find.text(l10n.planFireSectionTitle), findsOneWidget);
    expect(find.text(l10n.planRebalanceSectionTitle), findsOneWidget);
    expect(find.text(l10n.planBudgetSectionTitle), findsOneWidget);
  });

  testWidgets('falls back to empty FIRE hero when FIRE view errors', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _wrapAsync(AsyncValue.error(StateError('fire failed'), StackTrace.empty)),
    );
    await tester.pump();

    expect(find.byType(PlanHubPage), findsOneWidget);
    expect(find.text(l10n.commonLoadFailed), findsOneWidget);
    expect(find.text(l10n.commonSafeErrorMessage), findsOneWidget);
    expect(find.text('Bad state: fire failed'), findsNothing);
    expect(find.text(l10n.commonRetry), findsOneWidget);
  });

  testWidgets('renders empty FIRE summary and next-step tiles', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrap(_view(FireGoal.unset())));
    await tester.pump();

    expect(find.byType(PlanHubPage), findsOneWidget);
    expect(find.text(l10n.planHubTitle), findsWidgets);
    expect(find.text(l10n.planHeroEmpty), findsOneWidget);
    expect(find.text(l10n.planHeroConfigure), findsOneWidget);
    expect(find.text(l10n.planFireSectionTitle), findsOneWidget);
    expect(find.text(l10n.planRebalanceSectionTitle), findsOneWidget);
    expect(find.text(l10n.planBudgetSectionTitle), findsOneWidget);
    // Strategy tools stay collapsed until expanded.
    expect(find.text(l10n.planDcaSectionTitle), findsNothing);
  });

  testWidgets('renders configured FIRE progress in the hero card', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final goal = FireGoal(
      targetAmount: Decimal.fromInt(1000),
      monthlyExpenses: Decimal.fromInt(40),
      monthlySurplus: Decimal.fromInt(100),
      inflationRate: 0,
    );

    await tester.pumpWidget(
      _wrap(_view(goal, currentNetWorth: Decimal.fromInt(250))),
    );
    await tester.pump();

    expect(find.text(l10n.planFireSectionTitle), findsWidgets);
    expect(find.text('${l10n.planHeroProgressLabel} 25%'), findsOneWidget);
    expect(find.text(l10n.planHeroSeePlan), findsOneWidget);
  });

  testWidgets('plan hub stays bounded on a narrow scaled viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrapAsync(AsyncValue.data(_view(FireGoal.unset())), textScale: 1.5),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next steps'), findsOneWidget);
    expect(find.text('Strategies'), findsOneWidget);
  });

  testWidgets('expands more tools and navigates to feature routes', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapRouter(_view(FireGoal.unset())));
    await tester.pump();

    await tester.tap(find.text(l10n.planStrategyToolsSectionTitle));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.planDcaSectionTitle));
    await tester.pumpAndSettle();
    expect(find.text('dca-route'), findsOneWidget);
  });

  testWidgets('budget action navigates to budget route', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapRouter(_view(FireGoal.unset())));
    await tester.pump();

    await tester.tap(find.text(l10n.planBudgetSectionTitle));
    await tester.pumpAndSettle();

    expect(find.text('budget-route'), findsOneWidget);
  });

  testWidgets('rebalance action navigates to rebalance route', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapRouter(_view(FireGoal.unset())));
    await tester.pump();

    await tester.tap(find.text(l10n.planRebalanceSectionTitle));
    await tester.pumpAndSettle();

    expect(find.text('rebalance-route'), findsOneWidget);
  });

  testWidgets('FIRE hero call-to-action navigates to FIRE route', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapRouter(_view(FireGoal.unset())));
    await tester.pump();

    await tester.tap(find.text(l10n.planHeroConfigure));
    await tester.pumpAndSettle();

    expect(find.text('fire-route'), findsOneWidget);
  });
}

FireDashboardView _view(FireGoal goal, {Decimal? currentNetWorth}) =>
    const FireCalculator().buildView(
      goal: goal,
      currentNetWorth: currentNetWorth ?? Decimal.zero,
      baseCurrency: 'CNY',
      start: DateTime(2026, 6, 20),
    );
