/// Persist FRB agent-runtime step summaries into the existing local AI trace
/// store.
///
/// This is an app-level adapter: the FRB runner remains persistence-neutral,
/// while callers that want user-visible diagnostics can explicitly record the
/// native step summary as an [AiTrace].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/contracts/contracts.dart';
import '../core/ai/trace/ai_trace_builder.dart';
import '../core/ai/trace/providers.dart';
import 'agent_runtime_native_bridge.dart';
import 'agent_runtime_runner.dart';

final agentRuntimeTraceRecorderProvider = Provider<AgentRuntimeTraceRecorder>((
  ref,
) {
  return AgentRuntimeTraceRecorder(
    appendTrace: ref.watch(aiTraceStoreProvider).append,
  );
});

class AgentRuntimeTraceRecorder {
  const AgentRuntimeTraceRecorder({
    required Future<void> Function(AiTrace trace) appendTrace,
  }) : _appendTrace = appendTrace;

  final Future<void> Function(AiTrace trace) _appendTrace;

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
      routingReason: kFrbNativeToolPlanRoutingReason,
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
        'dispatched_tool_count': stepRun.dispatchedToolCount,
        'budget_exhausted': stepRun.budgetExhausted,
        'native_trace_event_count': stepRun.nativeTraceEvents.length,
        'native_trace_event_kind': ?_string(nativeTraceEvent?['kind']),
        'native_trace_event_status': ?_string(nativeTraceEvent?['status']),
        'native_trace_event_tool_name': ?_string(
          nativeTraceEvent?['tool_name'],
        ),
        'native_step_index': ?_int(nativeRunState?['step_index']),
        'native_terminal_reason': ?_string(nativeRunState?['terminal_reason']),
        'native_remaining_tool_count': ?_int(
          nativeRunState?['remaining_tool_count'],
        ),
        'native_tool_result_count': ?_int(nativeRunState?['tool_result_count']),
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

    var toolResponseIndex = 0;
    for (var i = 0; i < stepRun.steps.length; i++) {
      final step = stepRun.steps[i];
      if (step['status'] != 'tool_call_requested') continue;
      final nativeStepIndex = _int(step['step_index']);
      final spanOrdinal = nativeStepIndex ?? i;
      final toolCall = _object(step['tool_call']);
      final name = _string(toolCall?['name']) ?? 'unknown';
      final response = toolResponseIndex < stepRun.toolResponses.length
          ? stepRun.toolResponses[toolResponseIndex]
          : null;
      toolResponseIndex++;
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
          'tool_call_id': _string(toolCall?['tool_call_id']),
          'native_step_index': ?nativeStepIndex,
          'native_step_status': _string(step['status']),
          'response_id': _string(response?['id']),
        },
      );
    }

    return builder.finalize(
      finishedAt: finishedAt,
      terminalReason: _terminalReason(step, stepRun),
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

Map<String, Object?>? _nativeRunState(
  Map<String, Object?> step,
  AgentRuntimeNativeStepRunResult stepRun,
) {
  return _object(_nativeTraceEvent(step, stepRun)?['run_state']) ??
      _object(step['run_state']);
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
