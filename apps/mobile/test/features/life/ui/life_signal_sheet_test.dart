import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/life/domain/life_event.dart';
import 'package:naviwealth/features/life/ui/life_signal_sheet.dart';
import 'package:naviwealth/features/settings/ui/domains_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _RecordingApplier implements ProposalApplier {
  ReadyProposalPlan? appliedPlan;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    appliedPlan = plan;
    return const ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: 'created-action',
      appliedTable: 'execution_actions',
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}

String? _createdRoute(String family, String id) =>
    family == 'exec:execution_actions' ? '/registered-execution/$id' : null;

class _OptInStore extends Fake implements DomainOptInStore {
  DomainOptIns value = DomainOptIns.financeOnly;
  @override
  Future<DomainOptIns> read() async => value;
  @override
  Future<void> write(DomainOptIns optIns) async => value = optIns;
}

String _settingsSubtitle(AppLocalizations l10n, bool enabled) =>
    enabled ? 'Enabled' : 'Disabled';

void main() {
  testWidgets(
    'enabling Execution returns to the same suggestion without creating it',
    (tester) async {
      final store = _OptInStore();
      final applier = _RecordingApplier();
      final event = LifeEvent(
        id: 'signal',
        at: DateTime.utc(2026),
        domain: DomainScope.finance,
        template: LifeEventTemplate.financeDaySummary,
        params: const ['3', '2', '1'],
        actionSuggestion: const LifeActionSuggestion(
          template: LifeActionTemplate.reviewFinanceActivity,
          sourceRowFamily: 'fin:journal_entries',
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: FButton(
                onPress: () => showLifeSignalSheet(
                  context: context,
                  event: event,
                  executionEnabled: false,
                ),
                child: const Text('Open signal'),
              ),
            ),
          ),
          GoRoute(
            path: '/settings/domains',
            builder: (_, _) => const DomainsSettingsPage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            domainOptInStoreProvider.overrideWith((_) async => store),
            domainPackRegistryProvider.overrideWithValue(const [
              DomainPack(
                scope: DomainScope.execution,
                tabPaths: ['/registered-execution'],
                settingsSpec: DomainSettingsSpec(
                  icon: FLucideIcons.listTodo,
                  label: 'ExecutionOS',
                  subtitle: _settingsSubtitle,
                ),
              ),
            ]),
            proposalApplierProvider.overrideWith((_) async => applier),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) =>
                FTheme(data: FTheme.neutral.light.desktop, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open signal'));
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.lifeSignalEnableExecution));
      await tester.pumpAndSettle();
      expect(find.byType(DomainsSettingsPage), findsOneWidget);
      expect(
        GoRouterState.of(tester.element(find.byType(DomainsSettingsPage)))
            .uri
            .queryParameters['resume'],
        'execution',
      );
      await tester.tap(find.byType(FSwitch));
      await tester.pumpAndSettle();
      expect(store.value.contains(DomainScope.execution), isTrue);
      expect(find.text(l10n.lifeSignalCreateAction), findsOneWidget);
      expect(find.text(l10n.lifeSignalDetailTitle), findsOneWidget);
      expect(applier.appliedPlan, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'confirmed action opens the created object through its registered resolver',
    (tester) async {
      final event = LifeEvent(
        id: 'finance-today',
        at: DateTime.utc(2026, 9, 30, 8),
        domain: DomainScope.finance,
        template: LifeEventTemplate.financeDaySummary,
        params: const ['3', '2', '1'],
        actionSuggestion: const LifeActionSuggestion(
          template: LifeActionTemplate.reviewFinanceActivity,
          sourceRowFamily: 'fin:journal_entries',
          sourceRowId: 'day:2026-09-30',
        ),
      );
      final applier = _RecordingApplier();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: FButton(
                onPress: () => showLifeSignalSheet(
                  context: context,
                  event: event,
                  executionEnabled: true,
                ),
                child: const Text('Open signal'),
              ),
            ),
          ),
          GoRoute(
            path: '/registered-execution/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Created ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDomainPacksProvider.overrideWithValue(const [
              DomainPack(
                scope: DomainScope.execution,
                tabPaths: ['/registered-execution'],
                sourceRouteResolver: _createdRoute,
              ),
            ]),
            proposalApplierProvider.overrideWith((_) async => applier),
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
      await tester.tap(find.text('Open signal'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en', 'US'));
      await tester.tap(find.text(l10n.lifeSignalCreateAction));
      await tester.pumpAndSettle();
      expect(applier.appliedPlan, isNull);
      expect(find.text(l10n.lifeSignalActionConfirmTitle), findsOneWidget);

      await tester.tap(find.text(l10n.lifeSignalCreateAction).last);
      await tester.pumpAndSettle();
      expect(applier.appliedPlan?.kind, 'execution_action');
      expect(applier.appliedPlan?.payload['source_row_id'], 'day:2026-09-30');

      await tester.tap(find.text(l10n.lifeSignalOpenExecution));
      await tester.pumpAndSettle();
      expect(find.text('Created created-action'), findsOneWidget);
      expect(find.text(l10n.lifeSignalDetailTitle), findsNothing);
    },
  );
}
