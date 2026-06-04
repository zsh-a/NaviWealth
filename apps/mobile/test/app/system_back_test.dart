// App-wide invariant: the Android system back gesture must never exit the
// app from inside *content*. It may exit only after a second back gesture
// at a true app root (Home or an auth gate such as login / onboarding).
//
// This is a regression guard for the class of bug where a content route
// is mounted outside the dock shell (the only widget with a root
// system-back handler) and, when it is the navigation-stack root, the
// gesture falls through to the OS and quits the app. The Settings subtree
// hit exactly this after the D-2.3b multi-domain refactor; [SystemBackScope]
// now wraps it. These tests pin the behaviour for Settings *and* the
// in-shell routes so a future shell refactor can't silently reintroduce it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/app/router.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GoRouter> _boot(WidgetTester tester, String initial) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
      appRouterProvider.overrideWith(
        (ref) => buildAppRouter(ref, initialLocation: initial),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => preloadDeferredRoutesForTest());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NaviWealthApp(),
    ),
  );
  await _drain(tester);
  return container.read(appRouterProvider);
}

/// Fire the one-shot skeleton min-display timers pages schedule on mount,
/// so the FakeAsync zone has no pending timers at teardown.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

String _path(GoRouter r) => r.routeInformationProvider.value.uri.path;

void _captureSystemNavigatorPop(
  WidgetTester tester,
  ValueSetter<MethodCall> onCall,
) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') onCall(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  setUp(() {
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains('overflowed')) return;
      orig?.call(d);
    };
    addTearDown(() => FlutterError.onError = orig);
  });

  group('Root exits require a second system back gesture', () {
    testWidgets('Home root → first back arms, second back exits', (
      tester,
    ) async {
      var platformPopCalls = 0;
      _captureSystemNavigatorPop(tester, (_) => platformPopCalls++);

      final router = await _boot(tester, AppRoutes.home);
      expect(_path(router), AppRoutes.home);

      final first = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(first, isTrue);
      expect(platformPopCalls, 0);

      final second = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(second, isTrue);
      expect(platformPopCalls, 1);
    });

    testWidgets('navigating after first back disarms root exit', (
      tester,
    ) async {
      var platformPopCalls = 0;
      _captureSystemNavigatorPop(tester, (_) => platformPopCalls++);

      final router = await _boot(tester, AppRoutes.home);
      expect(_path(router), AppRoutes.home);

      final first = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(first, isTrue);
      expect(platformPopCalls, 0);

      router.go(AppRoutes.activity);
      await _drain(tester);
      expect(_path(router), AppRoutes.activity);

      final second = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(second, isTrue);
      expect(_path(router), AppRoutes.home);
      expect(platformPopCalls, 0);
    });

    testWidgets('/login root → first back arms, second back exits', (
      tester,
    ) async {
      var platformPopCalls = 0;
      _captureSystemNavigatorPop(tester, (_) => platformPopCalls++);

      final router = await _boot(tester, AppRoutes.login);
      expect(_path(router), AppRoutes.login);

      final first = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(first, isTrue);
      expect(platformPopCalls, 0);

      final second = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(second, isTrue);
      expect(platformPopCalls, 1);
    });

    testWidgets('/onboarding root → first back arms, second back exits', (
      tester,
    ) async {
      var platformPopCalls = 0;
      _captureSystemNavigatorPop(tester, (_) => platformPopCalls++);

      final router = await _boot(tester, AppRoutes.onboarding);
      expect(_path(router), AppRoutes.onboarding);

      final first = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(first, isTrue);
      expect(platformPopCalls, 0);

      final second = await tester.binding.handlePopRoute();
      await _drain(tester);
      expect(second, isTrue);
      expect(platformPopCalls, 1);
    });
  });

  group('Settings (out-of-shell) — must not exit on system back', () {
    testWidgets('/settings as stack root → handled, lands on Home', (
      tester,
    ) async {
      final router = await _boot(tester, AppRoutes.settings);
      expect(_path(router), AppRoutes.settings);
      expect(router.canPop(), isFalse, reason: 'settings is the stack root');

      final handled = await tester.binding.handlePopRoute();
      await _drain(tester);

      expect(handled, isTrue, reason: 'gesture handled — app must not exit');
      expect(_path(router), AppRoutes.home);
    });

    testWidgets(
      'deep-linked /settings/ai-llm → /settings → Home, never exits',
      (tester) async {
        final router = await _boot(tester, AppRoutes.settingsAiLlm);
        expect(_path(router), AppRoutes.settingsAiLlm);
        expect(router.canPop(), isTrue, reason: 'parent /settings is in stack');

        final first = await tester.binding.handlePopRoute();
        await _drain(tester);
        expect(first, isTrue);
        expect(_path(router), AppRoutes.settings);
        expect(router.canPop(), isFalse, reason: 'now at settings root');

        final second = await tester.binding.handlePopRoute();
        await _drain(tester);
        expect(second, isTrue, reason: 'gesture handled — app must not exit');
        expect(_path(router), AppRoutes.home);
      },
    );
  });

  group('In-shell deep routes — back walks up, never exits', () {
    // Representative deep, nested routes across three branches. (Form
    // pages like /wealth/accounts/new are intentionally excluded — their
    // heavy layout throws unrelated rendering errors in the test viewport;
    // the back-stack invariant they share is already covered by these.)
    const cases = <String, String>{
      AppRoutes.planFire: AppRoutes.plan,
      AppRoutes.expenseReport: AppRoutes.activityExpenses,
      AppRoutes.wealthPortfolio: AppRoutes.wealth,
      AppRoutes.wealthWatchlist: AppRoutes.wealth,
    };
    cases.forEach((deep, parent) {
      testWidgets('go($deep) → system back → $parent', (tester) async {
        final router = await _boot(tester, '/');
        router.go(deep);
        await _drain(tester);
        expect(_path(router), deep);

        final handled = await tester.binding.handlePopRoute();
        await _drain(tester);

        expect(handled, isTrue, reason: 'gesture handled — app must not exit');
        expect(_path(router), parent, reason: 'walks up one level');
      });
    });
  });
}
