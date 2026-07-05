/// Shell read tools for explaining persisted agent results.
library;

import 'package:naviwealth/core/auth/current_user.dart';

import '../../../agents/agent_artifact.dart';
import '../../../agents/agent_run_store.dart';
import '../../../agents/providers.dart';
import 'device_tool.dart';

class GetAgentArtifactsTool implements DeviceTool {
  const GetAgentArtifactsTool();

  @override
  String get name => 'get_agent_artifacts';

  @override
  String get description =>
      '读取本地保存的 agent artifact。用于解释用户正在查看的 agent 结果、证据、建议动作和 trace 关联。'
      '优先传 artifact_id；也可按 agent_id 或 domain 取最近结果。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'artifact_id': <String, Object?>{
        'type': 'string',
        'description': '具体 agent artifact id；存在时优先读取这一条。',
      },
      'agent_id': <String, Object?>{
        'type': 'string',
        'description': '按 agent id 读取最近 artifact。',
      },
      'domain': <String, Object?>{
        'type': 'string',
        'enum': ['finance', 'health', 'knowledge', 'execution'],
        'description': '按 domain 读取最近 artifact。未传 artifact_id/agent_id 时使用。',
      },
      'limit': <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 20,
        'description': '返回数量，默认 5。',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final store = await ctx.ref.read(agentArtifactStoreProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final artifactId = _trimmed(input['artifact_id']);
    final agentId = _trimmed(input['agent_id']);
    final domain = _trimmed(input['domain']);
    final limit = _limit(input['limit']);

    final artifacts = <AgentArtifact>[];
    if (artifactId != null) {
      final artifact = await store.read(artifactId);
      if (artifact != null && artifact.ownerUserId == ownerUserId) {
        artifacts.add(artifact);
      }
    } else if (agentId != null) {
      artifacts.addAll(
        await store.latestForAgent(
          ownerUserId: ownerUserId,
          agentId: agentId,
          limit: limit,
        ),
      );
    } else if (domain != null) {
      artifacts.addAll(
        await store.latestForDomain(
          ownerUserId: ownerUserId,
          domain: domain,
          limit: limit,
        ),
      );
    } else {
      return <String, Object?>{
        'error': 'artifact_id, agent_id, or domain is required',
        'code': 'invalid_input',
      };
    }

    return <String, Object?>{
      'artifacts': artifacts.map(_artifactToWire).toList(growable: false),
      if (artifacts.isEmpty)
        'guidance':
            '没有找到匹配的 agent artifact。不要假设该 agent 从未运行；可再调用 get_agent_runs 查看运行状态。',
    };
  }
}

class GetAgentRunsTool implements DeviceTool {
  const GetAgentRunsTool();

  @override
  String get name => 'get_agent_runs';

  @override
  String get description =>
      '读取本地保存的 agent run 生命周期状态。用于解释 agent 最近一次运行是否 ready/no_finding/failed、'
      '关联的 artifact/memory/trace，以及失败原因。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'required': <String>['agent_id'],
    'properties': <String, Object?>{
      'agent_id': <String, Object?>{
        'type': 'string',
        'description': '要读取最近运行状态的 agent id。',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final agentId = _trimmed(input['agent_id']);
    if (agentId == null) {
      return <String, Object?>{
        'error': 'agent_id must be a non-empty string',
        'code': 'invalid_input',
      };
    }
    final store = await ctx.ref.read(agentRunStoreProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final run = await store.latestForAgent(
      ownerUserId: ownerUserId,
      agentId: agentId,
    );

    return <String, Object?>{
      'runs': <Map<String, Object?>>[if (run != null) _runToWire(run)],
      if (run == null) 'guidance': '没有找到该 agent 的运行记录。请避免说它已经成功或失败；只能说明本地暂无记录。',
    };
  }
}

Map<String, Object?> _artifactToWire(AgentArtifact artifact) {
  return <String, Object?>{
    'id': artifact.id,
    'agent_id': artifact.agentId,
    'domain': artifact.domain,
    'kind': artifact.kind.wire,
    'severity': artifact.severity.wire,
    'title': artifact.title,
    'summary': artifact.summary,
    'insights': artifact.insights
        .map((insight) => insight.toJson())
        .toList(growable: false),
    'evidence': artifact.evidence
        .map((evidence) => evidence.toJson())
        .toList(growable: false),
    'actions': artifact.actions
        .map((action) => action.toJson())
        .toList(growable: false),
    if (artifact.memoryId != null) 'memory_id': artifact.memoryId,
    if (artifact.traceId != null) 'trace_id': artifact.traceId,
    'created_at': artifact.createdAt.toUtc().toIso8601String(),
    if (artifact.expiresAt != null)
      'expires_at': artifact.expiresAt!.toUtc().toIso8601String(),
    if (artifact.dismissedAt != null)
      'dismissed_at': artifact.dismissedAt!.toUtc().toIso8601String(),
    if (artifact.snoozedUntil != null)
      'snoozed_until': artifact.snoozedUntil!.toUtc().toIso8601String(),
  };
}

Map<String, Object?> _runToWire(AgentRunRecord run) {
  return <String, Object?>{
    'id': run.id,
    'agent_id': run.agentId,
    'agent_name': run.agentName,
    'status': run.status.wire,
    'trigger': run.trigger.wire,
    'started_at': run.startedAt.toUtc().toIso8601String(),
    if (run.finishedAt != null)
      'finished_at': run.finishedAt!.toUtc().toIso8601String(),
    if (run.summary != null) 'summary': run.summary,
    if (run.error != null) 'error': run.error,
    if (run.memoryId != null) 'memory_id': run.memoryId,
    if (run.artifactId != null) 'artifact_id': run.artifactId,
    if (run.traceId != null) 'trace_id': run.traceId,
  };
}

String? _trimmed(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _limit(Object? value) {
  final parsed = switch (value) {
    int v => v,
    num v => v.toInt(),
    _ => 5,
  };
  return parsed.clamp(1, 20);
}
