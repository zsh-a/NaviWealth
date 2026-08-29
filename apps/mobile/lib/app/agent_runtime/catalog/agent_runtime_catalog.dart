/// Export the active LifeOS agent/tool inventory as a Rust agent-runtime
/// catalog.
///
/// This is an adapter seam only: it does not move execution into Rust. The
/// Rust CLI/runtime can consume this JSON to inspect the same active agents,
/// tools, prompt blocks, and proposal kinds that Flutter composes from
/// [DomainPack] registrations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/composition/device_tools_provider.dart';
import 'package:naviwealth/core/ai/composition/proposal_kind_registry.dart';
import 'package:naviwealth/core/ai/composition/tool_descriptor_lookup.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart' show RiskLevel;
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_protocol.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';

export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart'
    show kSettingsLlmRuntimeCheckAgentId;
export 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_protocol.dart'
    show kAgentRuntimeCatalogVersion, kAgentRuntimeProtocolVersion;

final agentRuntimeCatalogProvider = Provider<AgentRuntimeCatalog>((ref) {
  final packs = ref.watch(activeDomainPacksProvider);
  return buildAgentRuntimeCatalog(
    packs: packs,
    appAgents: ref.watch(appAgentRegistryProvider),
    agentRegistrations: ref.watch(agentRegistrationProvider),
    generatedAt: DateTime.now().toUtc(),
  );
});

final assistantRuntimeToolsProvider = Provider<List<AgentRuntimeToolSpec>>((
  ref,
) {
  final descriptorFor = ref.watch(toolDescriptorLookupProvider);
  return List<AgentRuntimeToolSpec>.unmodifiable([
    for (final tool in ref.watch(assistantDeviceToolsProvider))
      AgentRuntimeToolSpec.fromTool(tool, descriptor: descriptorFor(tool.name)),
  ]);
});

AgentRuntimeCatalog buildAgentRuntimeCatalog({
  required List<DomainPack> packs,
  List<Agent> appAgents = const <Agent>[],
  required List<DomainAgentRegistration> agentRegistrations,
  required DateTime generatedAt,
}) {
  final descriptors = domainToolDescriptors(packs);
  final promptBlocks = domainSystemPromptBlocks(packs);
  final activeDomains = [for (final pack in packs) pack.scope.wire];
  final activeDomainSet = activeDomains.toSet();
  return AgentRuntimeCatalog(
    generatedAt: generatedAt.toUtc(),
    activeDomains: activeDomains,
    agents: [
      kSettingsLlmRuntimeCheckAgent,
      for (final agent in appAgents)
        AgentRuntimeAgentSpec.fromAgent(agent, domain: 'life'),
      for (final registration in agentRegistrations)
        if (activeDomainSet.contains(registration.domain.wire))
          AgentRuntimeAgentSpec.fromAgent(
            registration.agent,
            domain: registration.domain.wire,
          ),
    ],
    tools: [
      for (final tool in domainDeviceTools(packs))
        AgentRuntimeToolSpec.fromTool(tool, descriptor: descriptors[tool.name]),
    ],
    proposalKinds: [
      for (final kind in domainProposalKinds(packs))
        AgentRuntimeProposalKindSpec.fromMeta(kind),
    ],
    promptBlocks: [
      for (var i = 0; i < promptBlocks.length; i++)
        AgentRuntimePromptBlockSpec(index: i, text: promptBlocks[i]),
    ],
  );
}

const AgentRuntimeAgentSpec kSettingsLlmRuntimeCheckAgent =
    AgentRuntimeAgentSpec(
      id: kSettingsLlmRuntimeCheckAgentId,
      name: 'Settings LLM Runtime Check',
      version: '0.1.0',
      schedule: AgentRuntimeScheduleSpec.manual(),
      capabilities: <String>['diagnostic'],
      metadata: <String, Object?>{
        'domain': 'settings',
        'surface': 'settings_ai_llm',
      },
    );

class AgentRuntimeCatalog {
  AgentRuntimeCatalog({
    required this.generatedAt,
    required this.activeDomains,
    required this.agents,
    required this.tools,
    required this.proposalKinds,
    required this.promptBlocks,
  });

  final DateTime generatedAt;
  final List<String> activeDomains;
  final List<AgentRuntimeAgentSpec> agents;
  final List<AgentRuntimeToolSpec> tools;
  final List<AgentRuntimeProposalKindSpec> proposalKinds;
  final List<AgentRuntimePromptBlockSpec> promptBlocks;

  late final Map<String, Object?> _json = Map.unmodifiable(<String, Object?>{
    'protocol_version': kAgentRuntimeProtocolVersion,
    'catalog_version': kAgentRuntimeCatalogVersion,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'active_domains': List<String>.unmodifiable(activeDomains),
    'agents': List<Map<String, Object?>>.unmodifiable([
      for (final agent in agents)
        Map<String, Object?>.unmodifiable(agent.toJson()),
    ]),
    'tools': List<Map<String, Object?>>.unmodifiable([
      for (final tool in tools)
        Map<String, Object?>.unmodifiable(tool.toJson()),
    ]),
    'proposal_kinds': List<Map<String, Object?>>.unmodifiable([
      for (final kind in proposalKinds)
        Map<String, Object?>.unmodifiable(kind.toJson()),
    ]),
    'prompt_blocks': List<Map<String, Object?>>.unmodifiable([
      for (final block in promptBlocks)
        Map<String, Object?>.unmodifiable(block.toJson()),
    ]),
  });

  Map<String, Object?> toJson() => _json;
}

class AgentRuntimeAgentSpec {
  const AgentRuntimeAgentSpec({
    required this.id,
    required this.name,
    required this.version,
    required this.schedule,
    required this.capabilities,
    required this.metadata,
  });

  factory AgentRuntimeAgentSpec.fromAgent(Agent agent, {String? domain}) {
    final metadata = <String, Object?>{
      'dart_type': agent.runtimeType.toString(),
    };
    if (domain != null) metadata['domain'] = domain;
    return AgentRuntimeAgentSpec(
      id: agent.id,
      name: agent.name,
      version: '0.1.0',
      schedule: AgentRuntimeScheduleSpec.fromAgentSchedule(agent.schedule),
      capabilities: const <String>['scheduled_agent'],
      metadata: metadata,
    );
  }

  final String id;
  final String name;
  final String version;
  final AgentRuntimeScheduleSpec schedule;
  final List<String> capabilities;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_version': kAgentRuntimeProtocolVersion,
    'id': id,
    'name': name,
    'version': version,
    'schedule': schedule.toJson(),
    'capabilities': capabilities,
    'metadata': metadata,
  };
}

class AgentRuntimeScheduleSpec {
  const AgentRuntimeScheduleSpec.manual()
    : everySeconds = null,
      preferredHourLocal = null,
      jitterSeconds = null;

  const AgentRuntimeScheduleSpec.interval({
    required int this.everySeconds,
    this.preferredHourLocal,
    this.jitterSeconds,
  });

  factory AgentRuntimeScheduleSpec.fromAgentSchedule(AgentSchedule schedule) {
    final seconds = schedule.interval.inSeconds;
    return AgentRuntimeScheduleSpec.interval(
      everySeconds: seconds <= 0 ? 1 : seconds,
      preferredHourLocal: schedule.preferredHourLocal,
      jitterSeconds: schedule.jitter.inSeconds,
    );
  }

  final int? everySeconds;
  final int? preferredHourLocal;
  final int? jitterSeconds;

  Map<String, Object?> toJson() {
    final everySeconds = this.everySeconds;
    if (everySeconds == null) {
      return const <String, Object?>{'type': 'manual'};
    }
    return <String, Object?>{
      'type': 'interval',
      'every_seconds': everySeconds,
      if (preferredHourLocal != null)
        'preferred_hour_local': preferredHourLocal,
      if (jitterSeconds != null) 'jitter_seconds': jitterSeconds,
    };
  }
}

class AgentRuntimeToolSpec {
  const AgentRuntimeToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.risk,
    required this.replayPolicy,
    required this.metadata,
  });

  factory AgentRuntimeToolSpec.fromTool(
    DeviceTool tool, {
    ToolDescriptor? descriptor,
  }) {
    final risk = _runtimeRisk(tool, descriptor);
    return AgentRuntimeToolSpec(
      name: tool.name,
      description: tool.description,
      inputSchema: _jsonObject(tool.inputSchema),
      risk: risk,
      replayPolicy: risk == 'read_only' ? 'safe_retry' : 'at_most_once',
      metadata: <String, Object?>{
        if (descriptor != null) ...descriptor.toJson(),
      },
    );
  }

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final String risk;
  final String replayPolicy;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'input_schema': inputSchema,
    'risk': risk,
    'replay_policy': replayPolicy,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class AgentRuntimeProposalKindSpec {
  const AgentRuntimeProposalKindSpec({
    required this.kind,
    required this.toolName,
  });

  factory AgentRuntimeProposalKindSpec.fromMeta(ProposalKindMeta meta) {
    return AgentRuntimeProposalKindSpec(
      kind: meta.kind,
      toolName: meta.toolName,
    );
  }

  final String kind;
  final String toolName;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'tool_name': toolName,
  };
}

class AgentRuntimePromptBlockSpec {
  const AgentRuntimePromptBlockSpec({required this.index, required this.text});

  final int index;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'text': text,
  };
}

String _runtimeRisk(DeviceTool tool, ToolDescriptor? descriptor) {
  if (tool.name.startsWith('propose_')) return 'medium';
  if (descriptor == null) return 'read_only';
  return switch (descriptor.risk) {
    RiskLevel.info => 'read_only',
    RiskLevel.suggest => 'low',
    RiskLevel.propose => 'medium',
    RiskLevel.commit => 'high',
  };
}

Map<String, Object?> _jsonObject(Map<String, Object?> value) {
  return value.isEmpty ? const <String, Object?>{'type': 'object'} : value;
}
