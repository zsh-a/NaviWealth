/// Shared dependencies for Dart callers that execute native profile-turn steps.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_runtime_runner.dart';
import 'agent_runtime_trace_recorder.dart';

typedef AgentRuntimeProfileTurnBindingKey = ({
  String agentId,
  String domain,
  String surface,
});

final agentRuntimeProfileTurnBindingProvider =
    Provider.family<
      AgentRuntimeProfileTurnBinding?,
      AgentRuntimeProfileTurnBindingKey
    >((ref, key) {
      return agentRuntimeProfileTurnBinding(
        ref,
        agentId: key.agentId,
        domain: key.domain,
        surface: key.surface,
      );
    });

AgentRuntimeProfileTurnBinding? agentRuntimeProfileTurnBinding(
  Ref ref, {
  required String agentId,
  required String domain,
  required String surface,
}) {
  final runner = ref.watch(agentRuntimeProfileTurnRunnerProvider);
  if (runner == null) return null;
  return AgentRuntimeProfileTurnBinding(
    agentId: agentId,
    domain: domain,
    surface: surface,
    runner: runner,
    recordTrace: ref
        .read(agentRuntimeTraceRecorderProvider)
        .profileTurnRecorder(
          agentId: agentId,
          domain: domain,
          surface: surface,
        ),
  );
}

class AgentRuntimeProfileTurnBinding {
  const AgentRuntimeProfileTurnBinding({
    required this.agentId,
    required this.domain,
    required this.surface,
    required this.runner,
    this.recordTrace,
  });

  final String agentId;
  final String domain;
  final String surface;
  final AgentRuntimeProfileTurnRunner runner;
  final AgentRuntimeProfileTurnTraceRecorder? recordTrace;

  Future<AgentRuntimeProfileTurnResult> run({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxToolSteps,
  }) async {
    final result = await runner.run(
      agentId: agentId,
      messages: messages,
      tools: tools,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      metadata: <String, Object?>{
        'surface': surface,
        'agent_id': agentId,
        ...metadata,
      },
      maxToolSteps: maxToolSteps,
    );
    await recordProfileTurn(result);
    return result;
  }

  Future<void> recordProfileTurn(AgentRuntimeProfileTurnResult result) async {
    final recorder = recordTrace;
    if (recorder == null) return;
    try {
      await recorder(result);
    } on Object {
      // Best-effort diagnostics; never fail the production agent.
    }
  }
}
