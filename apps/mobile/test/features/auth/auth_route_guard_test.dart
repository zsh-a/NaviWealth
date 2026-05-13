import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_guard.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/auth/token_store.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/data/db/providers.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:naviwealth/features/auth/data/auth_route_guard.dart';

class _Marker extends StatelessWidget {
  const _Marker(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Text(label, textDirection: TextDirection.ltr);
}

AuthSession _session({DateTime? expiresAt}) => AuthSession(
  accessToken: 'tok',
  expiresAt: expiresAt ?? DateTime.utc(2026, 12, 1),
  userId: 'u-1',
  deviceId: 'd-1',
);

ProviderContainer _container({Map<String, String>? seed}) {
  final keyStore = InMemoryKeyStore(seed);
  return ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(keyStore),
      // Plug the AuthRouteGuard into FIR-15's empty default — same wiring
      // bootstrap.dart does in production.
      routeGuardsProvider.overrideWith(
        (ref) => <RouteGuard>[ref.watch(authRouteGuardProvider)],
      ),
    ],
  );
}

GoRouter _buildRouter(ProviderContainer container, String initial) {
  return GoRouter(
    initialLocation: initial,
    refreshListenable: container.read(routeRefreshListenableProvider),
    redirect: (context, state) => routerRedirect(container, context, state),
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const _Marker('home')),
      GoRoute(
        path: AppRoutes.accounts,
        builder: (_, _) => const _Marker('portfolio'),
      ),
      GoRoute(path: '/login', builder: (_, _) => const _Marker('login')),
    ],
  );
}

Future<GoRouter> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required String initial,
}) async {
  final router = _buildRouter(container, initial);
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

String _path(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();

void main() {
  testWidgets('logged-out user requesting portfolio is bounced to /login', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    // Force AuthController build to settle on AuthLoggedOut.
    await container.read(authControllerProvider.future);

    final router = await _pump(tester, container, initial: AppRoutes.accounts);

    expect(_path(router), '/login?next=%2Faccounts');
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('logged-out user requesting / drops to /login (no next)', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final router = await _pump(tester, container, initial: '/');

    expect(_path(router), '/login');
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('logged-in user on /login is redirected home', (tester) async {
    final container = _container(
      seed: {TokenStore.storageKey: _session().encode()},
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final router = await _pump(tester, container, initial: '/login');

    expect(_path(router), '/');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets(
    'logged-in user on /login?next=/portfolio bounces back to portfolio',
    (tester) async {
      final container = _container(
        seed: {TokenStore.storageKey: _session().encode()},
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      final router = await _pump(
        tester,
        container,
        initial: '/login?next=${AppRoutes.accounts}',
      );

      expect(_path(router), AppRoutes.accounts);
      expect(find.text('portfolio'), findsOneWidget);
    },
  );

  testWidgets('logged-in user can navigate freely', (tester) async {
    final container = _container(
      seed: {TokenStore.storageKey: _session().encode()},
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final router = await _pump(tester, container, initial: AppRoutes.accounts);

    expect(_path(router), AppRoutes.accounts);
    expect(find.text('portfolio'), findsOneWidget);
  });

  testWidgets('logging in from /login bounces to home (no `next`)', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final router = await _pump(tester, container, initial: '/login');
    expect(_path(router), '/login');

    // Simulate a successful login by writing a session and bumping the
    // controller. The guard's `ref.listen` (via listenSelf) bumps the
    // router-version provider, prompting redirect re-evaluation.
    await container.read(tokenStoreProvider).write(_session());
    container.read(authControllerProvider.notifier).state = AsyncData(
      AuthLoggedIn(_session()),
    );
    await tester.pumpAndSettle();

    expect(_path(router), '/');
    expect(find.text('home'), findsOneWidget);
  });
}
