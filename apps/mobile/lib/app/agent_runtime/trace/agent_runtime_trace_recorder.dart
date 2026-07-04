/// Persist FRB agent-runtime step summaries into the existing local AI trace
/// store.
///
/// This is an app-level adapter: the FRB runner remains persistence-neutral,
/// while callers that want user-visible diagnostics can explicitly record the
/// native step summary as an [AiTrace].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_profile_turn.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_step_result.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_builder.dart';
import 'package:naviwealth/core/ai/trace/providers.dart';

final agentRuntimeTraceRecorderProvider = Provider<AgentRuntimeTraceRecorder>((
  ref,
) {
  return AgentRuntimeTraceRecorder(
    appendTrace: ref.watch(aiTraceStoreProvider).append,
  );
});

typedef AgentRuntimeStepTraceRecorder =
    Future<void> Function(AgentRuntimeNativeStepRunResult stepRun);

class AgentRuntimeTraceRecorder {
  const AgentRuntimeTraceRecorder({
    required Future<void> Function(AiTrace trace) appendTrace,
  }) : _appendTrace = appendTrace;

  final Future<void> Function(AiTrace trace) _appendTrace;

  AgentRuntimeStepTraceRecorder stepRunRecorder({
    required String agentId,
    required String domain,
    required String surface,
  }) {
    return (stepRun) => recordStepRun(
      agentId: agentId,
      stepRun: stepRun,
      domain: domain,
      surface: surface,
    );
  }

  AgentRuntimeProfileTurnTraceRecorder profileTurnRecorder({
    required String agentId,
    required String domain,
    required String surface,
  }) {
    return (result) => recordProfileTurn(
      agentId: agentId,
      result: result,
      domain: domain,
      surface: surface,
    );
  }

  Future<AiTrace> recordProfileTurn({
    required String agentId,
    required AgentRuntimeProfileTurnResult result,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? requestId,
    String domain = kDefaultDomain,
    String surface = 'agent_runtime',
  }) async {
    final started = (startedAt ?? DateTime.now().toUtc()).toUtc();
    final finished = (finishedAt ?? DateTime.now().toUtc()).toUtc();
    final runId = _string(result.step['run_id']);
    final trace = _buildTrace(
      agentId: agentId,
      llmResponse: result.llmResponse,
      step: result.step,
      stepRun: result.stepRun,
      startedAt: started,
      finishedAt: finished.isBefore(started) ? started : finished,
      requestId: requestId ?? _requestId(agentId: agentId, runId: runId),
      domain: domain,
      surface: surface,
    );
    await _appendTrace(trace);
    return trace;
  }

  Future<AiTrace> recordStepRun({
    required String agentId,
    required AgentRuntimeNativeStepRunResult stepRun,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? requestId,
    String domain = kDefaultDomain,
    String surface = 'agent_runtime',
  }) async {
    final started = (startedAt ?? DateTime.now().toUtc()).toUtc();
    final finished = (finishedAt ?? DateTime.now().toUtc()).toUtc();
    final runId = _string(stepRun.terminalStep['run_id']);
    final trace = _buildTrace(
      agentId: agentId,
      llmResponse: null,
      step: stepRun.terminalStep,
      stepRun: stepRun,
      startedAt: started,
      finishedAt: finished.isBefore(started) ? started : finished,
      requestId: requestId ?? _requestId(agentId: agentId, runId: runId),
      domain: domain,
      surface: surface,
      label: 'agent_runtime_step_run',
      routingReason: kFrbNativeEffectLoopRoutingReason,
    );
    await _appendTrace(trace);
    return trace;
  }

  Future<AiTrace> recordProfileCompletion({
    required String agentId,
    required Map<String, Object?>? llmResponse,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? requestId,
    String domain = kDefaultDomain,
    String surface = 'agent_runtime',
    String routingReason = kFrbAgentRuntimeProfileRoutingReason,
    Object? error,
  }) async {
    final started = (startedAt ?? DateTime.now().toUtc()).toUtc();
    final finished = (finishedAt ?? DateTime.now().toUtc()).toUtc();
    final trace = _buildProfileCompletionTrace(
      agentId: agentId,
      llmResponse: llmResponse,
      startedAt: started,
      finishedAt: finished.isBefore(started) ? started : finished,
      requestId: requestId ?? _requestId(agentId: agentId),
      domain: domain,
      surface: surface,
      routingReason: routingReason,
      error: error,
    );
    await _appendTrace(trace);
    return trace;
  }

  AiTrace _buildTrace({
    required String agentId,
    required Map<String, Object?>? llmResponse,
    required Map<String, Object?> step,
    required AgentRuntimeNativeStepRunResult stepRun,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String requestId,
    required String domain,
    required String surface,
    String label = 'agent_runtime_profile_turn',
    String routingReason = kFrbAgentRuntimeProfileRoutingReason,
  }) {
    final seed = AiTrace(
      requestId: requestId,
      startedAtIso: startedAt.toIso8601String(),
      intent: IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.info,
        label: label,
        domain: domain,
      ),
      backend: Backend.device,
      budgetTier: BudgetTier.standard,
      routingReason: routingReason,
      totalDurationMs: 0,
    );
    final nativeTraceEvent = _nativeTraceEvent(step, stepRun);
    final nativeRunState = _nativeRunState(step, stepRun);
    final builder = AiTraceBuilder.fromSeed(seed, capturePayloads: false)
      ..addTurnAttributes(<String, Object?>{
        'runtime': 'frb_agent_runtime',
        'surface': surface,
        'agent_id': agentId,
        'terminal_status': _string(step['status']),
        'dispatched_effect_count': stepRun.dispatchedEffectCount,
        'budget_exhausted': stepRun.budgetExhausted,
        'native_trace_event_count': stepRun.nativeTraceEvents.length,
        'native_trace_event_kind': ?_string(nativeTraceEvent?['kind']),
        'native_trace_event_status': ?_string(nativeTraceEvent?['status']),
        'native_trace_event_tool_name': ?_string(
          nativeTraceEvent?['tool_name'],
        ),
        'native_step_index': ?_int(nativeRunState?['step_index']),
        'native_terminal_reason': ?_string(nativeRunState?['terminal_reason']),
        'native_remaining_effect_count': ?_int(
          nativeRunState?['remaining_effect_count'],
        ),
        'native_effect_result_count': ?_int(
          nativeRunState?['effect_result_count'],
        ),
      });

    final parentId = llmResponse == null ? kTurnSpanId : 'llm:profile';
    if (llmResponse != null) {
      final llmFinished = _offsetTime(startedAt, 1);
      builder.addSpan(
        id: 'llm:profile',
        parentId: kTurnSpanId,
        kind: AiSpanKind.llm,
        name: 'llm:profile',
        startedAt: startedAt,
        endedAt: llmFinished,
        status: AiSpanStatus.ok,
        model: _string(llmResponse['model']),
        stopReason: _string(llmResponse['finish_reason']),
        attributes: <String, Object?>{
          'provider': _string(llmResponse['provider']),
        },
      );
    }

    var effectResponseIndex = 0;
    for (var i = 0; i < stepRun.steps.length; i++) {
      final step = stepRun.steps[i];
      if (step['status'] != 'effect_requested') continue;
      final effect = _object(step['effect']);
      if (_string(effect?['kind']) != 'tool') continue;
      final nativeStepIndex = _int(step['step_index']);
      final spanOrdinal = nativeStepIndex ?? i;
      final nativeStepTraceEvent = _nativeTraceEventForStep(
        stepRun,
        nativeStepIndex,
      );
      final nativeStepRunState = _object(nativeStepTraceEvent?['run_state']);
      final name = _string(effect?['name']) ?? 'unknown';
      final response = effectResponseIndex < stepRun.effectResponses.length
          ? stepRun.effectResponses[effectResponseIndex]
          : null;
      effectResponseIndex++;
      final error = _object(response?['error']);
      final spanStarted = _offsetTime(startedAt, 2 + spanOrdinal);
      builder.addSpan(
        id: 'tool:${spanOrdinal + 1}',
        parentId: parentId,
        kind: AiSpanKind.tool,
        name: 'tool:$name',
        startedAt: spanStarted,
        endedAt: _offsetTime(spanStarted, 1),
        status: error == null ? AiSpanStatus.ok : AiSpanStatus.error,
        errorCode: _string(error?['code']),
        errorMessage: _string(error?['message']),
        attributes: <String, Object?>{
          'effect_id': _string(effect?['effect_id']),
          'native_step_index': ?nativeStepIndex,
          'native_step_status': _string(step['status']),
          'native_trace_event_kind': ?_string(nativeStepTraceEvent?['kind']),
          'native_trace_event_status': ?_string(
            nativeStepTraceEvent?['status'],
          ),
          'native_trace_event_tool_name': ?_string(
            nativeStepTraceEvent?['tool_name'],
          ),
          'native_trace_event_step_index': ?_int(
            nativeStepRunState?['step_index'],
          ),
          'native_trace_event_terminal_reason': ?_string(
            nativeStepRunState?['terminal_reason'],
          ),
          'native_trace_event_remaining_effect_count': ?_int(
            nativeStepRunState?['remaining_effect_count'],
          ),
          'native_trace_event_effect_result_count': ?_int(
            nativeStepRunState?['effect_result_count'],
          ),
          'response_id': _string(response?['id']),
        },
      );
    }

    return builder.finalize(
      finishedAt: finishedAt,
      terminalReason: _terminalReason(step, stepRun),
    );
  }

  AiTrace _buildProfileCompletionTrace({
    required String agentId,
    required Map<String, Object?>? llmResponse,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String requestId,
    required String domain,
    required String surface,
    required String routingReason,
    Object? error,
  }) {
    final hasError = error != null;
    final seed = AiTrace(
      requestId: requestId,
      startedAtIso: startedAt.toIso8601String(),
      intent: IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.info,
        label: 'agent_runtime_profile_completion',
        domain: domain,
      ),
      backend: Backend.device,
      budgetTier: BudgetTier.standard,
      routingReason: routingReason,
      totalDurationMs: 0,
    );
    final builder = AiTraceBuilder.fromSeed(seed, capturePayloads: false)
      ..addTurnAttributes(<String, Object?>{
        'runtime': 'frb_agent_runtime',
        'surface': surface,
        'agent_id': agentId,
        'terminal_status': hasError ? 'failed' : 'completed',
      });
    builder.addSpan(
      id: 'llm:profile',
      parentId: kTurnSpanId,
      kind: AiSpanKind.llm,
      name: 'llm:profile',
      startedAt: startedAt,
      endedAt: finishedAt,
      status: hasError ? AiSpanStatus.error : AiSpanStatus.ok,
      errorCode: hasError ? error.runtimeType.toString() : null,
      errorMessage: hasError ? error.toString() : null,
      model: _string(llmResponse?['model']),
      stopReason: _string(llmResponse?['finish_reason']),
      tokens: _tokens(llmResponse?['usage']),
      attributes: <String, Object?>{
        'provider': _string(llmResponse?['provider']),
      },
    );
    return builder.finalize(
      finishedAt: finishedAt,
      terminalReason: hasError
          ? TerminalReason.streamError
          : TerminalReason.done,
    );
  }
}

TerminalReason _terminalReason(
  Map<String, Object?> step,
  AgentRuntimeNativeStepRunResult stepRun,
) {
  if (stepRun.budgetExhausted) return TerminalReason.closedEarly;
  final nativeReason = _string(
    _nativeRunState(step, stepRun)?['terminal_reason'],
  );
  if (nativeReason != null) {
    return TerminalReasonWire.parse(nativeReason);
  }
  return switch (step['status']) {
    'failed' => TerminalReason.streamError,
    _ => TerminalReason.done,
  };
}

String _requestId({required String agentId, String? runId}) {
  final id = runId == null || runId.isEmpty
      ? DateTime.now().toUtc().microsecondsSinceEpoch.toString()
      : runId;
  return 'agent-runtime:$agentId:$id';
}

DateTime _offsetTime(DateTime start, int milliseconds) {
  return start.toUtc().add(Duration(milliseconds: milliseconds));
}

String? _string(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  if (value is num || value is bool) return value.toString();
  return null;
}

Map<String, Object?>? _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

Map<String, Object?>? _nativeTraceEvent(
  Map<String, Object?> step,
  AgentRuntimeNativeStepRunResult stepRun,
) {
  return _object(step['trace_event']) ??
      (stepRun.nativeTraceEvents.isEmpty
          ? null
          : stepRun.nativeTraceEvents.last);
}

Map<String, Object?>? _nativeTraceEventForStep(
  AgentRuntimeNativeStepRunResult stepRun,
  int? stepIndex,
) {
  if (stepIndex == null) return null;
  for (final event in stepRun.nativeTraceEvents) {
    if (_int(event['step_index']) == stepIndex) return event;
  }
  return null;
}

Map<String, Object?>? _nativeRunState(
  Map<String, Object?> step,
  AgentRuntimeNativeStepRunResult stepRun,
) {
  return _object(_object(step['trace_event'])?['run_state']) ??
      _object(step['run_state']) ??
      _object(_nativeTraceEvent(step, stepRun)?['run_state']);
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

SpanTokens? _tokens(Object? value) {
  final usage = _object(value);
  if (usage == null) return null;
  return SpanTokens(
    input: _int(usage['input_tokens']) ?? _int(usage['input']) ?? 0,
    output: _int(usage['output_tokens']) ?? _int(usage['output']) ?? 0,
    cacheRead:
        _int(usage['cache_read_tokens']) ?? _int(usage['cache_read']) ?? 0,
    cacheWrite:
        _int(usage['cache_write_tokens']) ?? _int(usage['cache_write']) ?? 0,
  );
}
