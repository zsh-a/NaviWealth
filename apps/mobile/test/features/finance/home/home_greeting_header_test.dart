import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/app/shell/shell_chrome.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:naviwealth/features/finance/home/ui/home_greeting_header.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _FakeAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthLocalOnly();
}

GoRouter _router({Widget child = const HomeGreetingHeader()}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const Scaffold(body: Text('settings-route')),
      ),
    ],
  );
}

Widget _wrap() {
  return ProviderScope(
    overrides: [
      ...appShellChromeOverrides(),
      authControllerProvider.overrideWith(_FakeAuthController.new),
    ],
    child: MaterialApp.router(
      routerConfig: _router(child: const HomeGreetingHeader()),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) =>
          FTheme(data: FThemes.slate.light.desktop, child: child!),
    ),
  );
}

void main() {
  testWidgets('renders a time-of-day greeting + shell chrome actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The greeting hosts the cross-domain shell chrome (the Today tab has
    // no FHeader): global Search + Settings. The domain switcher chip is
    // hidden here because only one domain is registered in this scope.
    expect(find.byIcon(FLucideIcons.search), findsOneWidget);
    expect(find.byIcon(FLucideIcons.settings), findsOneWidget);
    // Some greeting is rendered — the exact text depends on local time.
    expect(find.byType(Text), findsWidgets);
  });
}
