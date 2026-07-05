/// Domain-facing binding for running native agent-runtime effect plans.
library;

import 'dart:async';

import 'agent_runtime_protocol.dart';
import 'agent_runtime_step_result.dart';

export 'agent_runtime_step_result.dart' show AgentRuntimeNativeStepRunResult;

sealed class AgentRuntimeEffect {
  const AgentRuntimeEffect();

  const factory AgentRuntimeEffect.tool({
    required String name,
    Map<String, Object?>? input,
  }) = AgentRuntimeToolEffect;

  const factory AgentRuntimeEffect.subagent({
    required String agentId,
    Map<String, Object?>? input,
    String? runId,
    Map<String, Object?>? scope,
    Map<String, Object?>? workflow,
    Map<String, Object?>? metadata,
  }) = AgentRuntimeSubagentEffect;

  Map<String, Object?> toJson();
}

final class AgentRuntimeToolEffect extends AgentRuntimeEffect {
  const AgentRuntimeToolEffect({
    required this.name,
    Map<String, Object?>? input,
  }) : input = input ?? const <String, Object?>{},
       super();

  final String name;
  final Map<String, Object?> input;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'tool',
    'name': name,
    'input': input,
  };
}

final class AgentRuntimeSubagentEffect extends AgentRuntimeEffect {
  const AgentRuntimeSubagentEffect({
    required this.agentId,
    Map<String, Object?>? input,
    this.runId,
    this.scope,
    this.workflow,
    Map<String, Object?>? metadata,
  }) : input = input ?? const <String, Object?>{},
       metadata = metadata ?? const <String, Object?>{},
       super();

  final String agentId;
  final Map<String, Object?> input;
  final String? runId;
  final Map<String, Object?>? scope;
  final Map<String, Object?>? workflow;
  final Map<String, Object?> metadata;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'subagent',
    'agent_id': agentId,
    'input': input,
    if (runId != null) 'run_id': runId,
    if (scope != null) 'scope': scope,
    if (workflow != null) 'workflow': workflow,
    'metadata': metadata,
  };
}

abstract interface class AgentRuntimeEffectStepRunner {
  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxEffectSteps,
  });
}

typedef AgentRuntimeTraceRecordErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class AgentRuntimeEffectPlanBinding {
  AgentRuntimeEffectPlanBinding({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeEffectStepRunner stepRunner,
    required Map<String, Object?> catalogJson,
    this.recordTrace,
    this.onRecordTraceError,
  }) : _stepRunnerReader = (() => stepRunner),
       _catalogJsonReader = (() => catalogJson);

  AgentRuntimeEffectPlanBinding.lazyCatalog({
    required this.agentId,
    required this.domain,
    required this.surface,
    required AgentRuntimeEffectStepRunner Function() stepRunnerReader,
    required Map<String, Object?> Function() catalogJsonReader,
    this.recordTrace,
    this.onRecordTraceError,
  }) : _stepRunnerReader = stepRunnerReader,
       _catalogJsonReader = catalogJsonReader;

  final String agentId;
  final String domain;
  final String surface;
  final Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)?
  recordTrace;
  final AgentRuntimeTraceRecordErrorHandler? onRecordTraceError;
  final AgentRuntimeEffectStepRunner Function() _stepRunnerReader;
  final Map<String, Object?> Function() _catalogJsonReader;

  Future<AgentRuntimeNativeStepRunResult> runEffectPlan({
    required List<AgentRuntimeEffect> effectPlan,
    String trigger = 'manual',
    Map<String, Object?> metadata = const <String, Object?>{},
    int? maxEffectSteps,
  }) async {
    final stepRun = await _stepRunnerReader().runUntilTerminalWithTrace(
      catalog: _catalogJsonReader(),
      request: <String, Object?>{
        'protocol_version': kAgentRuntimeProtocolVersion,
        'input': <String, Object?>{
          'effects': effectPlan.map((effect) => effect.toJson()).toList(),
        },
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
    required List<AgentRuntimeEffect> effectPlan,
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
      await recordStepRun(
        _fallbackStepRun(reason: 'decode_returned_null', metadata: metadata),
      );
    } on Object catch (error) {
      await recordStepRun(
        _fallbackStepRun(
          reason: 'effect_plan_failed',
          error: error,
          metadata: metadata,
        ),
      );
    }
    return fallback();
  }

  Future<void> recordStepRun(AgentRuntimeNativeStepRunResult stepRun) async {
    final recorder = recordTrace;
    if (recorder == null) return;
    try {
      await recorder(stepRun);
    } on Object catch (error, stackTrace) {
      onRecordTraceError?.call(error, stackTrace);
      // Best-effort diagnostics; never fail the production agent.
    }
  }

  AgentRuntimeNativeStepRunResult _fallbackStepRun({
    required String reason,
    required Map<String, Object?> metadata,
    Object? error,
  }) {
    final runId = 'fallback:${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final errorText = error?.toString();
    final traceEvent = <String, Object?>{
      'kind': 'agent_runtime_fallback',
      'run_id': runId,
      'agent_id': agentId,
      'status': 'failed',
      'fallback_reason': reason,
      'fallback_error': ?errorText,
    };
    final terminalStep = <String, Object?>{
      'protocol_version': kAgentRuntimeProtocolVersion,
      'run_id': runId,
      'agent_id': agentId,
      'status': 'failed',
      'output': <String, Object?>{
        'fallback_reason': reason,
        'fallback_error': ?errorText,
        'metadata': metadata,
      },
      'run_state': const <String, Object?>{
        'status': 'failed',
        'step_index': 0,
        'remaining_effect_count': 0,
        'effect_result_count': 0,
        'terminal_reason': 'stream_error',
      },
      'trace_event': traceEvent,
    };
    return AgentRuntimeNativeStepRunResult(
      terminalStep: terminalStep,
      nativeTraceEvents: <Map<String, Object?>>[traceEvent],
    );
  }
}
