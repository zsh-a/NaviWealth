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

const _shellSpecWithHiddenReview = DomainShellSpec(
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
  hiddenTabs: <DomainShellTab>[
    DomainShellTab(
      icon: Icons.rate_review_outlined,
      selectedIcon: Icons.rate_review,
      label: 'Review',
      routePath: '/review',
    ),
  ],
);

GoRouter _router({
  Widget one = const Center(child: Text('one')),
  bool wrapOneWithPause = true,
}) => GoRouter(
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
              builder: (context, state) => wrapOneWithPause
                  ? ShellTabPause(routePath: '/one', child: one)
                  : one,
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

GoRouter _routerWithHiddenReview() => GoRouter(
  initialLocation: '/one',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          DomainTabsShell(shell: shell, spec: _shellSpecWithHiddenReview),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/one',
              builder: (context, state) => const ShellTabPause(
                routePath: '/one',
                child: Center(child: Text('one-live')),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/two',
              builder: (context, state) => const ShellTabPause(
                routePath: '/two',
                child: Center(child: Text('two-live')),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/review',
              builder: (context, state) => const ShellTabPause(
                routePath: '/review',
                child: Center(child: Text('review-live')),
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

  testWidgets('dock hides while a sheet is open and returns after it closes', (
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
    await tester.pumpAndSettle();
    expect(find.byType(FloatingGlassNavBar), findsOneWidget);

    // Sheet opens: the dock slides/fades out.
    appSheetOverlayDepthListenable.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FloatingGlassNavBar), findsNothing);

    // Sheet closes: the dock must come back (first-launch regression — a
    // stuck sheet depth used to suppress the dock indefinitely).
    appSheetOverlayDepthListenable.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FloatingGlassNavBar), findsOneWidget);
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

  testWidgets('branch switch is immediate and preserves paused branch state', (
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

    router.go('/two');
    await tester.pump();

    // Switching branches does not add a full-shell opacity layer.
    expect(
      find.byKey(const ValueKey<String>('domain-tabs-shell.branch-fade')),
      findsNothing,
    );
    expect(find.byType(StatefulNavigationShell), findsOneWidget);

    // Back to branch one: state below ShellTabPause survives the round trip.
    router.go('/one');
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('hidden branch retains every offstage visible tab subtree', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = _routerWithHiddenReview();
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

    // StatefulShellRoute initializes branches lazily. Visit the second branch
    // before hiding both visible tabs so the assertion measures retention,
    // not eager branch creation.
    router.go('/two');
    await tester.pumpAndSettle();
    router.go('/review');
    await tester.pumpAndSettle();

    expect(find.text('one-live'), findsNothing);
    expect(find.text('two-live'), findsNothing);
    expect(find.text('one-live', skipOffstage: false), findsOneWidget);
    expect(find.text('two-live', skipOffstage: false), findsOneWidget);
    expect(find.text('review-live'), findsOneWidget);
  });
}

/// Branch-one probe with local state, to prove the indexed stack (and the
/// pause gate inside it) never remounts offstage branches.
class _CounterProbe extends StatefulWidget {
  const _CounterProbe();

  @override
  State<_CounterProbe> createState() => _CounterProbeState();
}

class _CounterProbeState extends State<_CounterProbe> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return ShellTabPause(
      routePath: '/one',
      child: Center(
        child: GestureDetector(
          key: const ValueKey<String>('counter-probe'),
          onTap: () => setState(() => _count++),
          child: Text('count: $_count'),
        ),
      ),
    );
  }
}
