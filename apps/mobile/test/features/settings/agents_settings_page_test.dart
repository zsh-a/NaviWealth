import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/agent_artifact_page.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_routes.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/ai/agents/agent_quality_report.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_run_controller.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_runner.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/advanced_settings_page.dart';
import 'package:naviwealth/features/settings/ui/agents_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = makeTestDatabase());
  tearDown(() => db.close());

  testWidgets('renders empty state when no active domain registers agents', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
        GoRoute(
          path: SettingsRoutes.domains,
          name: SettingsRouteNames.domains,
          builder: (context, state) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: const Text('Domain management route'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider.overrideWithValue(
            const <DomainAgentRegistration>[],
          ),
          agentPresentationSpecsProvider.overrideWithValue(
            const <String, AgentPresentationSpec>{},
          ),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => InMemoryAgentPreferenceStore(),
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => InMemoryAgentRunStore(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No active agents'), findsOneWidget);
    expect(
      find.text('Enable a LifeOS domain to see its agents here.'),
      findsOneWidget,
    );
    expect(find.text('Run now'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-enabled-fake_agent')),
      findsNothing,
    );

    await tester.tap(find.text('Manage domains'));
    await tester.pumpAndSettle();

    expect(find.text('Domain management route'), findsOneWidget);
  });

  testWidgets('renders agent rows from presentation metadata', (tester) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider
              .overrideWithValue(const <DomainAgentRegistration>[
                DomainAgentRegistration(
                  agent: _FakeAgent(),
                  domain: DomainScope.finance,
                ),
              ]),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
          agent_providers.agentQualityReportProvider.overrideWith(
            (ref) async => AgentQualityReport(
              windowStart: DateTime.utc(2026, 6, 5),
              generatedAt: DateTime.utc(2026, 7, 5),
              readyRuns: 6,
              noFindingRuns: 3,
              failedRuns: 1,
              artifactCount: 5,
              dismissedOrSnoozedArtifacts: 1,
              evidenceBearingArtifacts: 4,
              fullyAnchoredEvidenceArtifacts: 3,
              evidenceNavigationAttempts: 5,
              evidenceNavigationSuccesses: 4,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Presented Agent'), findsOneWidget);
    expect(find.textContaining('Presented description.'), findsOneWidget);
    expect(find.textContaining('Daily · around 08:00'), findsOneWidget);
    expect(find.text('Enabled 1/1'), findsNothing);
    expect(find.text('30-day quality'), findsNothing);
    expect(find.text('FinanceOS'), findsOneWidget);
    expect(find.text('Run now'), findsNothing);
    expect(find.text('Notifications'), findsNothing);

    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    expect(find.text('Run now'), findsOneWidget);
    expect(find.textContaining('Execution'), findsOneWidget);
    expect(
      find.text('Runs once without changing the automatic schedule'),
      findsOneWidget,
    );
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('persists enabled toggle', (tester) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider
              .overrideWithValue(const <DomainAgentRegistration>[
                DomainAgentRegistration(
                  agent: _FakeAgent(),
                  domain: DomainScope.finance,
                ),
              ]),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-enabled-fake_agent')),
    );
    await tester.pumpAndSettle();

    final pref = await preferenceStore.preferenceFor(
      ownerUserId: 'user-1',
      agentId: 'fake_agent',
    );
    expect(pref.enabled, isFalse);
    expect(find.text('Disabled'), findsWidgets);
  });

  testWidgets('agent rows keep state without duplicating overview metrics', (
    tester,
  ) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    const readyAgent = _FakeAgent();
    const failedAgent = _FailedAgent();
    final startedAt = DateTime.utc(2026, 7, 5, 9);

    await runStore.markRunning(
      ownerUserId: 'user-1',
      agent: readyAgent,
      startedAt: startedAt,
      trigger: AgentRunTrigger.schedule,
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: readyAgent,
      runStartedAt: startedAt,
      result: AgentRunResult(
        agentId: readyAgent.id,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 20)),
        summary: 'Ready summary',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await runStore.markRunning(
      ownerUserId: 'user-1',
      agent: failedAgent,
      startedAt: startedAt,
      trigger: AgentRunTrigger.schedule,
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: failedAgent,
      runStartedAt: startedAt,
      result: AgentRunResult.failed(
        agentId: failedAgent.id,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 20)),
        error: 'Failed summary',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await preferenceStore.setEnabled(
      ownerUserId: 'user-1',
      agentId: failedAgent.id,
      enabled: false,
      updatedAt: startedAt,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider
              .overrideWithValue(const <DomainAgentRegistration>[
                DomainAgentRegistration(
                  agent: readyAgent,
                  domain: DomainScope.finance,
                ),
                DomainAgentRegistration(
                  agent: failedAgent,
                  domain: DomainScope.finance,
                ),
              ]),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
                'failed_agent': AgentPresentationSpec(
                  agentId: 'failed_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.triangleAlert,
                  label: _failedAgentLabel,
                  description: _failedAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enabled 1/2'), findsNothing);
    expect(find.text('Ready 1'), findsNothing);
    expect(find.text('Failed 0'), findsNothing);
    expect(find.text('Notifications 1'), findsNothing);
    expect(find.text('Disabled'), findsWidgets);
  });

  testWidgets('advanced settings owns agent quality diagnostics', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agent_providers.agentQualityReportProvider.overrideWith(
            (ref) async => AgentQualityReport(
              windowStart: DateTime.utc(2026, 6, 5),
              generatedAt: DateTime.utc(2026, 7, 5),
              readyRuns: 6,
              noFindingRuns: 3,
              failedRuns: 1,
              artifactCount: 5,
              dismissedOrSnoozedArtifacts: 1,
              evidenceBearingArtifacts: 4,
              fullyAnchoredEvidenceArtifacts: 3,
              evidenceNavigationAttempts: 5,
              evidenceNavigationSuccesses: 4,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AdvancedSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('30-day quality'), findsOneWidget);
    expect(find.text('10 completed runs'), findsOneWidget);
    expect(find.text('Ready 60% · 6/10'), findsOneWidget);
    expect(find.text('Failed 10% · 1/10'), findsOneWidget);
    expect(find.text('Evidence opened 80% · 4/5'), findsOneWidget);
  });

  testWidgets('disabled agents cannot be run manually from settings', (
    tester,
  ) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    await preferenceStore.setEnabled(
      ownerUserId: 'user-1',
      agentId: 'fake_agent',
      enabled: false,
      updatedAt: DateTime.utc(2026, 7, 5),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider
              .overrideWithValue(const <DomainAgentRegistration>[
                DomainAgentRegistration(
                  agent: _FakeAgent(),
                  domain: DomainScope.finance,
                ),
              ]),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
          agentRunControllerProvider.overrideWith((ref) async {
            throw StateError('disabled agents should not reach Run now');
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disabled'), findsWidgets);
    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();

    expect(
      await runStore.latestForAgent(
        ownerUserId: 'user-1',
        agentId: 'fake_agent',
      ),
      isNull,
    );
  });

  testWidgets('run now writes a manual run through the controller', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    const agent = _FakeAgent();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider.overrideWithValue(
            const <DomainAgentRegistration>[
              DomainAgentRegistration(
                agent: agent,
                domain: DomainScope.finance,
              ),
            ],
          ),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
          agentRunControllerProvider.overrideWith((ref) async {
            final runtime = MemoryRuntime(
              embedder: StubEmbedder(),
              memoryStore: SqliteMemoryStore(db: db),
              eventStore: SqliteEventStore(db: db),
            );
            return AgentRunController(
              runner: AgentRunner(
                runtime: runtime,
                ownerUserId: 'user-1',
                runStore: runStore,
                preferenceStore: preferenceStore,
              ),
              agents: const <Agent>[agent],
              ref: ref,
            );
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();

    final latest = await runStore.latestForAgent(
      ownerUserId: 'user-1',
      agentId: agent.id,
    );
    expect(latest, isNotNull);
    expect(latest!.trigger, AgentRunTrigger.manual);
    expect(latest.status, AgentRunLifecycleStatus.noFinding);
    expect(latest.summary, 'test');
    expect(find.textContaining('No finding'), findsWidgets);
  });

  testWidgets('run now reports controller failures and resets busy state', (
    tester,
  ) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    const agent = _FakeAgent();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider.overrideWithValue(
            const <DomainAgentRegistration>[
              DomainAgentRegistration(
                agent: agent,
                domain: DomainScope.finance,
              ),
            ],
          ),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
          agentRunControllerProvider.overrideWith((ref) async {
            throw StateError('runtime unavailable');
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AppMessenger.init(child: child!),
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();

    expect(
      find.text("We couldn't complete that. Please try again."),
      findsOneWidget,
    );
    expect(find.textContaining('runtime unavailable'), findsNothing);
    expect(find.text('Run now'), findsOneWidget);
    expect(
      await runStore.latestForAgent(ownerUserId: 'user-1', agentId: agent.id),
      isNull,
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('detail run now stays busy while manual run is pending', (
    tester,
  ) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    const agent = _FakeAgent();
    final runCompleter = Completer<AgentRunResult>();
    final controller = _DelayedAgentRunController(result: runCompleter.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider.overrideWithValue(
            const <DomainAgentRegistration>[
              DomainAgentRegistration(
                agent: agent,
                domain: DomainScope.finance,
              ),
            ],
          ),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
          agentRunControllerProvider.overrideWith((ref) async => controller),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run now'));
    await tester.pump();

    expect(controller.calls, 1);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Run now'), findsNothing);

    await tester.tap(find.text('Running'));
    await tester.pump();

    expect(controller.calls, 1);

    runCompleter.complete(
      AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: DateTime.utc(2026, 7, 5, 9),
        finishedAt: DateTime.utc(2026, 7, 5, 9, 1),
        summary: 'done',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run now'), findsOneWidget);
  });

  testWidgets('opens latest agent artifact from settings', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    final artifactStore = SqliteAgentArtifactStore(db: db);
    const agent = _FakeAgent();
    final startedAt = DateTime.utc(2026, 7, 5, 9);
    await runStore.markRunning(
      ownerUserId: 'user-1',
      agent: agent,
      startedAt: startedAt,
      trigger: AgentRunTrigger.manual,
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: agent,
      runStartedAt: startedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 20)),
        summary: 'Artifact summary',
        artifactId: 'artifact-1',
      ),
      trigger: AgentRunTrigger.manual,
    );
    await artifactStore.save(
      AgentArtifact(
        id: 'artifact-1',
        ownerUserId: 'user-1',
        agentId: agent.id,
        domain: 'finance',
        kind: AgentArtifactKind.review,
        severity: AgentArtifactSeverity.info,
        title: 'Latest Artifact',
        summary: 'Artifact summary',
        insights: const <AgentInsight>[
          AgentInsight(title: 'Signal', body: 'Something happened.'),
        ],
        createdAt: startedAt,
      ),
    );
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
        GoRoute(
          path: AgentArtifactRoutes.detailPath,
          builder: (context, state) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: AgentArtifactPage(
              artifactId: state.pathParameters['artifactId'] ?? '',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider.overrideWithValue(
            const <DomainAgentRegistration>[
              DomainAgentRegistration(
                agent: agent,
                domain: DomainScope.finance,
              ),
            ],
          ),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => artifactStore,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    expect(find.text('View result'), findsOneWidget);
    expect(find.textContaining('Last run'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    await tester.tap(find.text('View result'));
    await tester.pumpAndSettle();

    expect(find.text('Latest Artifact'), findsWidgets);
    expect(find.text('Something happened.'), findsOneWidget);
  });

  testWidgets('hides latest agent artifact when it is no longer visible', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    final artifactStore = SqliteAgentArtifactStore(db: db);
    const agent = _FakeAgent();
    final startedAt = DateTime.utc(2026, 7, 5, 9);
    await runStore.markRunning(
      ownerUserId: 'user-1',
      agent: agent,
      startedAt: startedAt,
      trigger: AgentRunTrigger.manual,
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: agent,
      runStartedAt: startedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 20)),
        summary: 'Artifact summary',
        artifactId: 'artifact-1',
      ),
      trigger: AgentRunTrigger.manual,
    );
    await artifactStore.save(
      AgentArtifact(
        id: 'artifact-1',
        ownerUserId: 'user-1',
        agentId: agent.id,
        domain: 'finance',
        kind: AgentArtifactKind.review,
        severity: AgentArtifactSeverity.info,
        title: 'Hidden Artifact',
        summary: 'Artifact summary',
        createdAt: startedAt,
      ),
    );
    await artifactStore.dismiss(
      ownerUserId: 'user-1',
      id: 'artifact-1',
      dismissedAt: startedAt,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider.overrideWithValue(
            const <DomainAgentRegistration>[
              DomainAgentRegistration(
                agent: agent,
                domain: DomainScope.finance,
              ),
            ],
          ),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => artifactStore,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    expect(find.text('View result'), findsNothing);
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('opens agent run history from settings', (tester) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    const agent = _FakeAgent();
    final olderStartedAt = DateTime.utc(2026, 7, 4, 9);
    final latestStartedAt = DateTime.utc(2026, 7, 5, 9);
    await runStore.markRunning(
      ownerUserId: 'user-1',
      agent: agent,
      startedAt: olderStartedAt,
      trigger: AgentRunTrigger.schedule,
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: agent,
      runStartedAt: olderStartedAt,
      result: AgentRunResult.skipped(
        agentId: agent.id,
        startedAt: olderStartedAt,
        finishedAt: olderStartedAt.add(const Duration(milliseconds: 20)),
        reason: 'Older summary',
      ),
      trigger: AgentRunTrigger.schedule,
    );
    await runStore.markRunning(
      ownerUserId: 'user-1',
      agent: agent,
      startedAt: latestStartedAt,
      trigger: AgentRunTrigger.manual,
    );
    await runStore.finishRun(
      ownerUserId: 'user-1',
      agent: agent,
      runStartedAt: latestStartedAt,
      result: AgentRunResult(
        agentId: agent.id,
        status: AgentRunStatus.completed,
        startedAt: latestStartedAt,
        finishedAt: latestStartedAt.add(const Duration(milliseconds: 20)),
        summary: 'Latest summary',
      ),
      trigger: AgentRunTrigger.manual,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistrationProvider.overrideWithValue(
            const <DomainAgentRegistration>[
              DomainAgentRegistration(
                agent: agent,
                domain: DomainScope.finance,
              ),
            ],
          ),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                ),
              }),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferenceStore,
          ),
          agent_providers.agentRunStoreProvider.overrideWith(
            (ref) async => runStore,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Presented Agent'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Presented Agent history'), findsOneWidget);
    expect(find.text('Latest summary'), findsOneWidget);
    expect(find.text('Older summary'), findsOneWidget);
    expect(find.textContaining('Manual'), findsOneWidget);
    expect(find.textContaining('Scheduled'), findsOneWidget);
  });
}

String _fakeAgentLabel(AppLocalizations l10n) => 'Presented Agent';

String _fakeAgentDescription(AppLocalizations l10n) => 'Presented description.';

String _failedAgentLabel(AppLocalizations l10n) => 'Disabled Failed Agent';

String _failedAgentDescription(AppLocalizations l10n) => 'Failed description.';

class _FakeAgent implements Agent {
  const _FakeAgent();

  @override
  String get id => 'fake_agent';

  @override
  String get name => 'Raw agent name';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 1), preferredHourLocal: 8);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    return AgentRunResult.skipped(
      agentId: id,
      startedAt: ctx.now,
      finishedAt: ctx.now,
      reason: 'test',
    );
  }
}

class _FailedAgent implements Agent {
  const _FailedAgent();

  @override
  String get id => 'failed_agent';

  @override
  String get name => 'Raw failed agent name';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 1), preferredHourLocal: 9);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    return AgentRunResult.failed(
      agentId: id,
      startedAt: ctx.now,
      finishedAt: ctx.now,
      error: 'test',
    );
  }
}

class _DelayedAgentRunController implements AgentRunController {
  _DelayedAgentRunController({required this.result});

  final Future<AgentRunResult> result;
  int calls = 0;

  @override
  Future<AgentRunResult> runOnceById(
    String agentId, {
    DateTime? now,
    AgentRunTrigger trigger = AgentRunTrigger.manual,
  }) {
    calls += 1;
    return result;
  }

  @override
  Future<List<AgentRunResult>> tick({
    DateTime? now,
    Iterable<String>? onlyAgentIds,
    AgentRunTrigger trigger = AgentRunTrigger.schedule,
    Future<void> Function(Agent agent)? beforeRun,
  }) async {
    return <AgentRunResult>[await result];
  }
}
