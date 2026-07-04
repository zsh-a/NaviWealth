/// Domain-neutral profile-turn contract for the FRB agent runtime.
///
/// The concrete FRB/native runner is app-level composition, but feature code
/// only needs this small runner/result/binding surface.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_runtime_step_result.dart';

const String kSettingsLlmRuntimeCheckAgentId = 'settings_llm_runtime_check';

typedef AgentRuntimeProfileTurnBindingKey = ({
  String agentId,
  String domain,
  String surface,
});

typedef AgentRuntimeProfileTurnTraceRecorder =
    Future<void> Function(AgentRuntimeProfileTurnResult result);

typedef AgentRuntimeProfileTurnTraceRecorderFactory =
    AgentRuntimeProfileTurnTraceRecorder Function({
      required String agentId,
      required String domain,
      required String surface,
    });

final agentRuntimeProfileTurnRunnerProvider =
    Provider<AgentRuntimeProfileTurnRunner?>((ref) => null);

final agentRuntimeProfileTurnTraceRecorderFactoryProvider =
    Provider<AgentRuntimeProfileTurnTraceRecorderFactory?>((ref) => null);

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
        resolveAvailability: true,
      );
    });

AgentRuntimeProfileTurnBinding? agentRuntimeProfileTurnBinding(
  Ref ref, {
  required String agentId,
  required String domain,
  required String surface,
  bool resolveAvailability = true,
}) {
  final recorderFactory = ref.read(
    agentRuntimeProfileTurnTraceRecorderFactoryProvider,
  );
  final recorder = recorderFactory?.call(
    agentId: agentId,
    domain: domain,
    surface: surface,
  );
  if (!resolveAvailability) {
    return AgentRuntimeProfileTurnBinding.lazyRunner(
      agentId: agentId,
      domain: domain,
      surface: surface,
      runnerReader: () => ref.read(agentRuntimeProfileTurnRunnerProvider),
      recordTrace: recorder,
    );
  }

  final runner = ref.watch(agentRuntimeProfileTurnRunnerProvider);
  if (runner == null) return null;
  return AgentRuntimeProfileTurnBinding(
    agentId: agentId,
    domain: domain,
    surface: surface,
    runner: runner,
    recordTrace: recorder,
  );
}

abstract interface class AgentRuntimeProfileTurnRunner {
  Future<AgentRuntimeProfileTurnResult> run({
    required String agentId,
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata,
    int? maxEffectSteps,
  });
}

class AgentRuntimeProfileTurnResult {
  const AgentRuntimeProfileTurnResult({
    required this.llmResponse,
    required this.step,
    this.stepRun = const AgentRuntimeNativeStepRunResult(
      terminalStep: <String, Object?>{},
    ),
  });

  final Map<String, Object?> llmResponse;
  final Map<String, Object?> step;
  final AgentRuntimeNativeStepRunResult stepRun;

  Map<String, Object?> toJson() => <String, Object?>{
    'llm_response': llmResponse,
    'step': step,
    'step_run': stepRun.toJson(),
  };
}

class AgentRuntimeProfileTurnBinding {
  AgentRuntimeProfileTurnBinding({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeProfileTurnRunner runner,
    this.recordTrace,
  }) : _runnerReader = (() => runner);

  AgentRuntimeProfileTurnBinding.lazyRunner({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeProfileTurnRunner? Function() runnerReader,
    this.recordTrace,
  }) : _runnerReader = runnerReader;

  final String agentId;
  final String domain;
  final String surface;
  final AgentRuntimeProfileTurnTraceRecorder? recordTrace;
  final AgentRuntimeProfileTurnRunner? Function() _runnerReader;

  AgentRuntimeProfileTurnRunner? get runner => _runnerReader();

  Future<AgentRuntimeProfileTurnResult> run({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxEffectSteps,
  }) async {
    final runner = _runnerReader();
    if (runner == null) {
      throw StateError('agent runtime profile turn runner is unavailable');
    }
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
      maxEffectSteps: maxEffectSteps,
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
