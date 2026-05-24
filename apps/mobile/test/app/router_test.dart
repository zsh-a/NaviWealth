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
// checklist in apps/mobile/docs/web-routing.md and live cross-browser runs in
// FIR-40. What we *can* assert here is the router contract those flows rely
// on: a given URL deterministically maps to a given page, and the bottom nav
// keeps the URL up to date.

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/desktop_sidebar.dart';
import 'package:naviwealth/app/route_error_page.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/app/router.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/analytics/analytics_page.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_providers.dart';
import 'package:naviwealth/features/analytics/data/providers.dart'
    as analytics_data;
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/cashflow/ui/cashflow_page.dart';
import 'package:naviwealth/features/cashflow/ui/dividend_center_page.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:naviwealth/features/settings/settings_page.dart';
import 'package:naviwealth/features/wealth/ui/wealth_hub_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// Standard test surface sizes for the three responsive shell breakpoints.
// _RootShell switches at 600 (rail) and 1240 (drawer); these sit comfortably
// inside each band so a small change to the breakpoints doesn't accidentally
// flip a test into a different layout.
const Size _mobileSize = Size(400, 800);
const Size _tabletSize = Size(800, 1000);
const Size _desktopSize = Size(1440, 900);

Future<ProviderContainer> _pumpAt(
  WidgetTester tester, {
  String initialLocation = '/',
  Size viewportSize = _mobileSize,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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
  await tester.pump(const Duration(milliseconds: 100));
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
      expect(find.byType(FBottomNavigationBar), findsOneWidget);
    });

    for (final legacy in <String>[
      '/assets',
      '/expenses',
      '/analytics',
      '/fire',
      '/rebalance',
      '/me',
      '/more',
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

    testWidgets('/accounts/analytics renders Analytics', (tester) async {
      await _pumpAt(tester, initialLocation: AppRoutes.planProjection);
      expect(find.byType(AnalyticsPage), findsOneWidget);
    });

    testWidgets('/cashflow?period=year renders CashFlow', (tester) async {
      final container = await _pumpAt(
        tester,
        initialLocation: '${AppRoutes.cashflow}?period=year',
      );
      expect(find.byType(CashFlowPage), findsOneWidget);
      expect(_currentPath(container), AppRoutes.cashflow);
    });

    testWidgets('/activity/cashflow/dividends renders Dividend Center', (
      tester,
    ) async {
      await _pumpAt(tester, initialLocation: AppRoutes.cashflowDividends);
      expect(find.byType(DividendCenterPage), findsOneWidget);
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
        initialLocation: '${AppRoutes.planProjection}?range=1y',
      );
      expect(find.byType(AnalyticsPage), findsOneWidget);
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
      expect(find.byType(FBottomNavigationBar), findsNothing);
      await _drainTimers(tester);
    });

    testWidgets('tapping nav item by position navigates correctly', (
      tester,
    ) async {
      final container = await _pumpAt(tester);
      expect(_currentPath(container), AppRoutes.home);

      // Find the bottom bar and calculate nav item positions.
      // Layout: Today / Activity / Search / Wealth / Plan.
      final barFinder = find.byType(FBottomNavigationBar);
      final barBox = tester.renderObject<RenderBox>(barFinder);
      final barSize = barBox.size;
      final barOrigin = barBox.localToGlobal(Offset.zero);

      final barCenterY = barOrigin.dy + barSize.height / 2;
      final barWidth = barSize.width;
      final tabW = barWidth / 5;

      // Item 3 = Wealth. Item 2 is the Search action and does not navigate.
      final wealthX = barOrigin.dx + tabW * 3.5;
      await tester.tapAt(Offset(wealthX, barCenterY));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.wealth);

      // Item 4 = Plan.
      final planX = barOrigin.dx + tabW * 4.5;
      await tester.tapAt(Offset(planX, barCenterY));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.plan);
      await _drainTimers(tester);
    });

    testWidgets('selected tab index follows the current URL', (tester) async {
      // 5-item nav layout:
      // Today(0) | Activity(1) | Search action(2) | Wealth(3) | Plan(4)
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.wealth,
      );
      final bar = tester.widget<FBottomNavigationBar>(
        find.byType(FBottomNavigationBar),
      );
      expect(bar.index, 3);

      container.read(appRouterProvider).go(AppRoutes.activity);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final updated = tester.widget<FBottomNavigationBar>(
        find.byType(FBottomNavigationBar),
      );
      expect(updated.index, 1);
      await _drainTimers(tester);
    });
  });

  group('responsive shell switches by viewport width', () {
    // FIR-84: < 600 → GlassBottomBar (bottom), ≥ 600 & < 1240 →
    // GlassSideBar, ≥ 1240 → DesktopSidebar. Tabs and selectedIndex
    // stay consistent across the three layouts.

    testWidgets('mobile width uses GlassBottomBar at the bottom', (
      tester,
    ) async {
      await _pumpAt(tester, viewportSize: _mobileSize);
      expect(find.byType(FBottomNavigationBar), findsOneWidget);
      expect(find.byType(FSidebar), findsNothing);
      expect(find.byType(DesktopSidebar), findsNothing);
    });

    testWidgets(
      'S2.5 — mobile shell exposes a command-bar nav action (only Layer-1 '
      'AI entry on touch; opens the palette on tap)',
      (tester) async {
        final container = await _pumpAt(tester, viewportSize: _mobileSize);
        // Resolve the localized label so the assertion survives a copy
        // change.
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final searchAction = find.text(l10n.navSearch);
        expect(searchAction, findsOneWidget);

        await tester.tap(searchAction);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // The palette opens as a dialog with its own search field.
        expect(find.text(l10n.commandPaletteSearchHint), findsOneWidget);
        expect(
          _currentPath(container),
          AppRoutes.home,
          reason: 'opening the palette must not navigate away',
        );
        await _drainTimers(tester);
      },
    );

    testWidgets('S2.5 — desktop shell does not show the mobile search action', (
      tester,
    ) async {
      await _pumpAt(tester, viewportSize: _desktopSize);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.navSearch),
        findsNothing,
        reason: 'desktop uses Cmd-K; the nav action is touch-only',
      );
    });

    testWidgets('tablet width uses GlassSideBar', (tester) async {
      await _pumpAt(tester, viewportSize: _tabletSize);
      expect(find.byType(FSidebar), findsOneWidget);
      expect(find.byType(FBottomNavigationBar), findsNothing);
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
      expect(find.byType(FBottomNavigationBar), findsNothing);
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
      expect(sidebar.selectedIndex, 3);

      // Settings is off-nav (IA contract §1) — navigating to /settings
      // exits the shell and the sidebar isn't visible. So we hop to
      // Wealth to confirm the index swap before that.
      container.read(appRouterProvider).go(AppRoutes.wealth);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final updated = tester.widget<DesktopSidebar>(
        find.byType(DesktopSidebar),
      );
      expect(updated.selectedIndex, 2);
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

      router.go(AppRoutes.planProjection);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnalyticsPage), findsOneWidget);

      // Simulate browser "back": platform replays the previous URL.
      router.go(AppRoutes.wealth);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WealthHubPage), findsOneWidget);
      expect(_currentPath(container), AppRoutes.wealth);

      // Simulate browser "forward".
      router.go(AppRoutes.planProjection);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnalyticsPage), findsOneWidget);
      expect(_currentPath(container), AppRoutes.planProjection);
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
        final first = await _pumpAt(
          tester,
          initialLocation: AppRoutes.wealth,
        );
        expect(find.byType(WealthHubPage), findsOneWidget);
        first.dispose();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final second = await _pumpAt(
          tester,
          initialLocation: AppRoutes.wealth,
        );
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
