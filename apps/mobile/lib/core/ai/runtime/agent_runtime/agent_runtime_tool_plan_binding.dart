/// Domain-facing binding for running native agent-runtime tool plans.
library;

import 'dart:async';

import 'agent_runtime_protocol.dart';
import 'agent_runtime_step_result.dart';

export 'agent_runtime_step_result.dart' show AgentRuntimeNativeStepRunResult;

abstract interface class AgentRuntimeToolPlanStepRunner {
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxToolSteps,
  });
}

class AgentRuntimeToolPlanBinding {
  AgentRuntimeToolPlanBinding({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeToolPlanStepRunner stepRunner,
    required Map<String, Object?> catalogJson,
    this.recordTrace,
  }) : _stepRunnerReader = (() => stepRunner),
       _catalogJsonReader = (() => catalogJson);

  AgentRuntimeToolPlanBinding.lazyCatalog({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeToolPlanStepRunner Function() stepRunnerReader,
    required Map<String, Object?> Function() catalogJsonReader,
    this.recordTrace,
  }) : _stepRunnerReader = stepRunnerReader,
       _catalogJsonReader = catalogJsonReader;

  final String agentId;
  final String domain;
  final String surface;
  final Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)?
  recordTrace;
  final AgentRuntimeToolPlanStepRunner Function() _stepRunnerReader;
  final Map<String, Object?> Function() _catalogJsonReader;

  AgentRuntimeToolPlanStepRunner get stepRunner => _stepRunnerReader();

  Future<AgentRuntimeNativeStepRunResult> runToolPlan({
    required List<Map<String, Object?>> toolPlan,
    String trigger = 'manual',
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxToolSteps,
  }) async {
    final stepRun = await _stepRunnerReader().runUntilTerminalWithTrace(
      catalog: _catalogJsonReader(),
      request: <String, Object?>{
        'protocol_version': kAgentRuntimeProtocolVersion,
        'input': <String, Object?>{
          'tool_plan': <Object?>[for (final toolCall in toolPlan) toolCall],
        },
        'trigger': trigger,
        'metadata': <String, Object?>{
          'surface': surface,
          'agent_id': agentId,
          ...metadata,
        },
      },
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    );
    await recordStepRun(stepRun);
    return stepRun;
  }

  Future<T> readFromToolPlan<T>({
    required List<Map<String, Object?>> toolPlan,
    required Future<T> Function() fallback,
    required FutureOr<T?> Function(Map<String, Object?> terminalStep) decode,
    String trigger = 'manual',
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxToolSteps,
  }) async {
    try {
      final stepRun = await runToolPlan(
        toolPlan: toolPlan,
        trigger: trigger,
        metadata: metadata,
        maxToolSteps: maxToolSteps,
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
