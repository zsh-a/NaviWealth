import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/composition/proposal_kind_registry.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/privacy_budget.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
      agents: [_agent],
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
        'domain': 'execution',
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
      tools.firstWhere((tool) => tool['name'] == 'propose_fake')['risk'],
      'medium',
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
        agentRegistryProvider.overrideWith((ref) => [_agent]),
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
