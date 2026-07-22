import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/life/data/life_events_provider.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';
import 'package:naviwealth/features/life/ui/life_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
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
