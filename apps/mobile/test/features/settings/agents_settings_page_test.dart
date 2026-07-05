import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
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
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/agents_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

void main() {
  testWidgets('renders empty state when no active domain registers agents', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => FTheme(
            data: FThemes.slate.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
        GoRoute(
          path: SettingsRoutes.domains,
          name: SettingsRouteNames.domains,
          builder: (context, state) => FTheme(
            data: FThemes.slate.light.desktop,
            child: const Text('Domain management route'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[]),
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
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[_FakeAgent()]),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                  notificationsSupported: true,
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
            data: FThemes.slate.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Presented Agent'), findsOneWidget);
    expect(find.text('Presented description.'), findsOneWidget);
    expect(find.text('Daily · around 08:00'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Run now'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-notifications-fake_agent')),
    );
    await tester.pumpAndSettle();

    final pref = await preferenceStore.preferenceFor(
      ownerUserId: 'user-1',
      agentId: 'fake_agent',
    );
    expect(pref.notificationsEnabled, isFalse);
    expect(pref.enabled, isTrue);
  });

  testWidgets('persists enabled toggle without changing notifications', (
    tester,
  ) async {
    final preferenceStore = InMemoryAgentPreferenceStore();
    final runStore = InMemoryAgentRunStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[_FakeAgent()]),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                  notificationsSupported: true,
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
            data: FThemes.slate.light.desktop,
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
    expect(pref.notificationsEnabled, isTrue);
    expect(find.text('Disabled'), findsOneWidget);
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
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[_FakeAgent()]),
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
            data: FThemes.slate.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disabled'), findsOneWidget);
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

  testWidgets('disabled agents cannot change notification preference', (
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
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[_FakeAgent()]),
          agentPresentationSpecsProvider
              .overrideWithValue(const <String, AgentPresentationSpec>{
                'fake_agent': AgentPresentationSpec(
                  agentId: 'fake_agent',
                  domain: DomainScope.finance,
                  icon: FLucideIcons.walletCards,
                  label: _fakeAgentLabel,
                  description: _fakeAgentDescription,
                  notificationsSupported: true,
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
            data: FThemes.slate.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-notifications-fake_agent')),
    );
    await tester.pumpAndSettle();

    final pref = await preferenceStore.preferenceFor(
      ownerUserId: 'user-1',
      agentId: 'fake_agent',
    );
    expect(pref.enabled, isFalse);
    expect(pref.notificationsEnabled, isTrue);
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
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[agent]),
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
            data: FThemes.slate.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
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
    expect(find.textContaining('No finding'), findsOneWidget);
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[agent]),
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
            data: FThemes.slate.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View result'), findsOneWidget);
    expect(find.textContaining('Last run'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    await tester.tap(find.text('View result'));
    await tester.pumpAndSettle();

    expect(find.text('Latest Artifact'), findsWidgets);
    expect(find.text('Something happened.'), findsOneWidget);
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
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentRegistryProvider.overrideWithValue(const <Agent>[agent]),
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
            data: FThemes.slate.light.desktop,
            child: const AgentsSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Raw agent name history'), findsOneWidget);
    expect(find.text('Latest summary'), findsOneWidget);
    expect(find.text('Older summary'), findsOneWidget);
    expect(find.textContaining('Manual'), findsOneWidget);
    expect(find.textContaining('Scheduled'), findsOneWidget);
  });
}

String _fakeAgentLabel(AppLocalizations l10n) => 'Presented Agent';

String _fakeAgentDescription(AppLocalizations l10n) => 'Presented description.';

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
