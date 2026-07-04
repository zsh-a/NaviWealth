/// Domain-facing binding for running native agent-runtime effect plans.
library;

import 'dart:async';

import 'agent_runtime_protocol.dart';
import 'agent_runtime_step_result.dart';

export 'agent_runtime_step_result.dart' show AgentRuntimeNativeStepRunResult;

abstract interface class AgentRuntimeEffectStepRunner {
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
  });
}

class AgentRuntimeEffectPlanBinding {
  AgentRuntimeEffectPlanBinding({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeEffectStepRunner stepRunner,
    required Map<String, Object?> catalogJson,
    this.recordTrace,
  }) : _stepRunnerReader = (() => stepRunner),
       _catalogJsonReader = (() => catalogJson);

  AgentRuntimeEffectPlanBinding.lazyCatalog({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeEffectStepRunner Function() stepRunnerReader,
    required Map<String, Object?> Function() catalogJsonReader,
    this.recordTrace,
  }) : _stepRunnerReader = stepRunnerReader,
       _catalogJsonReader = catalogJsonReader;

  final String agentId;
  final String domain;
  final String surface;
  final Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)?
  recordTrace;
  final AgentRuntimeEffectStepRunner Function() _stepRunnerReader;
  final Map<String, Object?> Function() _catalogJsonReader;

  AgentRuntimeEffectStepRunner get stepRunner => _stepRunnerReader();

  Future<AgentRuntimeNativeStepRunResult> runEffectPlan({
    required List<Map<String, Object?>> effectPlan,
    String trigger = 'manual',
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxEffectSteps,
  }) async {
    final stepRun = await _stepRunnerReader().runUntilTerminalWithTrace(
      catalog: _catalogJsonReader(),
      request: <String, Object?>{
        'protocol_version': kAgentRuntimeProtocolVersion,
        'input': <String, Object?>{'effects': effectPlan},
        'trigger': trigger,
        'metadata': <String, Object?>{
          'surface': surface,
          'agent_id': agentId,
          ...metadata,
        },
      },
      agentId: agentId,
      maxEffectSteps: maxEffectSteps,
    );
    await recordStepRun(stepRun);
    return stepRun;
  }

  Future<T> readFromEffectPlan<T>({
    required List<Map<String, Object?>> effectPlan,
    required Future<T> Function() fallback,
    required FutureOr<T?> Function(Map<String, Object?> terminalStep) decode,
    String trigger = 'manual',
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxEffectSteps,
  }) async {
    try {
      final stepRun = await runEffectPlan(
        effectPlan: effectPlan,
        trigger: trigger,
        metadata: metadata,
        maxEffectSteps: maxEffectSteps,
      );
      final value = await decode(stepRun.terminalStep);
      if (value != null) return value;
    } on Object {
      // Fall through to the repository/programmatic path below.
    }
    return fallback();
  }

  Future<void> recordStepRun(AgentRuntimeNativeStepRunResult stepRun) async {
    final recorder = recordTrace;
    if (recorder == null) return;
    try {
      await recorder(stepRun);
    } on Object {
      // Best-effort diagnostics; never fail the production agent.
    }
  }
}
