import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/planning_hub_status.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_calculator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';
import 'package:naviwealth/features/finance/ui/plan_hub_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(FireDashboardView view) => _wrapAsync(AsyncValue.data(view));

Widget _wrapAsync(
  AsyncValue<FireDashboardView> view, {
  double textScale = 1,
  PlanningHubStatus status = const PlanningHubStatus.loading(),
}) => ProviderScope(
  overrides: [
    fireDashboardViewProvider.overrideWith((ref) => view),
    planningHubStatusProvider.overrideWith((ref) => status),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: AppMessenger.init(child: child!),
    ),
    home: const PlanHubPage(),
  ),
);

Widget _wrapRouter(
  FireDashboardView view, {
  PlanningHubStatus? status,
}) => ProviderScope(
  overrides: [
    fireDashboardViewProvider.overrideWith((ref) => AsyncValue.data(view)),
    planningHubStatusProvider.overrideWith((ref) => status ?? _settledStatus()),
  ],
  child: MaterialApp.router(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => AppMessenger.init(child: child!),
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
          path: FinanceRoutes.planRunway,
          builder: (_, _) => const Text('runway-route'),
        ),
        GoRoute(
          path: FinanceRoutes.planLifeEvents,
          builder: (_, _) => const Text('life-events-route'),
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
    expect(find.text(l10n.planAttentionTitle), findsOneWidget);
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.text(l10n.planCashSafetyTitle), findsOneWidget);
    expect(find.text(l10n.planLongTermGoalsTitle), findsOneWidget);
    expect(find.text(l10n.planInvestmentPlanTitle), findsOneWidget);
    expect(find.text(l10n.planInvestmentToolsTitle), findsOneWidget);
    expect(find.text(l10n.planBudgetSectionTitle), findsOneWidget);
    expect(find.text(l10n.planDcaPlanTitle), findsNothing);
  });

  testWidgets('keeps the workspace usable when FIRE status errors', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _wrapAsync(AsyncValue.error(StateError('fire failed'), StackTrace.empty)),
    );
    await tester.pump();

    expect(find.byType(PlanHubPage), findsOneWidget);
    expect(find.text(l10n.planStatusUnavailable), findsOneWidget);
    expect(find.text('Bad state: fire failed'), findsNothing);
    expect(find.text(l10n.planCashSafetyTitle), findsOneWidget);
    expect(find.text(l10n.planBudgetSectionTitle), findsOneWidget);
  });

  testWidgets('keeps unconfigured FIRE secondary to the planning workspace', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrap(_view(FireGoal.unset())));
    await tester.pump();

    expect(find.byType(PlanHubPage), findsOneWidget);
    expect(find.text(l10n.planHubTitle), findsWidgets);
    expect(find.text(l10n.planAttentionTitle), findsOneWidget);
    expect(find.text(l10n.planFireGoalNotConfigured), findsOneWidget);
    expect(find.text(l10n.planFireGoalTitle), findsOneWidget);
    expect(find.text(l10n.planBudgetSectionTitle), findsOneWidget);
    expect(find.text(l10n.planInvestmentPlanTitle), findsOneWidget);
    expect(find.text(l10n.planInvestmentToolsTitle), findsOneWidget);
    expect(find.text(l10n.planRebalanceSectionTitle), findsNothing);
    expect(find.text(l10n.planDcaPlanTitle), findsNothing);
    expect(find.text(l10n.lifeEventScenariosTitle), findsWidgets);
    expect(find.text('Planning tools'), findsNothing);
    expect(find.text(l10n.incomePlannerTitle), findsNothing);
  });

  testWidgets('keeps configured FIRE progress quiet in the plan list', (
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

    expect(find.text(l10n.planFireGoalTitle), findsOneWidget);
    expect(find.text('25%'), findsNothing);
  });

  testWidgets('surfaces live planning status on workflow tiles', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _wrapAsync(
        AsyncValue.data(_view(FireGoal.unset())),
        status: PlanningHubStatus(
          runway: PlanningRunwayStatus.healthy,
          pendingLifeEventReviews: 2,
          rebalance: PlanningRebalanceStatus.attention,
          rebalanceDriftPct: 0.075,
          budgetCount: 3,
          budgetSignal: BudgetSignal.comfortable,
          budgetProgress: 0.62,
          dcaPlanCount: 1,
          dcaNextDueAt: DateTime.now().add(const Duration(days: 5)),
          dcaDue: false,
          wheelCycleCount: 2,
          wheelOpenPositionCount: 1,
          isLoading: false,
          hasError: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('On track'), findsWidgets);
    expect(
      find.text('2 reviews due'),
      findsNWidgets(2),
      reason: 'Attention promotion must not hide the stable plan entry.',
    );
    expect(find.text('7.5% drift'), findsNothing);
    expect(find.text('62% used this month'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(l10n.planInvestmentToolsTitle),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text(l10n.planInvestmentToolsTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.planInvestmentToolsTitle));
    await tester.pumpAndSettle();
    expect(find.text('7.5% drift'), findsOneWidget);
    expect(find.text(l10n.incomeStrategyTitle), findsOneWidget);
    expect(find.text(l10n.planExploreActiveOptions(1)), findsOneWidget);
  });

  testWidgets('plan hub stays bounded on a narrow scaled viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrapAsync(
        AsyncValue.data(_view(FireGoal.unset())),
        textScale: 1.5,
        status: _settledStatus(),
      ),
    );
    await tester.pump();

    expect(find.text('Needs attention'), findsNothing);
    expect(find.text('Explore investment tools'), findsOneWidget);
    expect(find.text('Recurring investment plan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('promotes urgent work ahead of lower-priority reviews', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      _wrapAsync(
        AsyncValue.data(_view(FireGoal.unset())),
        status: _settledStatus(
          runway: PlanningRunwayStatus.shortfall,
          budgetSignal: BudgetSignal.overBudget,
          dcaDue: true,
          pendingLifeEventReviews: 2,
          rebalance: PlanningRebalanceStatus.attention,
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.planStatusActionRequired), findsWidgets);
    expect(find.text(l10n.moneyRunwayStatusShortfall), findsWidgets);
    expect(find.text(l10n.planAttentionCount(5)), findsOneWidget);
    expect(find.text(l10n.planAttentionShowAll(4)), findsOneWidget);
    await tester.tap(find.text(l10n.planAttentionShowAll(4)));
    await tester.pumpAndSettle();
    expect(find.text(l10n.planAttentionCollapse), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(l10n.planStatusPendingReviews(2)),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text(l10n.planStatusPendingReviews(2)),
      findsOneWidget,
      reason: 'The stable plan entry remains available after expansion.',
    );
  });

  testWidgets('does not treat active rebalance as an attention item', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _wrapAsync(
        AsyncValue.data(_view(FireGoal.unset())),
        status: _settledStatus(rebalance: PlanningRebalanceStatus.active),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.planAttentionTitle), findsNothing);
    expect(find.text(l10n.planStatusRebalanceActive), findsNothing);
  });

  testWidgets('visible strategy rows navigate to feature routes', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapRouter(_view(FireGoal.unset())));
    await tester.pump();

    await tester.ensureVisible(find.text(l10n.planInvestmentToolsTitle));
    await tester.tap(find.text(l10n.planInvestmentToolsTitle));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.incomeStrategyTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.incomeStrategyTitle).last);
    await tester.pumpAndSettle();
    expect(find.text('income-route'), findsOneWidget);
  });

  testWidgets('keeps budget visible as a permanent planning capability', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapRouter(_view(FireGoal.unset())));
    await tester.pump();

    expect(find.text(l10n.planBudgetSectionTitle), findsOneWidget);
  });

  testWidgets('rebalance action navigates to rebalance route', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _wrapRouter(
        _view(FireGoal.unset()),
        status: _settledStatus(rebalance: PlanningRebalanceStatus.attention),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text(l10n.planInvestmentToolsTitle),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(l10n.planInvestmentToolsTitle));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.planRebalanceSectionTitle).last);
    await tester.pumpAndSettle();

    expect(find.text('rebalance-route'), findsOneWidget);
  });

  testWidgets('FIRE hero call-to-action navigates to FIRE route', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(_wrapRouter(_view(FireGoal.unset())));
    await tester.pump();

    await tester.tap(find.text(l10n.planFireGoalTitle));
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

PlanningHubStatus _settledStatus({
  PlanningRunwayStatus runway = PlanningRunwayStatus.healthy,
  int pendingLifeEventReviews = 0,
  PlanningRebalanceStatus rebalance = PlanningRebalanceStatus.balanced,
  BudgetSignal budgetSignal = BudgetSignal.comfortable,
  bool dcaDue = false,
}) => PlanningHubStatus(
  runway: runway,
  pendingLifeEventReviews: pendingLifeEventReviews,
  rebalance: rebalance,
  rebalanceDriftPct: rebalance == PlanningRebalanceStatus.attention ? 0.08 : 0,
  budgetCount: 3,
  budgetSignal: budgetSignal,
  budgetProgress: 0.62,
  dcaPlanCount: 1,
  dcaNextDueAt: DateTime.now().add(Duration(days: dcaDue ? -1 : 5)),
  dcaDue: dcaDue,
  wheelCycleCount: 0,
  wheelOpenPositionCount: 0,
  isLoading: false,
  hasError: false,
);
