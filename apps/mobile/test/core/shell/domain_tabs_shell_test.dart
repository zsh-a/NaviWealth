import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/core/shell/domain_tabs_shell.dart';
import 'package:naviwealth/core/shell/shell_visibility.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

const _shellSpec = DomainShellSpec(
  scope: DomainScope.finance,
  label: 'TestOS',
  icon: Icons.home_outlined,
  selectedIcon: Icons.home,
  tabs: <DomainShellTab>[
    DomainShellTab(
      icon: Icons.looks_one_outlined,
      selectedIcon: Icons.looks_one,
      label: 'One',
      routePath: '/one',
    ),
    DomainShellTab(
      icon: Icons.looks_two_outlined,
      selectedIcon: Icons.looks_two,
      label: 'Two',
      routePath: '/two',
    ),
  ],
);

GoRouter _router({Widget one = const Center(child: Text('one'))}) => GoRouter(
  initialLocation: '/one',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          DomainTabsShell(shell: shell, spec: _shellSpec),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/one',
              builder: (context, state) =>
                  ShellTabPause(routePath: '/one', child: one),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/two',
              builder: (context, state) => const ShellTabPause(
                routePath: '/two',
                child: Center(child: Text('two')),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  tearDown(() => appSheetOverlayDepthListenable.value = 0);

  testWidgets('switching branches keeps the navigation shell mounted once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('domain-shell.content-transition')),
      findsNothing,
    );
    expect(find.text('one'), findsOneWidget);

    router.go('/two');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(StatefulNavigationShell), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('opening a sheet keeps routed content layout stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var probeBuilds = 0;
    double? bottomPadding;
    final router = _router(
      one: Builder(
        builder: (context) {
          probeBuilds++;
          bottomPadding = MediaQuery.paddingOf(context).bottom;
          return const Center(child: Text('one'));
        },
      ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buildsBeforeSheet = probeBuilds;
    final paddingBeforeSheet = bottomPadding;
    expect(paddingBeforeSheet, isNotNull);
    expect(paddingBeforeSheet, greaterThan(0));

    appSheetOverlayDepthListenable.value = 1;
    await tester.pump();

    expect(probeBuilds, buildsBeforeSheet);
    expect(bottomPadding, paddingBeforeSheet);
  });

  testWidgets('branch switch fades in and preserves offstage branch state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = _router(one: const _CounterProbe());
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mutate branch-one state, then leave the branch.
    await tester.tap(find.byKey(const ValueKey<String>('counter-probe')));
    await tester.pump();
    expect(find.text('count: 1'), findsOneWidget);

    const fadeKey = ValueKey<String>('domain-tabs-shell.branch-fade');
    router.go('/two');
    await tester.pump();

    // The fade has just started; the shell itself is still mounted once.
    expect(
      tester.widget<FadeTransition>(find.byKey(fadeKey)).opacity.value,
      lessThan(1),
    );
    expect(find.byType(StatefulNavigationShell), findsOneWidget);

    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(find.byKey(fadeKey)).opacity.value, 1);

    // Back to branch one: its state survived the round trip offstage.
    router.go('/one');
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('reduce motion keeps the branch switch instant', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    const fadeKey = ValueKey<String>('domain-tabs-shell.branch-fade');
    router.go('/two');
    await tester.pump();

    expect(tester.widget<FadeTransition>(find.byKey(fadeKey)).opacity.value, 1);
    expect(find.text('two'), findsOneWidget);
  });
}

/// Branch-one probe with local state, to prove the indexed stack (and the
/// fade wrapper around it) never remounts offstage branches.
class _CounterProbe extends StatefulWidget {
  const _CounterProbe();

  @override
  State<_CounterProbe> createState() => _CounterProbeState();
}

class _CounterProbeState extends State<_CounterProbe> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        key: const ValueKey<String>('counter-probe'),
        onTap: () => setState(() => _count++),
        child: Text('count: $_count'),
      ),
    );
  }
}
