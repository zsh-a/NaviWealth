// Verifies the GoRouter errorBuilder added in FIR-15:
//   - unknown URL → 404 page that includes the URL
//   - "back to overview" navigates the user out

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/route_error_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../support/test_app_theme.dart';

GoRouter _router({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    errorBuilder: (context, state) =>
        RouteErrorPage(state: state, homePath: '/'),
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const Text('home')),
    ],
  );
}

Widget _wrap(GoRouter router) {
  return MaterialApp.router(
    builder: buildTestAppTheme,
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

void main() {
  testWidgets('unknown URL renders 404 with the path the user tried', (
    tester,
  ) async {
    final router = _router(initialLocation: '/does-not-exist');
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.textContaining('/does-not-exist'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.home), findsOneWidget);
  });

  testWidgets('back-to-overview navigates to /', (tester) async {
    final router = _router(initialLocation: '/nope');
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.home));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });
}
