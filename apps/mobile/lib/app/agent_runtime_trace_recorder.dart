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
      result: result,
      startedAt: started,
      finishedAt: finished.isBefore(started) ? started : finished,
      requestId: requestId ?? _requestId(agentId: agentId, runId: runId),
      domain: domain,
      surface: surface,
    );
    await _appendTrace(trace);
    return trace;
  }

  AiTrace _buildTrace({
    required String agentId,
    required AgentRuntimeProfileTurnResult result,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String requestId,
    required String domain,
    required String surface,
  }) {
    final seed = AiTrace(
      requestId: requestId,
      startedAtIso: startedAt.toIso8601String(),
      intent: IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.info,
        label: 'agent_runtime_profile_turn',
        domain: domain,
      ),
      backend: Backend.device,
      budgetTier: BudgetTier.standard,
      routingReason: kDeviceLlmDirectRoutingReason,
      totalDurationMs: 0,
    );
    final builder = AiTraceBuilder.fromSeed(seed, capturePayloads: false)
      ..addTurnAttributes(<String, Object?>{
        'runtime': 'frb_agent_runtime',
        'surface': surface,
        'agent_id': agentId,
        'terminal_status': _string(result.step['status']),
        'dispatched_tool_count': result.stepRun.dispatchedToolCount,
        'budget_exhausted': result.stepRun.budgetExhausted,
      });

    final llmFinished = _offsetTime(startedAt, 1);
    builder.addSpan(
      id: 'llm:profile',
      parentId: kTurnSpanId,
      kind: AiSpanKind.llm,
      name: 'llm:profile',
      startedAt: startedAt,
      endedAt: llmFinished,
      status: AiSpanStatus.ok,
      model: _string(result.llmResponse['model']),
      stopReason: _string(result.llmResponse['finish_reason']),
      attributes: <String, Object?>{
        'provider': _string(result.llmResponse['provider']),
      },
    );

    for (var i = 0; i < result.stepRun.steps.length; i++) {
      final step = result.stepRun.steps[i];
      if (step['status'] != 'tool_call_requested') continue;
      final toolCall = _object(step['tool_call']);
      final name = _string(toolCall?['name']) ?? 'unknown';
      final response = i < result.stepRun.toolResponses.length
          ? result.stepRun.toolResponses[i]
          : null;
      final error = _object(response?['error']);
      final spanStarted = _offsetTime(startedAt, 2 + i);
      builder.addSpan(
        id: 'tool:${i + 1}',
        parentId: 'llm:profile',
        kind: AiSpanKind.tool,
        name: 'tool:$name',
        startedAt: spanStarted,
        endedAt: _offsetTime(spanStarted, 1),
        status: error == null ? AiSpanStatus.ok : AiSpanStatus.error,
        errorCode: _string(error?['code']),
        errorMessage: _string(error?['message']),
        attributes: <String, Object?>{
          'tool_call_id': _string(toolCall?['tool_call_id']),
          'native_step_status': _string(step['status']),
          'response_id': _string(response?['id']),
        },
      );
    }

    return builder.finalize(
      finishedAt: finishedAt,
      terminalReason: _terminalReason(result),
    );
  }
}

TerminalReason _terminalReason(AgentRuntimeProfileTurnResult result) {
  if (result.stepRun.budgetExhausted) return TerminalReason.closedEarly;
  if (result.step['status'] == 'failed') return TerminalReason.streamError;
  return TerminalReason.done;
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
