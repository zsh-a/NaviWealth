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
import 'package:naviwealth/app/router.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/analytics/analytics_page.dart';
import 'package:naviwealth/features/assets/assets_page.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpAt(
  WidgetTester tester, {
  String initialLocation = '/',
}) async {
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
      accountsStreamProvider.overrideWith(
        (ref) => Stream<List<Account>>.value(const []),
      ),
      // The real `physicalAssetsListProvider` reaches through
      // `appDatabaseProvider` → `FlutterSecureKeyStore`, neither of which
      // is available under `flutter_test`. Stub with an immediate empty
      // emission so the page resolves to its empty state instead of
      // spinning forever.
      physicalAssetsListProvider.overrideWith(
        (ref) => Stream.value(const []),
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
  await tester.pumpAndSettle();
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

void main() {
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
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('/assets renders Assets', (tester) async {
      await _pumpAt(tester, initialLocation: '/assets');
      expect(find.byType(AssetsPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
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

      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
      await tester.pumpAndSettle();
      expect(_currentPath(container), '/assets');
      expect(find.byType(AssetsPage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pie_chart_outline));
      await tester.pumpAndSettle();
      expect(_currentPath(container), '/analytics');
      expect(find.byType(AnalyticsPage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(_currentPath(container), '/settings');
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.dashboard_outlined));
      await tester.pumpAndSettle();
      expect(_currentPath(container), '/');
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('selected tab index follows the current URL', (tester) async {
      final container = await _pumpAt(tester, initialLocation: '/analytics');
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 2);

      container.read(appRouterProvider).go('/settings');
      await tester.pumpAndSettle();
      final updated = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(updated.selectedIndex, 3);
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

      router.go('/assets');
      await tester.pumpAndSettle();
      expect(find.byType(AssetsPage), findsOneWidget);

      router.go('/analytics');
      await tester.pumpAndSettle();
      expect(find.byType(AnalyticsPage), findsOneWidget);

      // Simulate browser "back": platform replays the previous URL.
      router.go('/assets');
      await tester.pumpAndSettle();
      expect(find.byType(AssetsPage), findsOneWidget);
      expect(_currentPath(container), '/assets');

      // Simulate browser "forward".
      router.go('/analytics');
      await tester.pumpAndSettle();
      expect(find.byType(AnalyticsPage), findsOneWidget);
      expect(_currentPath(container), '/analytics');
    });
  });

  group('refresh restores the page from the URL', () {
    // A real F5 throws away the in-memory ProviderContainer and rebuilds the
    // widget tree from scratch with whatever URL the browser is currently on.
    // We model that by disposing the first container and pumping a brand-new
    // app at the same location — Riverpod state is fresh, but the page still
    // matches the URL.
    testWidgets('rebuilding at /assets lands on Assets with fresh state', (
      tester,
    ) async {
      final first = await _pumpAt(tester, initialLocation: '/assets');
      expect(find.byType(AssetsPage), findsOneWidget);
      first.dispose();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final second = await _pumpAt(tester, initialLocation: '/assets');
      expect(find.byType(AssetsPage), findsOneWidget);
      expect(_currentPath(second), '/assets');
    });

    testWidgets('rebuilding at /settings lands on Settings', (tester) async {
      await _pumpAt(tester, initialLocation: '/settings');
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });
}
