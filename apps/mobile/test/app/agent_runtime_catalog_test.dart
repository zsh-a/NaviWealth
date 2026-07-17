import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/composition/proposal_kind_registry.dart';
import 'package:naviwealth/core/ai/composition/system_prompt_blocks.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/privacy_budget.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';

const _readTool = _FakeTool(
  name: 'read_fake',
  description: 'Read fake data',
  inputSchema: <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'id': <String, Object?>{'type': 'string'},
    },
  },
);

const _proposeTool = _FakeTool(
  name: 'propose_fake',
  description: 'Propose fake data',
);

const _descriptor = ToolDescriptor(
  name: 'propose_fake',
  access: Access.propose,
  risk: RiskLevel.propose,
  requiresConfirmation: Confirmation.oneTap,
  allowedContextTier: BudgetTier.small,
  sideEffect: SideEffect.deviceLocalWrite,
  domain: 'finance',
);

final _agent = _FakeAgent(
  id: 'execution_review',
  name: 'Execution Review',
  schedule: AgentSchedule.daily(hourLocal: 9),
);

final _pack = DomainPack(
  scope: DomainScope.finance,
  deviceTools: const <DeviceTool>[_readTool, _proposeTool],
  toolDescriptors: const <String, ToolDescriptor>{'propose_fake': _descriptor},
  proposalKinds: <ProposalKindMeta>[
    const ProposalKindMeta(
      kind: 'fake',
      icon: Icons.check,
      label: _proposalLabel,
      toolName: 'propose_fake',
    ),
  ],
  systemPromptBlock: 'Finance prompt block',
  agentBuilder: (_) => <Agent>[_agent],
);

String _proposalLabel(AppLocalizations l10n) => 'Fake';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildAgentRuntimeCatalog exports Rust runtime wire shapes', () {
    final catalog = buildAgentRuntimeCatalog(
      packs: [_pack],
      agentRegistrations: [
        DomainAgentRegistration(agent: _agent, domain: DomainScope.finance),
      ],
      generatedAt: DateTime.utc(2026, 6, 28, 9, 12, 31),
    );

    final json = catalog.toJson();
    expect(json['protocol_version'], 'agent.v1');
    expect(json['catalog_version'], 'agent_catalog.v1');
    expect(json['active_domains'], ['finance']);

    final agents = json['agents']! as List<Object?>;
    expect(agents, hasLength(2));
    expect(agents.first, <String, Object?>{
      'protocol_version': 'agent.v1',
      'id': 'settings_llm_runtime_check',
      'name': 'Settings LLM Runtime Check',
      'version': '0.1.0',
      'schedule': <String, Object?>{'type': 'manual'},
      'capabilities': <String>['diagnostic'],
      'metadata': <String, Object?>{
        'domain': 'settings',
        'surface': 'settings_ai_llm',
      },
    });
    expect(agents[1], <String, Object?>{
      'protocol_version': 'agent.v1',
      'id': 'execution_review',
      'name': 'Execution Review',
      'version': '0.1.0',
      'schedule': <String, Object?>{
        'type': 'interval',
        'every_seconds': 86400,
        'preferred_hour_local': 9,
        'jitter_seconds': 300,
      },
      'capabilities': <String>['scheduled_agent'],
      'metadata': <String, Object?>{
        'domain': 'finance',
        'dart_type': '_FakeAgent',
      },
    });

    final tools = (json['tools']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      tools.map((tool) => tool['name']),
      containsAll(['read_fake', 'propose_fake']),
    );
    expect(
      tools.firstWhere((tool) => tool['name'] == 'read_fake')['risk'],
      'read_only',
    );
    expect(
      tools.firstWhere((tool) => tool['name'] == 'read_fake')['replay_policy'],
      'safe_retry',
    );
    expect(
      tools.firstWhere((tool) => tool['name'] == 'propose_fake')['risk'],
      'medium',
    );
    expect(
      tools.firstWhere(
        (tool) => tool['name'] == 'propose_fake',
      )['replay_policy'],
      'at_most_once',
    );
    expect(
      tools.firstWhere((tool) => tool['name'] == 'propose_fake')['metadata'],
      containsPair('requires_confirmation', 'one_tap'),
    );

    expect(json['proposal_kinds'], [
      <String, Object?>{'kind': 'fake', 'tool_name': 'propose_fake'},
    ]);
    expect(json['prompt_blocks'], [
      <String, Object?>{'index': 0, 'text': 'Finance prompt block'},
    ]);
  });

  test('agentRuntimeCatalogProvider follows active packs and agents', () {
    final container = ProviderContainer(
      overrides: [
        activeDomainPacksProvider.overrideWith((ref) => [_pack]),
        agentRegistrationProvider.overrideWithValue([
          DomainAgentRegistration(agent: _agent, domain: DomainScope.finance),
        ]),
      ],
    );
    addTearDown(container.dispose);

    final catalog = container.read(agentRuntimeCatalogProvider).toJson();
    expect(catalog['active_domains'], ['finance']);
    expect(
      (catalog['agents']! as List<Object?>).cast<Map<String, Object?>>().map(
        (agent) => agent['id'],
      ),
      ['settings_llm_runtime_check', 'execution_review'],
    );
    expect(
      (catalog['tools']! as List<Object?>).cast<Map<String, Object?>>().map(
        (tool) => tool['name'],
      ),
      contains('propose_fake'),
    );
  });

  test('buildAgentRuntimeCatalog ignores inactive agent registrations', () {
    final catalog = buildAgentRuntimeCatalog(
      packs: [_pack],
      agentRegistrations: [
        DomainAgentRegistration(agent: _agent, domain: DomainScope.finance),
        DomainAgentRegistration(
          agent: _FakeAgent(
            id: 'stale_health_agent',
            name: 'Stale Health Agent',
            schedule: AgentSchedule.daily(hourLocal: 8),
          ),
          domain: DomainScope.health,
        ),
      ],
      generatedAt: DateTime.utc(2026, 7, 5),
    ).toJson();

    expect(
      (catalog['agents']! as List<Object?>).cast<Map<String, Object?>>().map(
        (agent) => agent['id'],
      ),
      ['settings_llm_runtime_check', 'execution_review'],
    );
    expect(catalog['active_domains'], ['finance']);
  });

  test(
    'production runtime catalog mirrors active domain composition',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      addTearDown(db.close);
      final registrationsProvider = Provider<List<DomainAgentRegistration>>((
        ref,
      ) {
        return domainAgentRegistrations(
          ref,
          ref.watch(activeDomainPacksProvider),
        );
      });
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...lifeOsDomainCompositionOverrides(),
        ],
      );
      addTearDown(container.dispose);

      await container.read(auth.domainOptInsProvider.future);
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.knowledge, true);
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.execution, true);

      final activePacks = container.read(activeDomainPacksProvider);
      final catalog = container.read(agentRuntimeCatalogProvider).toJson();
      final runtimeAgents = (catalog['agents']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final scheduledRuntimeAgents = [
        for (final agent in runtimeAgents)
          if (agent['id'] != kSettingsLlmRuntimeCheckAgentId) agent,
      ];
      final runtimeAgentsById = {
        for (final agent in scheduledRuntimeAgents)
          agent['id']! as String: agent,
      };
      final registeredAgents = container.read(agentRegistryProvider);
      final registeredAgentIds = {
        for (final agent in registeredAgents) agent.id,
      };
      final registrationDomains = {
        for (final registration in container.read(registrationsProvider))
          registration.agent.id: registration.domain.wire,
      };

      expect(container.read(domainPackRegistryProvider), kAllDomainPacks);
      expect(catalog['active_domains'], [
        for (final pack in activePacks) pack.scope.wire,
      ]);
      expect(runtimeAgentsById.keys.toSet(), registeredAgentIds);
      for (final entry in runtimeAgentsById.entries) {
        final metadata = entry.value['metadata']! as Map<String, Object?>;
        expect(metadata['domain'], registrationDomains[entry.key]);
        expect(metadata['dart_type'], isA<String>());
        expect(entry.value['capabilities'], ['scheduled_agent']);
        expect(entry.value['version'], isNotEmpty);
        expect(
          (entry.value['schedule']! as Map<String, Object?>)['every_seconds'],
          greaterThan(0),
          reason: entry.key,
        );
      }

      expect(
        (catalog['tools']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((tool) => tool['name'])
            .toSet(),
        {for (final tool in domainDeviceTools(activePacks)) tool.name},
      );
      expect(
        (catalog['proposal_kinds']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((proposal) => proposal['kind'])
            .toSet(),
        {
          for (final proposal in domainProposalKinds(activePacks))
            proposal.kind,
        },
      );
      expect(
        (catalog['prompt_blocks']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((block) => block['text'])
            .toList(),
        container.read(systemPromptBlocksProvider),
      );
    },
  );
}

class _FakeTool implements DeviceTool {
  const _FakeTool({
    required this.name,
    required this.description,
    this.inputSchema = const <String, Object?>{},
  });

  @override
  final String name;

  @override
  final String description;

  @override
  final Map<String, Object?> inputSchema;

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    return const <String, Object?>{'ok': true};
  }
}

class _FakeAgent implements Agent {
  const _FakeAgent({
    required this.id,
    required this.name,
    required this.schedule,
  });

  @override
  final String id;

  @override
  final String name;

  @override
  final AgentSchedule schedule;

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
