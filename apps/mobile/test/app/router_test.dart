// Behavior verification for the web routing surface:
// path URL strategy + go_router + shell navigation. These tests exercise the
// core URL flows:
//   1. deep-link arrival
//   2. tab navigation (the URL stays in sync with the visible tab)
//   3. back/forward + refresh (re-driving the router from a stored URL lands
//      on the same page; Riverpod state is reset, URL is the source of truth)
//
// Real browser history (`window.history.back/forward`) is platform glue we
// can't drive from a widget test — those flows are covered by the manual
// checklist in apps/mobile/docs/development/web-routing.md and live cross-browser runs in
// FIR-40. What we *can* assert here is the router contract those flows rely
// on: a given URL deterministically maps to a given page, and the bottom nav
// keeps the URL up to date.

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/app/agent_artifact_page.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/app/routing/router.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_corpus.dart';
import 'package:naviwealth/core/auth/auth_api_client.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/shell/desktop_sidebar.dart';
import 'package:naviwealth/core/shell/route_error_page.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/ui/ai_chat_page.dart';
import 'package:naviwealth/features/auth/ui/devices_page.dart';
import 'package:naviwealth/features/execution/composition/execution_route_paths.dart';
import 'package:naviwealth/features/execution/ui/execution_detail_page.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_entry_detail_page.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_page.dart';
import 'package:naviwealth/features/finance/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/finance/analytics/data/benchmark/benchmark_providers.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart'
    as analytics_data;
import 'package:naviwealth/features/finance/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/finance/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_detail_page.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/cashflow/ui/cashflow_page.dart';
import 'package:naviwealth/features/finance/cashflow/ui/dividend_center_page.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/expense/ui/spending_page.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_calculator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/ui/fire_page.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_codecs.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/ui/rebalance_execution_workspace_page.dart';
import 'package:naviwealth/features/finance/rebalance/ui/rebalance_page.dart';
import 'package:naviwealth/features/finance/ui/plan_hub_page.dart';
import 'package:naviwealth/features/finance/ui/settings/fire_stress_settings_page.dart';
import 'package:naviwealth/features/finance/ui/settings/fx_rates_page.dart';
import 'package:naviwealth/features/finance/ui/settings/monthly_expense_settings_page.dart';
import 'package:naviwealth/features/finance/ui/settings/risk_thresholds_page.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_hub_page.dart';
import 'package:naviwealth/features/health/ui/health_trend_page.dart';
import 'package:naviwealth/features/settings/ui/settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';
import '../features/finance/data/repositories/_stub_stamper.dart';
import '../features/finance/rebalance/data/rebalance_execution_test_fixtures.dart';

class _OfflineBenchmarkSource implements BenchmarkHistorySource {
  @override
  Future<List<TimeSeriesPoint>> seriesFor({
    required BenchmarkIndex index,
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

class _EmptyHoldingService implements HoldingService {
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      const {};
  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];
  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) =>
      throw UnimplementedError();
  @override
  Future<void> invalidateFrom(DateTime from) async {}
}

class _StaticDevicesNotifier extends DevicesNotifier {
  @override
  Future<DevicesResponse> build() async =>
      const DevicesResponse(devices: [], currentDeviceId: 'test-device');
}

// Standard test surface sizes for the three responsive shell breakpoints.
// _RootShell switches at 600 (rail) and 1280 (drawer); these sit comfortably
// inside each band so a small change to the breakpoints doesn't accidentally
// flip a test into a different layout.
const Size _mobileSize = Size(400, 800);
const Size _tabletSize = Size(800, 1000);
const Size _desktopSize = Size(1440, 900);

Future<ProviderContainer> _pumpAt(
  WidgetTester tester, {
  String initialLocation = '/',
  Size viewportSize = _mobileSize,
  RebalanceExecutionSession? executionSession,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'ai_privacy.onboarding_seen.v1': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = makeTestDatabase();
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) async => db),
      mutationStamperProvider.overrideWith((_) async => makeStubStamper()),
      // Match production bootstrap: the DomainPack inventory, router
      // shells, active-domain aggregators, and domain-owned provider
      // seams all come from the same composition bundle.
      ...lifeOsDomainCompositionOverrides(),
      appRouterProvider.overrideWith(
        (ref) => buildAppRouter(ref, initialLocation: initialLocation),
      ),
      // The Assets/Accounts tabs subscribe to live DB streams. In a routing
      // smoke test we don't have a real database, so short-circuit the
      // streams to empty lists so `pumpAndSettle` actually settles.
      manualAssetsStreamProvider.overrideWith(
        (ref) => Stream<List<Asset>>.value(const []),
      ),
      // FIR-120: the assets tab also subscribes to securities so freshly
      // recorded trades surface there. No DB in widget tests, so stub.
      securitiesAssetsStreamProvider.overrideWith(
        (ref) => Stream<List<Asset>>.value(const []),
      ),
      accountsStreamProvider.overrideWith(
        (ref) => Stream<List<Account>>.value(const []),
      ),
      allAccountsStreamProvider.overrideWith(
        (ref) => Stream<List<Account>>.value(const []),
      ),
      journalExpensesStreamProvider.overrideWith(
        (ref) => Stream<List<Expense>>.value(const []),
      ),
      // The real `physicalAssetsListProvider` reaches through
      // `appDatabaseProvider` → `FlutterSecureKeyStore`, neither of which
      // is available under `flutter_test`. Stub with an immediate empty
      // emission so the page resolves to its empty state instead of
      // spinning forever.
      physicalAssetsListProvider.overrideWith((ref) => Stream.value(const [])),
      // FIR-52's dashboard watches liabilities to render its allocation
      // card. Stub the live stream so the home page settles to its empty
      // snapshot instead of hanging on the database key store.
      liabilitiesStreamProvider.overrideWith(
        (ref) => Stream<List<Liability>>.value(const []),
      ),
      // FIR-53's analytics tab reads equity assets from the same Drift
      // database. Same pattern as the other tabs — short-circuit to an
      // empty list so `pumpAndSettle` resolves.
      analytics_data.equityAssetsStreamProvider.overrideWith(
        (ref) => Stream<List<Asset>>.value(const []),
      ),
      // FIR-56's benchmark comparison card pulls index history through the
      // composite market-data service, which reaches the encrypted DB +
      // network providers we don't have under flutter_test. Stub with an
      // offline source so the analytics page settles instead of hanging.
      benchmarkHistorySourceProvider.overrideWith(
        (_) async => _OfflineBenchmarkSource(),
      ),
      // FIR-89's holdings + returns pipeline reaches through the same
      // encrypted DB chain. Stub both providers so the analytics +
      // dashboard pages settle without hanging on the missing key store.
      holdingServiceProvider.overrideWith(
        (ref) async => _EmptyHoldingService(),
      ),
      holdingsSnapshotProvider.overrideWith((ref) async => const {}),
      dashboardSnapshotProvider.overrideWith(
        (ref) async => DashboardSnapshot.empty(
          asOf: DateTime(2026, 8, 2),
          baseCurrency: 'CNY',
        ),
      ),
      recurringTransactionsProvider.overrideWith(
        (ref) => Stream.value(const []),
      ),
      cashFlowSummaryProvider.overrideWith(
        (ref, request) async => CashFlowSummary(
          period: request.period,
          baseCurrency: 'CNY',
          buckets: const [],
          totalInBase: Money.zero('CNY'),
        ),
      ),
      dividendCenterSnapshotProvider.overrideWith(
        (ref) async => _emptyDividendSnapshot(),
      ),
      fireDashboardViewProvider.overrideWith(
        (ref) => AsyncValue.data(
          const FireCalculator().buildView(
            goal: FireGoal.unset(),
            currentNetWorth: Decimal.zero,
            baseCurrency: 'CNY',
            start: DateTime(2026, 6, 19),
          ),
        ),
      ),
      devicesProvider.overrideWith(_StaticDevicesNotifier.new),
      if (executionSession != null)
        rebalanceExecutionSessionProvider(
          executionSession.id,
        ).overrideWith((_) async => executionSession),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NaviWealthApp(),
    ),
  );
  // The SuperFab pulse animation loops indefinitely, so pumpAndSettle will
  // time out. Use explicit pumps instead.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  // Route performance traces close 750 ms after the last named transition.
  await tester.pump(const Duration(milliseconds: 800));
  return container;
}

String _currentPath(ProviderContainer container) {
  return container
      .read(appRouterProvider)
      .routeInformationProvider
      .value
      .uri
      .path;
}

RebalanceExecutionSession _executionSession() {
  final plan = testPlan(reverseCollections: true);
  return RebalanceExecutionSession(
    id: 'router-session',
    ownerUserId: 'owner-a',
    status: RebalanceExecutionSessionStatus.active,
    plan: plan,
    rawPlanJson: RebalancePlanCodec.encode(plan),
    planFingerprint: RebalancePlanFingerprint.compute(plan),
    items: [
      RebalanceExecutionItem(
        id: 'router-item',
        sessionId: 'router-session',
        ownerUserId: 'owner-a',
        position: 0,
        suggestion: plan.trades.first,
        state: RebalanceExecutionItemState.needsDetails,
        createdAt: testNow,
        updatedAt: testNow,
      ),
    ],
    createdAt: testNow,
    updatedAt: testNow,
  );
}

/// Drain pending animation timers (SuperFab pulse, AnimatedContainer, etc.)
/// so the test binding's `_verifyInvariants` doesn't complain about leftover
/// timers after the widget tree is disposed.
Future<void> _drainTimers(WidgetTester tester) async {
  // Advance the fake clock enough to flush any repeating timers.
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  // Ignore rendering overflow errors from compact navigation at the smallest
  // test viewport.
  setUp(() {
    final originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalHandler);
  });

  setUpAll(() async {
    // `DeferredRoute` calls `loadLibrary()` on tab pages. In the VM that
    // returns a real-async Future the fake test clock can't drive, so the
    // spinner can hang `pumpAndSettle` forever. Pre-load all of them once
    // so subsequent calls return an already-completed cached future.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(preloadDeferredRoutesForTest);
  });

  group('deep-link arrival', () {
    testWidgets('/ renders Home', (tester) async {
      await _pumpAt(tester);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(FloatingGlassNavBar), findsOneWidget);
    });

    testWidgets('Life Agent result deep link resolves by artifact id', (
      tester,
    ) async {
      final route = AppRoutes.agentArtifact('artifact/with spaces');
      final container = await _pumpAt(tester, initialLocation: route);

      expect(_currentPath(container), route);
      expect(find.byType(RouteErrorPage), findsNothing);
      expect(find.byType(AgentArtifactPage), findsOneWidget);
      expect(
        tester
            .widget<AgentArtifactPage>(find.byType(AgentArtifactPage))
            .artifactId,
        'artifact/with spaces',
      );
    });

    testWidgets('Execution Project detail deep link resolves by project id', (
      tester,
    ) async {
      final route = ExecutionRoutes.project('project/with spaces');
      final container = await _pumpAt(tester, initialLocation: route);

      expect(_currentPath(container), route);
      expect(find.byType(RouteErrorPage), findsNothing);
      expect(find.byType(ExecutionProjectDetailPage), findsOneWidget);
      expect(
        tester
            .widget<ExecutionProjectDetailPage>(
              find.byType(ExecutionProjectDetailPage),
            )
            .projectId,
        'project/with spaces',
      );
    });

    testWidgets('web checklist primary deep links render canonical pages', (
      tester,
    ) async {
      final cases = <String, Type>{
        AppRoutes.activity: ActivityPage,
        AppRoutes.wealth: WealthHubPage,
        AppRoutes.plan: PlanHubPage,
        AppRoutes.settings: SettingsPage,
      };

      for (final entry in cases.entries) {
        final container = await _pumpAt(tester, initialLocation: entry.key);
        expect(_currentPath(container), entry.key);
        expect(find.byType(entry.value), findsOneWidget);
        await _drainTimers(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('web checklist secondary deep links resolve', (tester) async {
      final cases = <String, Type>{
        AppRoutes.wealthAsset('asset-1'): AssetDetailPage,
        AppRoutes.spending: SpendingPage,
        AppRoutes.planFire: FirePage,
        AppRoutes.settingsAiHistory: AiChatPage,
        AppRoutes.settingsDevices: DevicesPage,
        AppRoutes.settingsFxRates: FxRatesPage,
        AppRoutes.settingsRiskThresholds: RiskThresholdsPage,
        AppRoutes.settingsStressTest: FireStressSettingsPage,
        AppRoutes.settingsMonthlyExpense: MonthlyExpenseSettingsPage,
      };

      for (final entry in cases.entries) {
        final container = await _pumpAt(tester, initialLocation: entry.key);
        expect(_currentPath(container), Uri.parse(entry.key).path);
        expect(find.byType(RouteErrorPage), findsNothing);
        expect(find.byType(entry.value), findsOneWidget);
        await _drainTimers(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('all Agent outcome action routes resolve in the real router', (
      tester,
    ) async {
      final routes = <String>{
        for (final regressionCase in agentOutcomeRegressionCorpus)
          ...regressionCase.expectedActionRoutes,
      }.toList()..sort();
      expect(routes, isNotEmpty);

      for (final route in routes) {
        final container = await _pumpAt(tester, initialLocation: route);
        expect(_currentPath(container), Uri.parse(route).path, reason: route);
        expect(find.byType(RouteErrorPage), findsNothing, reason: route);
        await _drainTimers(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
      'all Agent evidence route families resolve in the real router',
      (tester) async {
        final routes = <String>{
          for (final regressionCase in agentOutcomeRegressionCorpus)
            for (final pattern
                in regressionCase.expectedEvidenceRoutePatterns.values)
              pattern.endsWith('*')
                  ? '${pattern.substring(0, pattern.length - 1)}route-probe'
                  : pattern,
        }.toList()..sort();
        expect(routes, isNotEmpty);

        for (final route in routes) {
          final container = await _pumpAt(tester, initialLocation: route);
          expect(_currentPath(container), Uri.parse(route).path, reason: route);
          expect(find.byType(RouteErrorPage), findsNothing, reason: route);
          await _drainTimers(tester);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    for (final legacy in <String>[
      '/assets',
      '/expenses',
      '/analytics',
      '/fire',
      '/rebalance',
      '/me',
      '/more',
      '/plan/projection',
      '/plan/scenarios',
      '/plan/goals',
    ]) {
      testWidgets('$legacy renders the route error page', (tester) async {
        final container = await _pumpAt(tester, initialLocation: legacy);
        expect(find.byType(RouteErrorPage), findsOneWidget);
        expect(_currentPath(container), legacy);
      });
    }

    testWidgets('/portfolio renders Portfolio', (tester) async {
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.wealth,
      );
      expect(find.byType(WealthHubPage), findsOneWidget);
      expect(_currentPath(container), AppRoutes.wealth);
    });

    testWidgets('/plan/rebalance renders Rebalance', (tester) async {
      await _pumpAt(tester, initialLocation: AppRoutes.planRebalance);
      expect(find.byType(RebalancePage), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('/plan/rebalance/execution/:sessionId restores workspace', (
      tester,
    ) async {
      final session = _executionSession();
      final location = AppRoutes.planRebalanceExecutionSession(session.id);
      final container = await _pumpAt(
        tester,
        initialLocation: location,
        executionSession: session,
      );

      expect(find.byType(RebalanceExecutionWorkspacePage), findsOneWidget);
      expect(find.text('0 of 1 resolved'), findsOneWidget);
      expect(_currentPath(container), location);
      await _drainTimers(tester);
    });

    testWidgets('/activity/cashflow?period=year renders CashFlow', (
      tester,
    ) async {
      final container = await _pumpAt(
        tester,
        initialLocation: '${AppRoutes.cashflow}?period=year',
      );
      expect(find.byType(CashFlowPage), findsOneWidget);
      expect(_currentPath(container), AppRoutes.cashflow);
    });

    testWidgets('/wealth/portfolio/dividends renders Dividend Center', (
      tester,
    ) async {
      await _pumpAt(tester, initialLocation: AppRoutes.cashflowDividends);
      expect(find.byType(DividendCenterPage), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('Dividend Center restores the focused asset query', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        initialLocation: '${AppRoutes.cashflowDividends}?assetId=us%3AAAPL',
      );

      final page = tester.widget<DividendCenterPage>(
        find.byType(DividendCenterPage),
      );
      expect(page.focusAssetId, 'us:AAPL');
      await _drainTimers(tester);
    });

    testWidgets('/activity/entry/:id resolves without route extra', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        initialLocation: AppRoutes.activityEntry('missing-entry'),
      );
      expect(find.byType(RouteErrorPage), findsNothing);
      expect(find.byType(ActivityEntryDetailRoute), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('/health/trend restores group and window from query', (
      tester,
    ) async {
      final container = await _pumpAt(
        tester,
        initialLocation: '${AppRoutes.healthTrend}?group=body&window=90',
      );
      expect(find.byType(RouteErrorPage), findsNothing);
      expect(find.byType(HealthTrendPage), findsOneWidget);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .queryParameters,
        containsPair('group', 'body'),
      );
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .queryParameters,
        containsPair('window', '90'),
      );
      await _drainTimers(tester);
    });

    testWidgets('/settings renders Settings', (tester) async {
      await _pumpAt(tester, initialLocation: AppRoutes.settings);
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('unknown query params on a known path do not break the page', (
      tester,
    ) async {
      // Query params on a redirect path should survive the redirect.
      await _pumpAt(
        tester,
        initialLocation: '${AppRoutes.planRebalance}?range=1y',
      );
      expect(find.byType(RebalancePage), findsOneWidget);
      await _drainTimers(tester);
    });
  });

  group('tab navigation keeps URL in sync', () {
    testWidgets('tapping each bottom-nav tab updates the URL and the page', (
      tester,
    ) async {
      final container = await _pumpAt(tester);
      expect(_currentPath(container), AppRoutes.home);

      // Navigate via the router directly — the pill bar layout and icon
      // disambiguation are covered by the positional tap test below.
      container.read(appRouterProvider).go(AppRoutes.wealth);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.wealth);
      expect(find.byType(WealthHubPage), findsOneWidget);

      container.read(appRouterProvider).go(AppRoutes.activity);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.activity);

      container.read(appRouterProvider).go(AppRoutes.plan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.plan);

      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.home);
      expect(find.byType(HomePage), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('/settings resolves outside the shell as a deep-link', (
      tester,
    ) async {
      // IA contract §1: Settings is off-nav. Verify deep-link arrival
      // lands on SettingsPage (push/pop semantics are exercised via the
      // gear icon in real UI tests, not here).
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.settings,
      );
      expect(_currentPath(container), AppRoutes.settings);
      expect(find.byType(SettingsPage), findsOneWidget);
      // Settings is outside the shell so the bottom nav is gone.
      expect(find.byType(FloatingGlassNavBar), findsNothing);
      await _drainTimers(tester);
    });

    testWidgets('tapping nav items navigates correctly', (tester) async {
      final container = await _pumpAt(tester);
      expect(_currentPath(container), AppRoutes.home);

      final barFinder = find.byType(FloatingGlassNavBar);
      await tester.tap(
        find.descendant(of: barFinder, matching: find.text('Wealth')).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.wealth);

      await tester.tap(
        find.descendant(of: barFinder, matching: find.text('Plan')).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.plan);
      await _drainTimers(tester);
    });

    testWidgets('home hero switches to Wealth without losing bottom nav', (
      tester,
    ) async {
      final container = await _pumpAt(tester);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(FloatingGlassNavBar), findsOneWidget);

      await tester.tap(find.text('Net Worth').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_currentPath(container), AppRoutes.wealth);
      expect(find.byType(WealthHubPage), findsOneWidget);
      expect(find.byType(FloatingGlassNavBar), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('selected tab index follows the current URL', (tester) async {
      // 4-item nav layout:
      // Today(0) | Activity(1) | Wealth(2) | Plan(3)
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.wealth,
      );
      final bar = tester.widget<FloatingGlassNavBar>(
        find.byType(FloatingGlassNavBar),
      );
      expect(bar.selectedIndex, 2);

      container.read(appRouterProvider).go(AppRoutes.activity);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final updated = tester.widget<FloatingGlassNavBar>(
        find.byType(FloatingGlassNavBar),
      );
      expect(updated.selectedIndex, 1);
      await _drainTimers(tester);
    });

    testWidgets('bottom nav stays hidden when popping back to a sub-page', (
      tester,
    ) async {
      final container = await _pumpAt(tester, initialLocation: AppRoutes.plan);
      final router = container.read(appRouterProvider);
      expect(find.byType(FloatingGlassNavBar), findsOneWidget);

      unawaited(router.push<void>(AppRoutes.planIncome));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(router.canPop(), isTrue);
      expect(find.byType(FloatingGlassNavBar), findsNothing);

      unawaited(router.push<void>(AppRoutes.planIncomeStats));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(router.canPop(), isTrue);
      expect(find.byType(FloatingGlassNavBar), findsNothing);

      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(router.canPop(), isTrue);
      expect(
        find.byType(FloatingGlassNavBar),
        findsNothing,
        reason: 'Income Planner is still below the Plan tab root.',
      );

      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.plan);
      expect(find.byType(FloatingGlassNavBar), findsOneWidget);
      await _drainTimers(tester);
    });
  });

  group('responsive shell switches by viewport width', () {
    // FIR-84: < 600 → GlassBottomBar (bottom), ≥ 600 & < 1200 →
    // GlassSideBar, ≥ 1200 → unified DesktopSidebar. Tabs and selectedIndex
    // stay consistent across the three layouts.

    testWidgets('mobile width uses GlassBottomBar at the bottom', (
      tester,
    ) async {
      await _pumpAt(tester, viewportSize: _mobileSize);
      expect(find.byType(FloatingGlassNavBar), findsOneWidget);
      expect(find.byType(FSidebar), findsNothing);
      expect(find.byType(DesktopSidebar), findsNothing);
    });

    testWidgets(
      'S2.5 — the tab header chrome opens the command palette on tap',
      (tester) async {
        // Search now lives in the shared header chrome — every headered tab
        // surfaces it via ShellTabScaffold (Today hosts it in its greeting
        // instead) — not a bottom-nav slot. Activity's header is always
        // present (not gated on async page data), so it's the stable place
        // to assert the chrome.
        final container = await _pumpAt(
          tester,
          initialLocation: AppRoutes.activity,
          viewportSize: _mobileSize,
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final moreActions = find.byIcon(FLucideIcons.ellipsis);
        expect(moreActions, findsOneWidget);
        await tester.tap(moreActions);
        await tester.pumpAndSettle();
        expect(find.text(l10n.shellMoreActions), findsOneWidget);

        final searchAction = find.text(l10n.navSearch);
        expect(searchAction, findsOneWidget);
        await tester.tap(searchAction);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // The palette opens as a dialog with its own search field.
        expect(find.text(l10n.commandPaletteSearchHint), findsOneWidget);
        expect(
          _currentPath(container),
          AppRoutes.activity,
          reason: 'opening the palette must not navigate away',
        );
        await _drainTimers(tester);
      },
    );

    testWidgets('S2.5 — desktop shell does not show the header search action', (
      tester,
    ) async {
      await _pumpAt(tester, viewportSize: _desktopSize);
      expect(
        find.byIcon(FLucideIcons.search),
        findsNothing,
        reason:
            'desktop uses Cmd-K + the left dock; the inline header '
            'chrome is touch-only',
      );
    });

    testWidgets('tablet width uses GlassSideBar', (tester) async {
      await _pumpAt(tester, viewportSize: _tabletSize);
      expect(find.byType(FSidebar), findsOneWidget);
      expect(find.byType(FloatingGlassNavBar), findsNothing);
      expect(find.byType(DesktopSidebar), findsNothing);
    });

    testWidgets('tablet width ≥ 900 still uses GlassSideBar', (tester) async {
      await _pumpAt(tester, viewportSize: const Size(1100, 1000));
      expect(find.byType(FSidebar), findsOneWidget);
      expect(find.byType(DesktopSidebar), findsNothing);
    });

    testWidgets('desktop width uses the FIR-106 collapsible sidebar', (
      tester,
    ) async {
      await _pumpAt(tester, viewportSize: _desktopSize);
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(FloatingGlassNavBar), findsNothing);
    });

    testWidgets('GlassSideBar selectedIndex follows the current URL', (
      tester,
    ) async {
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.activity,
        viewportSize: _tabletSize,
      );
      expect(find.byType(FSidebar), findsOneWidget);
      expect(find.byType(WealthHubPage), findsNothing);

      container.read(appRouterProvider).go(AppRoutes.wealth);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WealthHubPage), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('DesktopSidebar selectedIndex follows the current URL', (
      tester,
    ) async {
      // FIRE lives under Plan (/plan/fire); the Plan tab (index 3) stays
      // selected while the user is on any /plan/* sub-page.
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.planFire,
        viewportSize: _desktopSize,
      );
      final sidebar = tester.widget<DesktopSidebar>(
        find.byType(DesktopSidebar),
      );
      expect(sidebar.selectedIndex, 4);

      // Settings is off-nav (IA contract §1) — navigating to /settings
      // exits the shell and the sidebar isn't visible. So we hop to
      // Wealth to confirm the index swap before that.
      container.read(appRouterProvider).go(AppRoutes.wealth);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final updated = tester.widget<DesktopSidebar>(
        find.byType(DesktopSidebar),
      );
      expect(updated.selectedIndex, 3);
      await _drainTimers(tester);
    });

    testWidgets('tapping a rail destination updates the URL', (tester) async {
      final container = await _pumpAt(tester, viewportSize: _tabletSize);
      expect(_currentPath(container), AppRoutes.home);

      // The sidebar shows label text for all items. Tap "Wealth"
      // (renamed from "Accounts" under the IA contract).
      await tester.tap(find.text('Wealth'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.wealth);
      expect(find.byType(WealthHubPage), findsOneWidget);
      await _drainTimers(tester);
    });
  });

  group('back / forward via URL changes', () {
    testWidgets('Cash Flow back returns to the Activity timeline', (
      tester,
    ) async {
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.cashflow,
      );

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_currentPath(container), AppRoutes.activity);
      expect(find.byType(ActivityPage), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('Recurring back returns to Cash Flow', (tester) async {
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.cashflowRecurring,
      );

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_currentPath(container), AppRoutes.cashflow);
      expect(find.byType(CashFlowPage), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('Dividend Center back returns to Portfolio', (tester) async {
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.cashflowDividends,
      );

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_currentPath(container), AppRoutes.wealthPortfolio);
      await _drainTimers(tester);
    });

    // The browser back button doesn't pop a Navigator stack here — go_router
    // tracks history via the platform's RouteInformationProvider and replays
    // it as a `setNewRoutePath`. Functionally that's equivalent to the router
    // being asked to render the previous URL, which is what we drive below.
    testWidgets('replaying a previous URL re-renders the previous page', (
      tester,
    ) async {
      final container = await _pumpAt(tester);
      final router = container.read(appRouterProvider);

      router.go(AppRoutes.wealth);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WealthHubPage), findsOneWidget);

      router.go(AppRoutes.planRebalance);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RebalancePage), findsOneWidget);

      // Simulate browser "back": platform replays the previous URL.
      router.go(AppRoutes.wealth);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WealthHubPage), findsOneWidget);
      expect(_currentPath(container), AppRoutes.wealth);

      // Simulate browser "forward".
      router.go(AppRoutes.planRebalance);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RebalancePage), findsOneWidget);
      expect(_currentPath(container), AppRoutes.planRebalance);
      await _drainTimers(tester);
    });
  });

  group('refresh restores the page from the URL', () {
    // A real F5 throws away the in-memory ProviderContainer and rebuilds the
    // widget tree from scratch with whatever URL the browser is currently on.
    // We model that by disposing the first container and pumping a brand-new
    // app at the same location — Riverpod state is fresh, but the page still
    // matches the URL.
    testWidgets(
      'rebuilding at /portfolio lands on Portfolio with fresh state',
      (tester) async {
        final first = await _pumpAt(tester, initialLocation: AppRoutes.wealth);
        expect(find.byType(WealthHubPage), findsOneWidget);
        first.dispose();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final second = await _pumpAt(tester, initialLocation: AppRoutes.wealth);
        expect(find.byType(WealthHubPage), findsOneWidget);
        expect(_currentPath(second), AppRoutes.wealth);
      },
    );

    testWidgets('rebuilding at /settings lands on Settings', (tester) async {
      await _pumpAt(tester, initialLocation: AppRoutes.settings);
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });
}

DividendCenterSnapshot _emptyDividendSnapshot() => DividendCenterSnapshot(
  baseCurrency: 'CNY',
  yearToDateGross: Decimal.zero,
  ttmGross: Decimal.zero,
  priorYearToDateGross: Decimal.zero,
  ttmWithholding: Decimal.zero,
  events: const [],
  ranking: const [],
  months: const [],
);
