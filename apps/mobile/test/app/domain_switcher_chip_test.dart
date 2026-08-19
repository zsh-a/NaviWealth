import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/shell/shell_chrome.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/core/shell/domain_switcher.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

DomainShellSpec _domain({
  required DomainScope scope,
  required String label,
  required String path,
}) => DomainShellSpec(
  scope: scope,
  label: label,
  icon: FLucideIcons.layers,
  selectedIcon: FLucideIcons.layers,
  tabs: [
    DomainShellTab(
      icon: FLucideIcons.layers,
      selectedIcon: FLucideIcons.layers,
      label: label,
      routePath: path,
    ),
  ],
);

void main() {
  testWidgets('Life hub links directly to its only active domain', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/life',
      routes: [
        GoRoute(
          path: '/life',
          builder: (_, _) => const Scaffold(body: DomainSwitcherChip()),
        ),
        GoRoute(
          path: '/today',
          builder: (_, _) => const Scaffold(body: Text('Finance today')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeDomainShellsProvider.overrideWithValue([
            _domain(
              scope: DomainScope.finance,
              label: 'FinanceOS',
              path: '/today',
            ),
          ]),
          domainSwitcherHomePathProvider.overrideWithValue('/life'),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) =>
              FTheme(data: FTheme.neutral.light.desktop, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FinanceOS'), findsOneWidget);
    await tester.tap(find.byType(DomainSwitcherChip));
    await tester.pumpAndSettle();
    expect(find.text('Finance today'), findsOneWidget);
  });

  testWidgets('Life hub uses a neutral icon-only workspace switcher', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/life',
      routes: [
        GoRoute(
          path: '/life',
          builder: (_, _) => const Scaffold(body: DomainSwitcherChip()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeDomainShellsProvider.overrideWithValue([
            _domain(
              scope: DomainScope.finance,
              label: 'FinanceOS',
              path: '/today',
            ),
            _domain(
              scope: DomainScope.health,
              label: 'HealthOS',
              path: '/health',
            ),
          ]),
          domainSwitcherHomePathProvider.overrideWithValue('/life'),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) =>
              FTheme(data: FTheme.neutral.light.desktop, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en', 'US'));
    expect(find.byType(DomainSwitcherChip), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.shellSwitchDomainTitle), findsOneWidget);
    expect(find.text('FinanceOS'), findsNothing);
    expect(find.byIcon(FLucideIcons.layers), findsOneWidget);
  });
}
