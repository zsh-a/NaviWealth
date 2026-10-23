part of 'frb_chat_runner.dart';

Set<String> _readOnlyToolNames(List<Map<String, Object?>> tools) {
  return {
    for (final tool in tools)
      if (tool['risk'] == 'read_only')
        if (tool['name'] case final String name) name,
  };
}

Set<String> _toolNames(List<Map<String, Object?>> tools) {
  return {
    for (final tool in tools)
      if (tool['name'] case final String name)
        if (name.trim().isNotEmpty) name.trim(),
  };
}

String _effectiveRoundStatus(FrbStreamRoundState state) {
  final status = state.status;
  if (status.isNotEmpty) return status;
  return state.stopReason == 'tool_use' ? 'requires_tool_results' : 'completed';
}

({String code, String message})? _validateToolCalls(
  List<AgentRuntimeToolCall> calls,
  Set<String> allowedToolNames,
) {
  if (calls.isEmpty) {
    return (
      code: _kToolNotAllowedErrorCode,
      message: 'FRB LLM requested tool results without a tool call',
    );
  }
  final ids = <String>{};
  for (final call in calls) {
    if (call.stringId.isEmpty || !ids.add(call.stringId)) {
      return (
        code: _kToolNotAllowedErrorCode,
        message: 'FRB LLM returned duplicate or empty tool call ids',
      );
    }
    if (!allowedToolNames.contains(call.name)) {
      return (
        code: _kToolNotAllowedErrorCode,
        message:
            "FRB LLM requested tool '${call.name}', which is not in the active tool catalog",
      );
    }
  }
  final askUserCalls = calls
      .where((call) => call.name == kAskUserToolName)
      .length;
  if (askUserCalls > 0 && calls.length != 1) {
    return (
      code: _kAskUserBatchErrorCode,
      message: 'ask_user must be the only tool call in a round',
    );
  }
  return null;
}

bool _canParallelizeTool(AgentRuntimeToolCall call, Set<String> readOnlyTools) {
  return call.name != kAskUserToolName && readOnlyTools.contains(call.name);
}

Map<String, Object?>? _pendingInteractionFromToolResult(
  AgentRuntimeToolResult result,
) => _pendingInteractionFromOutput(result.output);

Map<String, Object?>? _pendingInteractionFromChatToolResult(
  Map<String, Object?> result,
) {
  if (result['is_error'] == true) return null;
  return _pendingInteractionFromOutput(result['output']);
}

Map<String, Object?>? _pendingInteractionFromOutput(Object? output) {
  final outputObject = frbObjectOrNull(output);
  final interaction = AiInteractionEnvelope.tryParse(
    outputObject?['interaction'],
  );
  if (interaction == null ||
      interaction.status != AiInteractionStatus.pending ||
      interaction.resumeKind != AiInteractionResumeKind.chatTurn) {
    return null;
  }
  return interaction.toJson();
}

ProgressEvent _toolProgress(AgentRuntimeToolCall call, DateTime startedAt) {
  return ProgressEvent(
    LongTaskProgress(
      id: 'tool:${call.stringId}',
      label: 'tool',
      detail: call.name,
      startedAt: startedAt,
    ),
  );
}

Future<_ToolDispatchOutcome> _dispatchChatTool({
  required AgentRuntimeToolDispatcher dispatcher,
  required AgentRuntimeToolCall call,
  required DateTime startedAt,
  CancelToken? cancelToken,
}) async {
  final dispatch = () async {
    final result = await dispatcher.call(call);
    return _ToolDispatchOutcome(
      call: call,
      result: result,
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
    );
  }();
  if (cancelToken == null) return dispatch;
  final outcome = await Future.any<_ToolDispatchOutcome?>([
    dispatch,
    _waitForCancel(cancelToken).then((_) => null),
  ]);
  return outcome ??
      _ToolDispatchOutcome.cancelled(
        call: call,
        startedAt: startedAt,
        code: _cancellationCode(cancelToken),
      );
}

SpanEvent _toolSpan(
  _ToolDispatchOutcome outcome, {
  required String parentId,
  required int round,
}) {
  final result = outcome.result;
  final call = outcome.call;
  return SpanEvent(
    id: 'tool:${call.stringId}',
    parentId: parentId,
    kind: AiSpanKind.tool,
    name: 'tool:${call.name}',
    startedAt: outcome.startedAt,
    endedAt: outcome.endedAt,
    status: outcome.cancelled
        ? AiSpanStatus.cancelled
        : result.isError
        ? AiSpanStatus.error
        : AiSpanStatus.ok,
    errorCode: result.errorCode,
    input: call.input,
    output: result.output,
    attributes: <String, Object?>{'round': round, 'tool_use_id': call.id},
  );
}

ToolResultEvent _toolResult(_ToolDispatchOutcome outcome) {
  return ToolResultEvent(
    id: outcome.call.stringId,
    name: outcome.call.name,
    output: outcome.result.output,
  );
}

class _ToolDispatchOutcome {
  const _ToolDispatchOutcome({
    required this.call,
    required this.result,
    required this.startedAt,
    required this.endedAt,
    this.cancelled = false,
  });

  factory _ToolDispatchOutcome.cancelled({
    required AgentRuntimeToolCall call,
    required DateTime startedAt,
    String code = _kToolCancelledErrorCode,
  }) {
    final output = <String, Object?>{
      'code': code,
      'message': _kToolCancelledMessage,
    };
    return _ToolDispatchOutcome(
      call: call,
      result: AgentRuntimeToolResult(
        id: call.id,
        name: call.name,
        response: <String, Object?>{
          'jsonrpc': '2.0',
          'id': call.id,
          'error': output,
        },
        output: output,
        outcome: <String, Object?>{
          'status': 'cancelled',
          'retryable': true,
          'code': code,
          'message': _kToolCancelledMessage,
          'details': const <String, Object?>{},
        },
        isError: true,
      ),
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
      cancelled: true,
    );
  }

  final AgentRuntimeToolCall call;
  final AgentRuntimeToolResult result;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool cancelled;
}

sealed class _ChatToolBatchResult {
  const _ChatToolBatchResult();
}

final class _ChatToolBatchReady extends _ChatToolBatchResult {
  const _ChatToolBatchReady(this.results);
  final List<Map<String, Object?>> results;
}

final class _ChatToolBatchSuspend extends _ChatToolBatchResult {
  const _ChatToolBatchSuspend(this.results, this.interaction);
  final List<Map<String, Object?>> results;
  final Map<String, Object?> interaction;
}

final class _ChatToolBatchCancelled extends _ChatToolBatchResult {
  const _ChatToolBatchCancelled();
}

final class _ChatToolBatchFailed extends _ChatToolBatchResult {
  const _ChatToolBatchFailed(this.code, this.message);
  final String code;
  final String message;
}

/// Dispatches one validated native request, batching only consecutive read
/// tools. Journal writes precede effects; completed results survive recovery.
final class _FrbChatToolBatch {
  _FrbChatToolBatch({
    required this.journal,
    required this.round,
    required this.roundId,
  });
  final _FrbChatToolJournal journal;
  final int round;
  final String roundId;
  late final _ChatToolBatchResult result;

  Stream<AiChatEvent> dispatch(List<AgentRuntimeToolCall> calls) async* {
    final handler = journal.toolLineHandler;
    if (handler == null) {
      result = const _ChatToolBatchFailed(
        'frb_chat_tool_host_unavailable',
        'FRB chat received a tool call without a tool host',
      );
      return;
    }
    final dispatcher = AgentRuntimeToolDispatcher(handler: handler);
    final results = <Map<String, Object?>>[];
    final readOnly = _readOnlyToolNames(journal.tools);
    Map<String, Object?>? interaction;
    for (final group in _dispatchGroups(calls, readOnly)) {
      if (journal.cancelToken?.isCancelled == true) {
        result = const _ChatToolBatchCancelled();
        return;
      }
      final outcomes = <Future<_ToolDispatchOutcome>>[];
      for (final call in group) {
        final startedAt = DateTime.now().toUtc();
        yield _toolProgress(call, startedAt);
        await journal.markDispatch(call);
        outcomes.add(
          _dispatchChatTool(
            dispatcher: dispatcher,
            call: call,
            startedAt: startedAt,
            cancelToken: journal.cancelToken,
          ),
        );
      }
      var cancelled = false;
      await for (final outcome in Stream.fromFutures(outcomes)) {
        if (outcome.cancelled) {
          await journal.recordCancellation(outcome);
          cancelled = true;
        }
        yield _toolSpan(outcome, parentId: roundId, round: round);
        yield _toolResult(outcome);
        if (outcome.cancelled) continue;
        results.add(outcome.result.toChatToolResult());
        await journal.recordResult(outcome);
        if (outcome.call.name == kAskUserToolName && !outcome.result.isError) {
          interaction = _pendingInteractionFromToolResult(outcome.result);
          if (interaction == null) {
            result = const _ChatToolBatchFailed(
              _kInteractionEnvelopeErrorCode,
              _kInteractionEnvelopeErrorMessage,
            );
            return;
          }
        }
      }
      if (cancelled) {
        result = const _ChatToolBatchCancelled();
        return;
      }
    }
    result = interaction == null
        ? _ChatToolBatchReady(results)
        : _ChatToolBatchSuspend(results, interaction);
  }
}

Iterable<List<AgentRuntimeToolCall>> _dispatchGroups(
  List<AgentRuntimeToolCall> calls,
  Set<String> readOnly,
) sync* {
  var batch = <AgentRuntimeToolCall>[];
  for (final call in calls) {
    if (_canParallelizeTool(call, readOnly)) {
      batch.add(call);
    } else {
      if (batch.isNotEmpty) yield batch;
      batch = <AgentRuntimeToolCall>[];
      yield [call];
    }
  }
  if (batch.isNotEmpty) yield batch;
}
