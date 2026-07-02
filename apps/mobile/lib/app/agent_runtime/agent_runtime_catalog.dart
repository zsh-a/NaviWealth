/// Export the active LifeOS agent/tool inventory as a Rust agent-runtime
/// catalog.
///
/// This is an adapter seam only: it does not move execution into Rust. The
/// Rust CLI/runtime can consume this JSON to inspect the same active agents,
/// tools, prompt blocks, and proposal kinds that Flutter composes from
/// [DomainPack] registrations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/agents/agent.dart';
import '../../core/ai/agents/agent_schedule.dart';
import '../../core/ai/composition/proposal_kind_registry.dart';
import '../../core/ai/contracts/intent.dart' show RiskLevel;
import '../../core/ai/contracts/tool_descriptor.dart';
import '../../core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart';
import '../../core/ai/runtime/agent_runtime/agent_runtime_protocol.dart';
import '../../core/ai/runtime/device/tools/device_tool.dart';
import '../../core/lifeos/domain_pack.dart';
import '../domain_composition.dart';

export '../../core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart'
    show kSettingsLlmRuntimeCheckAgentId;
export '../../core/ai/runtime/agent_runtime/agent_runtime_protocol.dart'
    show kAgentRuntimeProtocolVersion;

const String kAgentRuntimeCatalogVersion = 'agent_catalog.v1';

final agentRuntimeCatalogProvider = Provider<AgentRuntimeCatalog>((ref) {
  final packs = ref.watch(activeDomainPacksProvider);
  return buildAgentRuntimeCatalog(
    packs: packs,
    agentRegistrations: domainAgentRegistrations(ref, packs),
    generatedAt: DateTime.now().toUtc(),
  );
});

AgentRuntimeCatalog buildAgentRuntimeCatalog({
  required List<DomainPack> packs,
  required List<DomainAgentRegistration> agentRegistrations,
  required DateTime generatedAt,
}) {
  final descriptors = domainToolDescriptors(packs);
  final promptBlocks = domainSystemPromptBlocks(packs);
  return AgentRuntimeCatalog(
    generatedAt: generatedAt.toUtc(),
    activeDomains: [for (final pack in packs) pack.scope.wire],
    agents: [
      kSettingsLlmRuntimeCheckAgent,
      for (final registration in agentRegistrations)
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
  const AgentRuntimeCatalog({
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

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_version': kAgentRuntimeProtocolVersion,
    'catalog_version': kAgentRuntimeCatalogVersion,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'active_domains': activeDomains,
    'agents': [for (final agent in agents) agent.toJson()],
    'tools': [for (final tool in tools) tool.toJson()],
    'proposal_kinds': [for (final kind in proposalKinds) kind.toJson()],
    'prompt_blocks': [for (final block in promptBlocks) block.toJson()],
  };
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
    required this.metadata,
  });

  factory AgentRuntimeToolSpec.fromTool(
    DeviceTool tool, {
    ToolDescriptor? descriptor,
  }) {
    return AgentRuntimeToolSpec(
      name: tool.name,
      description: tool.description,
      inputSchema: _jsonObject(tool.inputSchema),
      risk: _runtimeRisk(tool, descriptor),
      metadata: <String, Object?>{
        if (descriptor != null) ...descriptor.toJson(),
      },
    );
  }

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final String risk;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'input_schema': inputSchema,
    'risk': risk,
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
