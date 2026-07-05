import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/nav.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('logicalParentOf', () {
    test('drops the last segment of a nested path', () {
      expect(logicalParentOf('/activity/expenses/new'), '/activity/expenses');
      expect(logicalParentOf('/accounts/list/abc123'), '/accounts/list');
      expect(
        logicalParentOf('/accounts/liabilities/new'),
        '/accounts/liabilities',
      );
    });

    test('a primary tab root collapses to Home', () {
      expect(logicalParentOf('/accounts'), '/');
      expect(logicalParentOf('/activity'), '/');
    });

    test('Home and empty stay at Home', () {
      expect(logicalParentOf('/'), '/');
      expect(logicalParentOf(''), '/');
    });

    test('ignores query string when computing the parent', () {
      expect(
        logicalParentOf('/accounts/list/abc123?selected=xyz'),
        '/accounts/list',
      );
    });
  });

  group('smartPop precedence', () {
    // The four-step back protocol is the single point of truth for the
    // back arrow, Esc, system back, and post-save navigation. Tests pin
    // step 3 (clear `?selected=`) and step 4 (fallback) explicitly —
    // steps 1/2 (GoRouter / Navigator pop) are covered by widget tests
    // upstream and are visible from the implementation.

    Future<GoRouter> pumpRouter(
      WidgetTester tester, {
      required String initialLocation,
      required GlobalKey<NavigatorState> innerNavKey,
      required void Function(BuildContext) onTapBack,
      String fallback = '/accounts',
    }) async {
      final router = GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(
            path: '/accounts',
            builder: (_, _) => const Scaffold(body: Text('accounts hub')),
          ),
          GoRoute(
            path: '/accounts/list',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (innerContext) {
                  return TextButton(
                    key: const ValueKey('back'),
                    onPressed: () => onTapBack(innerContext),
                    child: const Text('back'),
                  );
                },
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Navigator(
            key: innerNavKey,
            onGenerateRoute: (settings) =>
                MaterialPageRoute(builder: (_) => child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('clears ?selected= before falling back when stack is empty', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      final router = await pumpRouter(
        tester,
        initialLocation: '/accounts/list?selected=abc&filter=active',
        innerNavKey: navKey,
        onTapBack: (context) => popOrGo(context, fallback: '/accounts'),
      );
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/accounts/list?selected=abc&filter=active',
      );

      await tester.tap(find.byKey(const ValueKey('back')));
      await tester.pumpAndSettle();

      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, '/accounts/list');
      expect(uri.queryParameters.containsKey('selected'), isFalse);
      expect(uri.queryParameters['filter'], 'active');
    });

    testWidgets(
      'falls back to logical parent when no stack and no ?selected=',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final router = await pumpRouter(
          tester,
          initialLocation: '/accounts/list',
          innerNavKey: navKey,
          onTapBack: (context) => popOrGo(context, fallback: '/accounts'),
        );

        await tester.tap(find.byKey(const ValueKey('back')));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/accounts');
      },
    );

    testWidgets(
      'clearSelectedDetail returns false when no ?selected= present',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        bool? result;
        await pumpRouter(
          tester,
          initialLocation: '/accounts/list',
          innerNavKey: navKey,
          onTapBack: (context) => result = clearSelectedDetail(context),
        );

        await tester.tap(find.byKey(const ValueKey('back')));
        await tester.pumpAndSettle();
        expect(result, isFalse);
      },
    );
  });
}
