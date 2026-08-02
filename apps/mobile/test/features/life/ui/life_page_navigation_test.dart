import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';
import 'package:naviwealth/features/life/ui/life_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

DomainPack _domainPack(
  DomainScope scope,
  String label, {
  String? reviewRoutePath,
}) {
  final path = '/${scope.wire}';
  return DomainPack(
    scope: scope,
    tabPaths: [path],
    reviewRoutePath: reviewRoutePath,
    shellSpecBuilder: (_) => DomainShellSpec(
      scope: scope,
      label: label,
      icon: FLucideIcons.layers,
      selectedIcon: FLucideIcons.layers,
      tabs: const [],
    ),
  );
}

void main() {
  testWidgets('keeps a compact task-first hierarchy without duplicate nav', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final priority = LifeEvent(
      id: 'priority',
      at: DateTime.utc(2026, 7, 22, 16, 9),
      domain: DomainScope.execution,
      template: LifeEventTemplate.financeDaySummary,
      params: const ['1', '0', '0'],
      priority: LifeSignalPriority.high,
    );
    final recent = LifeEvent(
      id: 'recent',
      at: DateTime.utc(2026, 7, 22, 8),
      domain: DomainScope.finance,
      template: LifeEventTemplate.financeDaySummary,
      params: const ['3', '2', '1'],
    );
    final packs = [
      _domainPack(DomainScope.finance, 'FinanceOS'),
      _domainPack(DomainScope.health, 'HealthOS'),
      _domainPack(
        DomainScope.knowledge,
        'KnowledgeOS',
        reviewRoutePath: '/knowledge/review',
      ),
      _domainPack(DomainScope.execution, 'ExecutionOS'),
    ];
    final router = GoRouter(
      initialLocation: '/life',
      routes: [GoRoute(path: '/life', builder: (_, _) => const LifePage())],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lifeEventsProvider.overrideWithValue([priority, recent]),
          lifeHeroSummaryProvider.overrideWithValue(
            const LifeHeroSummary(
              domainCount: 4,
              signalCount: 2,
              highPriorityCount: 1,
              signalCountByDomain: {
                DomainScope.finance: 1,
                DomainScope.execution: 1,
              },
              highCountByDomain: {DomainScope.execution: 1},
            ),
          ),
          lifeWorkbenchDomainsProvider.overrideWithValue(packs),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) =>
              FTheme(data: FThemes.slate.light.desktop, child: child!),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final l10n = lookupAppLocalizations(const Locale('en', 'US'));
    final priorityTop = tester
        .getTopLeft(find.text(l10n.lifeTimelinePriorityTitle))
        .dy;
    final recentTop = tester.getTopLeft(find.text(l10n.lifeTimelineTitle)).dy;
    expect(priorityTop, lessThan(recentTop));
    expect(
      tester.getSize(find.byKey(const ValueKey('life-summary-card'))).height,
      lessThan(100),
    );

    for (final scope in DomainScope.values) {
      expect(find.byKey(ValueKey<DomainScope>(scope)), findsNothing);
    }

    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    await tester.pump(const Duration(milliseconds: 150));

    final priorityWideTop = tester
        .getTopLeft(find.text(l10n.lifeTimelinePriorityTitle))
        .dy;
    final reviewWideTop = tester.getTopLeft(find.text(l10n.lifeReviewTitle)).dy;
    final recentWideTop = tester
        .getTopLeft(find.text(l10n.lifeTimelineTitle))
        .dy;
    expect(priorityWideTop, reviewWideTop);
    expect(recentWideTop, greaterThan(priorityWideTop));
  });

  testWidgets('opens domain reviews from one Life review entry', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/life',
      routes: [
        GoRoute(path: '/life', builder: (_, _) => const LifePage()),
        GoRoute(
          path: '/knowledge/review',
          builder: (_, _) => const Scaffold(body: Text('Knowledge review')),
        ),
        GoRoute(
          path: '/execution/review',
          builder: (_, _) => const Scaffold(body: Text('Execution review')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lifeEventsProvider.overrideWithValue(const []),
          lifeHeroSummaryProvider.overrideWithValue(
            const LifeHeroSummary(
              domainCount: 2,
              signalCount: 0,
              highPriorityCount: 0,
            ),
          ),
          lifeWorkbenchDomainsProvider.overrideWithValue([
            _domainPack(
              DomainScope.knowledge,
              'KnowledgeOS',
              reviewRoutePath: '/knowledge/review',
            ),
            _domainPack(
              DomainScope.execution,
              'ExecutionOS',
              reviewRoutePath: '/execution/review',
            ),
          ]),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) =>
              FTheme(data: FThemes.slate.light.desktop, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('life-review-entry')),
      findsOneWidget,
    );
    await tester.tap(find.text('Close the loop'));
    await tester.pumpAndSettle();

    expect(find.text('Choose what you want to review.'), findsOneWidget);
    expect(find.text('Knowledge'), findsOneWidget);
    expect(find.text('Execution'), findsOneWidget);

    await tester.tap(find.text('Knowledge'));
    await tester.pumpAndSettle();
    expect(find.text('Knowledge review'), findsOneWidget);
  });

  testWidgets(
    'row opens its source while the independent action opens the signal sheet',
    (tester) async {
      final event = LifeEvent(
        id: 'finance-today',
        at: DateTime.utc(2026, 7, 22, 8),
        domain: DomainScope.finance,
        template: LifeEventTemplate.financeDaySummary,
        params: const ['3', '2', '1'],
        routePath: '/target',
        actionSuggestion: const LifeActionSuggestion(
          template: LifeActionTemplate.reviewFinanceActivity,
          sourceRowFamily: 'fin:journal_entries',
          sourceRowId: 'day:2026-07-22',
        ),
      );
      final router = GoRouter(
        initialLocation: '/life',
        routes: [
          GoRoute(path: '/life', builder: (_, _) => const LifePage()),
          GoRoute(
            path: '/target',
            builder: (_, _) => const Scaffold(body: Text('Source page')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lifeEventsProvider.overrideWithValue([event]),
            lifeHeroSummaryProvider.overrideWithValue(
              const LifeHeroSummary(
                domainCount: 1,
                signalCount: 1,
                highPriorityCount: 0,
              ),
            ),
            lifeWorkbenchDomainsProvider.overrideWithValue(const []),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) =>
                FTheme(data: FThemes.slate.light.desktop, child: child!),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await tester.tap(find.text('3 finance entries today'));
      await tester.pumpAndSettle();
      expect(find.text('Source page'), findsOneWidget);

      router.go('/life');
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel('Create action for 3 finance entries today'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Update details'), findsOneWidget);
      expect(find.text('Why this appeared'), findsOneWidget);
      expect(find.text('Source page'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
    },
  );
}
