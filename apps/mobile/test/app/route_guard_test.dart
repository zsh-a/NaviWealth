// Verifies the redirect / refresh-listenable scaffold added in FIR-15:
//   - registered guards run in order and the first non-null wins
//   - a guard returning the current path is treated as no-op (no loop)
//   - bumping `routeRedirectVersionProvider` triggers go_router to re-evaluate
//
// We pump a minimal `GoRouter` (no shell, no deferred routes) so we exercise
// the real go_router redirect machinery rather than mocking GoRouterState.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_guard.dart';
import 'package:naviwealth/app/route_paths.dart';

class _StubGuard implements RouteGuard {
  _StubGuard(this._target);

  final String? _target;
  int calls = 0;

  @override
  RedirectPath redirect(GoRouterState state) {
    calls += 1;
    return _target;
  }
}

class _StubGuardFn implements RouteGuard {
  _StubGuardFn(this._compute);

  final String? Function() _compute;

  @override
  RedirectPath redirect(GoRouterState state) => _compute();
}

class _NoopBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('routerRedirect does not use context');
}

class _Marker extends StatelessWidget {
  const _Marker(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, textDirection: TextDirection.ltr);
}

/// Family-keyed provider so each test gets its own router seeded at the
/// requested initial path, while still resolving `routeGuardsProvider` and
/// `routeRefreshListenableProvider` from the surrounding container.
final _testRouterProvider = Provider.family<GoRouter, String>((ref, initial) {
  return GoRouter(
    initialLocation: initial,
    refreshListenable: ref.watch(routeRefreshListenableProvider),
    redirect: (context, state) => routerRedirect(ref.container, context, state),
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const _Marker('home')),
      GoRoute(
        path: AppRoutes.wealth,
        builder: (_, _) => const _Marker('portfolio'),
      ),
      GoRoute(path: '/login', builder: (_, _) => const _Marker('login')),
    ],
  );
});

Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  ProviderContainer container, {
  String initialLocation = '/',
}) async {
  final router = container.read(_testRouterProvider(initialLocation));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: WidgetsApp.router(
        color: const Color(0xFF000000),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;

void main() {
  testWidgets('no guards → original path renders', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = await _pumpRouter(
      tester,
      container,
      initialLocation: AppRoutes.wealth,
    );
    expect(_path(router), AppRoutes.wealth);
    expect(find.text('portfolio'), findsOneWidget);
  });

  testWidgets('a guard that redirects sends the user to its target', (
    tester,
  ) async {
    final guard = _StubGuard('/login');
    final container = ProviderContainer(
      overrides: [
        routeGuardsProvider.overrideWithValue([guard]),
      ],
    );
    addTearDown(container.dispose);

    final router = await _pumpRouter(
      tester,
      container,
      initialLocation: AppRoutes.wealth,
    );

    expect(_path(router), '/login');
    expect(find.text('login'), findsOneWidget);
    expect(guard.calls, greaterThanOrEqualTo(1));
  });

  test('routerRedirect short-circuits at the first non-null guard', () {
    // The integration test above can't observe call counts cleanly because
    // go_router re-runs the redirect chain after each redirect. Drive the
    // function directly here so we can assert "third guard never ran" on a
    // single evaluation.
    final first = _StubGuardFn(() => null);
    var secondCalls = 0;
    var thirdCalls = 0;
    final second = _StubGuardFn(() {
      secondCalls += 1;
      return '/login';
    });
    final third = _StubGuardFn(() {
      thirdCalls += 1;
      return '/never';
    });
    final container = ProviderContainer(
      overrides: [
        routeGuardsProvider.overrideWithValue([first, second, third]),
      ],
    );
    addTearDown(container.dispose);

    // We need a real GoRouterState; the cheapest way to get one is to spin up
    // a throwaway router and grab `configuration` for the constructor.
    final probeRouter = GoRouter(
      initialLocation: AppRoutes.wealth,
      routes: <RouteBase>[
        GoRoute(path: AppRoutes.wealth, builder: (_, _) => const _Marker('a')),
      ],
    );
    addTearDown(probeRouter.dispose);

    final result = container.read(
      Provider<String?>((ref) {
        final state = GoRouterState(
          probeRouter.configuration,
          uri: Uri.parse(AppRoutes.wealth),
          matchedLocation: AppRoutes.wealth,
          fullPath: AppRoutes.wealth,
          pathParameters: const {},
          pageKey: const ValueKey(AppRoutes.wealth),
        );
        return routerRedirect(ref.container, _NoopBuildContext(), state);
      }),
    );

    expect(result, '/login');
    expect(secondCalls, 1);
    expect(thirdCalls, 0);
  });

  testWidgets('guard returning current path is treated as no-op (no loop)', (
    tester,
  ) async {
    final guard = _StubGuard('/login');
    final container = ProviderContainer(
      overrides: [
        routeGuardsProvider.overrideWithValue([guard]),
      ],
    );
    addTearDown(container.dispose);

    final router = await _pumpRouter(
      tester,
      container,
      initialLocation: '/login',
    );

    expect(_path(router), '/login');
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('bumping the version provider re-runs guards', (tester) async {
    String? target;
    final guard = _StubGuardFn(() => target);
    final container = ProviderContainer(
      overrides: [
        routeGuardsProvider.overrideWithValue([guard]),
      ],
    );
    addTearDown(container.dispose);

    final router = await _pumpRouter(
      tester,
      container,
      initialLocation: AppRoutes.wealth,
    );
    expect(_path(router), AppRoutes.wealth);

    // Flip the guard to redirect, then bump the version. go_router should
    // re-run redirects for the current location.
    target = '/login';
    container.read(routeRedirectVersionProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(_path(router), '/login');
  });
}
