// Behavior verification for the web routing surface set up in FIR-14:
// path URL strategy + go_router + bottom-nav shell. These tests exercise the
// three flows called out in FIR-43:
//   1. deep-link arrival (someone hits /assets directly in the address bar)
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/desktop_sidebar.dart';
import 'package:naviwealth/app/router.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/analytics/analytics_page.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_providers.dart';
import 'package:naviwealth/features/analytics/data/providers.dart'
    as analytics_data;
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/features/portfolio/portfolio_page.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:naviwealth/features/settings/settings_page.dart';
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
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async => const {};
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
      holdingServiceProvider.overrideWith((ref) async => _EmptyHoldingService()),
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
  // Disable the SuperFab pulse animation globally to avoid pending timer
  // assertions from the looping animation controller.
  setUp(() {
    SuperFab.disablePulseGlobally = true;
    addTearDown(() => SuperFab.disablePulseGlobally = false);
  });

  // Ignore rendering overflow errors from the floating pill bar and MorePage
  // cards — the test viewport (400×800) is smaller than production.
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
      expect(find.byType(FloatingPillNavigationBar), findsOneWidget);
    });

    testWidgets('/assets redirects to /portfolio and renders Portfolio', (
      tester,
    ) async {
      final container = await _pumpAt(tester, initialLocation: '/assets');
      expect(find.byType(PortfolioPage), findsOneWidget);
      expect(_currentPath(container), '/portfolio');
      expect(find.byType(FloatingPillNavigationBar), findsOneWidget);
    });

    testWidgets('/portfolio renders Portfolio', (tester) async {
      final container = await _pumpAt(tester, initialLocation: '/portfolio');
      expect(find.byType(PortfolioPage), findsOneWidget);
      expect(_currentPath(container), '/portfolio');
    });

    testWidgets('/more redirects to /', (tester) async {
      final container = await _pumpAt(tester, initialLocation: '/more');
      expect(find.byType(HomePage), findsOneWidget);
      expect(_currentPath(container), '/');
    });

    testWidgets('/assets/trade redirects to /portfolio/trade', (tester) async {
      final container = await _pumpAt(tester, initialLocation: '/assets/trade');
      expect(_currentPath(container), '/portfolio/trade');
    });

    testWidgets('/analytics renders Analytics', (tester) async {
      await _pumpAt(tester, initialLocation: '/analytics');
      expect(find.byType(AnalyticsPage), findsOneWidget);
    });

    testWidgets('/settings renders Settings', (tester) async {
      await _pumpAt(tester, initialLocation: '/settings');
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('unknown query params on a known path do not break the page', (
      tester,
    ) async {
      // FIR-43 calls out /analytics?range=1y as a future query-driven deep
      // link. The :range param itself isn't wired yet (that's a follow-up
      // feature), but at minimum an unknown query string must not 404.
      await _pumpAt(tester, initialLocation: '/analytics?range=1y');
      expect(find.byType(AnalyticsPage), findsOneWidget);
    });
  });

  group('tab navigation keeps URL in sync', () {
    testWidgets('tapping each bottom-nav tab updates the URL and the page', (
      tester,
    ) async {
      final container = await _pumpAt(tester);
      expect(_currentPath(container), '/');

      // Navigate via the router directly — the pill bar layout and icon
      // disambiguation are covered by the positional tap test below.
      container.read(appRouterProvider).go('/portfolio');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), '/portfolio');
      expect(find.byType(PortfolioPage), findsOneWidget);

      container.read(appRouterProvider).go('/analytics');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), '/analytics');

      container.read(appRouterProvider).go('/ai');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), '/ai');

      container.read(appRouterProvider).go('/');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), '/');
      expect(find.byType(HomePage), findsOneWidget);
      await _drainTimers(tester);
    });

    testWidgets('tapping nav item by position navigates correctly', (
      tester,
    ) async {
      final container = await _pumpAt(tester);
      expect(_currentPath(container), '/');

      // Find the pill bar and calculate nav item positions.
      // Layout: [item0] [item1]  [68dp gap]  [item2] [item3]
      final barFinder = find.byType(FloatingPillNavigationBar);
      final barBox = tester.renderObject<RenderBox>(barFinder);
      final barSize = barBox.size;
      final barOrigin = barBox.localToGlobal(Offset.zero);

      // The pill bar is at the bottom 64px of the 96px stack.
      // Nav items are centered vertically in the pill bar.
      final pillBarTop = barOrigin.dy + (barSize.height - 64);
      final pillBarCenterY = pillBarTop + 32;

      // Each Expanded item gets (barWidth - 68) / 4 width.
      final itemW = (barSize.width - 68) / 4;

      // Item 1 = Portfolio (second from left).
      final portfolioX = barOrigin.dx + itemW * 1.5;
      await tester.tapAt(Offset(portfolioX, pillBarCenterY));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), '/portfolio');
      await _drainTimers(tester);
    });

    testWidgets('selected tab index follows the current URL', (tester) async {
      // 4-tab layout: Home(0) | Portfolio(1) | Analytics(2) | AI(3)
      final container = await _pumpAt(tester, initialLocation: '/analytics');
      // /analytics is now tab index 2.
      final bar = tester.widget<FloatingPillNavigationBar>(
        find.byType(FloatingPillNavigationBar),
      );
      expect(bar.selectedIndex, 2);

      container.read(appRouterProvider).go('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final updated = tester.widget<FloatingPillNavigationBar>(
        find.byType(FloatingPillNavigationBar),
      );
      // Settings highlights Portfolio (index 1).
      expect(updated.selectedIndex, 1);
      await _drainTimers(tester);
    });
  });

  group('responsive shell switches by viewport width', () {
    // FIR-84: < 600 → NavigationBar (bottom), 600..1240 → NavigationRail
    // (extended above 900), ≥ 1240 → NavigationDrawer. Tabs and selectedIndex
    // stay consistent across the three layouts.

    testWidgets('mobile width uses FloatingPillNavigationBar at the bottom', (tester) async {
      await _pumpAt(tester, viewportSize: _mobileSize);
      expect(find.byType(FloatingPillNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(DesktopSidebar), findsNothing);
    });

    testWidgets('tablet width uses a collapsed NavigationRail', (tester) async {
      // 800px is below the 900px extended-rail threshold.
      await _pumpAt(tester, viewportSize: _tabletSize);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(FloatingPillNavigationBar), findsNothing);
      expect(find.byType(DesktopSidebar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
    });

    testWidgets('tablet width ≥ 900 extends the NavigationRail', (tester) async {
      await _pumpAt(tester, viewportSize: const Size(1100, 1000));
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('desktop width uses the FIR-106 collapsible sidebar', (tester) async {
      await _pumpAt(tester, viewportSize: _desktopSize);
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(FloatingPillNavigationBar), findsNothing);
    });

    testWidgets('NavigationRail selectedIndex follows the current URL', (
      tester,
    ) async {
      final container = await _pumpAt(
        tester,
        initialLocation: '/analytics',
        viewportSize: _tabletSize,
      );
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      // /analytics is now tab index 2
      expect(rail.selectedIndex, 2);

      container.read(appRouterProvider).go('/portfolio');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final updated = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(updated.selectedIndex, 1);
      await _drainTimers(tester);
    });

    testWidgets('DesktopSidebar selectedIndex follows the current URL', (
      tester,
    ) async {
      final container = await _pumpAt(
        tester,
        initialLocation: '/fire',
        viewportSize: _desktopSize,
      );
      final sidebar = tester.widget<DesktopSidebar>(
        find.byType(DesktopSidebar),
      );
      // /fire → Analytics tab (index 2)
      expect(sidebar.selectedIndex, 2);

      container.read(appRouterProvider).go('/portfolio');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final updated = tester.widget<DesktopSidebar>(
        find.byType(DesktopSidebar),
      );
      expect(updated.selectedIndex, 1);
      await _drainTimers(tester);
    });

    testWidgets('tapping a rail destination updates the URL', (tester) async {
      final container = await _pumpAt(tester, viewportSize: _tabletSize);
      expect(_currentPath(container), '/');

      // The rail shows label text for all items via NavigationRailLabelType.all.
      // Tap the "Portfolio" label to navigate.
      await tester.tap(find.text('Portfolio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), '/portfolio');
      expect(find.byType(PortfolioPage), findsOneWidget);
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

      router.go('/portfolio');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PortfolioPage), findsOneWidget);

      router.go('/analytics');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnalyticsPage), findsOneWidget);

      // Simulate browser "back": platform replays the previous URL.
      router.go('/portfolio');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PortfolioPage), findsOneWidget);
      expect(_currentPath(container), '/portfolio');

      // Simulate browser "forward".
      router.go('/analytics');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnalyticsPage), findsOneWidget);
      expect(_currentPath(container), '/analytics');
      await _drainTimers(tester);
    });
  });

  group('refresh restores the page from the URL', () {
    // A real F5 throws away the in-memory ProviderContainer and rebuilds the
    // widget tree from scratch with whatever URL the browser is currently on.
    // We model that by disposing the first container and pumping a brand-new
    // app at the same location — Riverpod state is fresh, but the page still
    // matches the URL.
    testWidgets('rebuilding at /portfolio lands on Portfolio with fresh state', (
      tester,
    ) async {
      final first = await _pumpAt(tester, initialLocation: '/portfolio');
      expect(find.byType(PortfolioPage), findsOneWidget);
      first.dispose();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final second = await _pumpAt(tester, initialLocation: '/portfolio');
      expect(find.byType(PortfolioPage), findsOneWidget);
      expect(_currentPath(second), '/portfolio');
    });

    testWidgets('rebuilding at /settings lands on Settings', (tester) async {
      await _pumpAt(tester, initialLocation: '/settings');
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });
}
