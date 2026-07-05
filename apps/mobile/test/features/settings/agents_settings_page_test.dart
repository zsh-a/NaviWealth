import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/agent_presentation.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/agents_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

void main() {
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

    await tester.tap(find.text('View result'));
    await tester.pumpAndSettle();

    expect(find.text('Latest Artifact'), findsWidgets);
    expect(find.text('Something happened.'), findsOneWidget);
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
      const AgentSchedule(interval: Duration(days: 1));

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
