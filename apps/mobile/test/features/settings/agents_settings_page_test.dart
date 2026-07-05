import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
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
