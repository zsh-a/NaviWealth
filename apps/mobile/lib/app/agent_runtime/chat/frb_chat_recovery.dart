part of 'frb_chat_runner.dart';

Future<_ChatSnapshotRecovery> _recoverChatSnapshot({
  required AgentRuntimeChatSnapshotRecord record,
  required AgentRuntimeChatSnapshotStore store,
  required AgentRuntimeToolLineHandler? toolLineHandler,
  required Set<String> allowedToolNames,
  required CancelToken? cancelToken,
}) async {
  if (record.status == 'requires_interaction') {
    final state = chatSnapshotObject(
      record.snapshot['state'],
      'snapshot.state',
    );
    final round = state['round'] is int ? state['round']! as int : 0;
    return _ChatRecoveryAwaitingInteraction(
      record: record,
      chatState: state,
      round: round,
    );
  }
  var currentRecord = record;
  var snapshot = Map<String, Object?>.from(record.snapshot);
  final state = chatSnapshotObject(snapshot['state'], 'snapshot.state');
  final round = state['round'] is int ? state['round']! as int : 0;
  final events = <AiChatEvent>[];
  final results = <Map<String, Object?>>[];
  Map<String, Object?>? suspendInteraction;
  final rawDispatches = snapshot['tool_dispatches'];
  if (rawDispatches is! List) {
    return _ChatRecoveryFailed(
      record: record,
      round: round,
      code: 'frb_chat_snapshot_corrupt',
      message: 'Persisted chat snapshot has no tool dispatch journal',
    );
  }
  final recoveredCalls = <AgentRuntimeToolCall>[];
  for (final value in rawDispatches) {
    final dispatch = chatSnapshotObject(value, 'snapshot.tool_dispatch');
    final callObject = chatSnapshotObject(
      dispatch['call'],
      'snapshot.tool_dispatch.call',
    );
    recoveredCalls.add(
      AgentRuntimeToolCall(
        id: callObject['id'] ?? '',
        name: frbString(callObject['name']),
        input: callObject['input'],
      ),
    );
  }
  if (_validateToolCalls(recoveredCalls, allowedToolNames)
      case final failure?) {
    return _ChatRecoveryFailed(
      record: record,
      round: round,
      code: failure.code,
      message: failure.message,
    );
  }
  for (var index = 0; index < rawDispatches.length; index++) {
    if (cancelToken?.isCancelled == true) {
      return _ChatRecoveryCancelled(
        record: currentRecord,
        round: round,
        events: events,
      );
    }
    final value = rawDispatches[index];
    final dispatch = chatSnapshotObject(value, 'snapshot.tool_dispatch');
    final call = recoveredCalls[index];
    final status = frbString(dispatch['status']);
    if (status == 'completed') {
      final result = chatSnapshotObject(
        dispatch['result'],
        'snapshot.tool_dispatch.result',
      );
      results.add(result);
      // A completed dispatch may be restored after the native stream was
      // interrupted. Re-emit its result so the current chat subscriber sees
      // the recovered tool lifecycle before the next model round.
      events.add(
        ToolCallEvent(id: call.stringId, name: call.name, input: call.input),
      );
      events.add(
        ToolResultEvent(
          id: call.stringId,
          name: call.name,
          output: result['output'],
        ),
      );
      if (call.name == kAskUserToolName && result['is_error'] != true) {
        final interaction = _pendingInteractionFromChatToolResult(result);
        if (interaction == null) {
          return _ChatRecoveryFailed(
            record: currentRecord,
            round: round,
            code: _kInteractionEnvelopeErrorCode,
            message: _kInteractionEnvelopeErrorMessage,
          );
        }
        suspendInteraction = interaction;
      }
      continue;
    }
    final replayPolicy = frbString(dispatch['replay_policy']);
    if (status == 'interrupted' ||
        (status == 'dispatching' && replayPolicy == 'at_most_once')) {
      snapshot = _withDispatchState(
        snapshot,
        callId: call.stringId,
        status: 'interrupted',
      );
      snapshot = <String, Object?>{
        ...snapshot,
        'status': 'failed',
        'error': <String, Object?>{
          'code': 'interrupted_at_most_once',
          'message': "Tool '${call.name}' may already have executed",
        },
      };
      currentRecord = await store.save(
        snapshot: snapshot,
        expectedRevision: currentRecord.revision,
      );
      return _ChatRecoveryFailed(
        record: currentRecord,
        round: round,
        code: 'frb_chat_at_most_once_interrupted',
        message:
            "Tool '${call.name}' was interrupted after dispatch and cannot "
            'be replayed safely.',
      );
    }
    if (toolLineHandler == null) {
      return _ChatRecoveryFailed(
        record: currentRecord,
        round: round,
        code: 'frb_chat_tool_host_unavailable',
        message: 'Cannot recover chat tools without a tool host',
      );
    }
    final startedAt = DateTime.now().toUtc();
    events.add(
      ToolCallEvent(id: call.stringId, name: call.name, input: call.input),
    );
    events.add(_toolProgress(call, startedAt));
    snapshot = _withDispatchState(
      snapshot,
      callId: call.stringId,
      status: 'dispatching',
    );
    currentRecord = await store.save(
      snapshot: snapshot,
      expectedRevision: currentRecord.revision,
    );
    final outcome = await _dispatchChatTool(
      dispatcher: AgentRuntimeToolDispatcher(handler: toolLineHandler),
      call: call,
      startedAt: startedAt,
      cancelToken: cancelToken,
    );
    events
      ..add(_toolSpan(outcome, parentId: 'r$round', round: round))
      ..add(_toolResult(outcome));
    if (outcome.cancelled) {
      final persisted = await _persistCancelledDispatch(
        snapshot: snapshot,
        snapshotRecord: currentRecord,
        store: store,
        call: call,
        replayPolicy: replayPolicy,
      );
      return _ChatRecoveryCancelled(
        record: persisted.record,
        round: round,
        events: events,
      );
    }
    final result = outcome.result.toChatToolResult();
    results.add(result);
    snapshot = _withDispatchState(
      snapshot,
      callId: call.stringId,
      status: 'completed',
      result: result,
    );
    currentRecord = await store.save(
      snapshot: snapshot,
      expectedRevision: currentRecord.revision,
    );
    if (call.name == kAskUserToolName && !outcome.result.isError) {
      final interaction = _pendingInteractionFromToolResult(outcome.result);
      if (interaction == null) {
        return _ChatRecoveryFailed(
          record: currentRecord,
          round: round,
          code: _kInteractionEnvelopeErrorCode,
          message: _kInteractionEnvelopeErrorMessage,
        );
      }
      suspendInteraction = interaction;
    }
  }
  if (suspendInteraction != null) {
    return _ChatRecoverySuspendInteraction(
      record: currentRecord,
      chatState: state,
      toolResults: results,
      events: events,
      round: round,
      interaction: suspendInteraction,
    );
  }
  return _ChatRecoveryToolResults(
    record: currentRecord,
    chatState: state,
    toolResults: results,
    events: events,
    round: round,
  );
}

Map<String, Object?> _buildPendingInteractionSnapshot({
  required Map<String, Object?> state,
}) {
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': kAgentRuntimeChatSnapshotVersion,
    'status': 'requires_interaction',
    'state': state,
    'tool_dispatches': const <Object?>[],
  };
}

Map<String, Object?> _buildPendingChatSnapshot({
  required Map<String, Object?> state,
  required List<AgentRuntimeToolCall> calls,
  required List<Map<String, Object?>> tools,
}) {
  final replayPolicies = <String, String>{
    for (final tool in tools)
      if (tool['name'] case final String name) name: _toolReplayPolicy(tool),
  };
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': kAgentRuntimeChatSnapshotVersion,
    'status': 'requires_tool_results',
    'state': state,
    'tool_dispatches': <Object?>[
      for (final call in calls)
        <String, Object?>{
          'call': <String, Object?>{
            'id': call.id,
            'name': call.name,
            'input': call.input,
          },
          'replay_policy': replayPolicies[call.name] ?? 'at_most_once',
          'status': 'pending',
        },
    ],
  };
}

String _toolReplayPolicy(Map<String, Object?> tool) {
  final explicit = tool['replay_policy'];
  if (explicit is String && explicit.isNotEmpty) return explicit;
  return tool['risk'] == 'read_only' ? 'safe_retry' : 'at_most_once';
}

String _replayPolicyForTool(List<Map<String, Object?>> tools, String name) {
  for (final tool in tools) {
    if (tool['name'] == name) return _toolReplayPolicy(tool);
  }
  return 'at_most_once';
}

Map<String, Object?> _buildTerminalChatSnapshot({
  required Map<String, Object?> state,
  required String status,
  required String stopReason,
}) {
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': kAgentRuntimeChatSnapshotVersion,
    'status': status,
    'state': state,
    'tool_dispatches': const <Object?>[],
    'stop_reason': stopReason,
  };
}

Map<String, Object?> _withDispatchState(
  Map<String, Object?> snapshot, {
  required String callId,
  required String status,
  Map<String, Object?>? result,
}) {
  final rawDispatches = snapshot['tool_dispatches'];
  if (rawDispatches is! List) {
    throw const AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot tool_dispatches must be an array',
    );
  }
  var found = false;
  final dispatches = <Object?>[
    for (final value in rawDispatches)
      (() {
        final dispatch = Map<String, Object?>.from(
          chatSnapshotObject(value, 'snapshot.tool_dispatch'),
        );
        final call = chatSnapshotObject(
          dispatch['call'],
          'snapshot.tool_dispatch.call',
        );
        if ((call['id']?.toString() ?? '') != callId) return dispatch;
        found = true;
        dispatch['status'] = status;
        if (result == null) {
          dispatch.remove('result');
        } else {
          dispatch['result'] = result;
        }
        return dispatch;
      })(),
  ];
  if (!found) {
    throw AgentRuntimeChatSnapshotException(
      AgentRuntimeChatSnapshotErrorCode.corrupt,
      'chat snapshot does not contain tool call $callId',
    );
  }
  return <String, Object?>{...snapshot, 'tool_dispatches': dispatches};
}

Future<_CancelledDispatchPersistence> _persistCancelledDispatch({
  required Map<String, Object?> snapshot,
  required AgentRuntimeChatSnapshotRecord snapshotRecord,
  required AgentRuntimeChatSnapshotStore store,
  required AgentRuntimeToolCall call,
  required String replayPolicy,
}) async {
  if (replayPolicy != 'at_most_once') {
    return _CancelledDispatchPersistence(
      snapshot: snapshot,
      record: snapshotRecord,
    );
  }
  var failedSnapshot = _withDispatchState(
    snapshot,
    callId: call.stringId,
    status: 'interrupted',
  );
  failedSnapshot = <String, Object?>{
    ...failedSnapshot,
    'status': 'failed',
    'error': <String, Object?>{
      'code': 'interrupted_at_most_once',
      'message': "Tool '${call.name}' may already have executed",
    },
  };
  final record = await store.save(
    snapshot: failedSnapshot,
    expectedRevision: snapshotRecord.revision,
  );
  return _CancelledDispatchPersistence(
    snapshot: failedSnapshot,
    record: record,
  );
}

final class _CancelledDispatchPersistence {
  const _CancelledDispatchPersistence({
    required this.snapshot,
    required this.record,
  });

  final Map<String, Object?> snapshot;
  final AgentRuntimeChatSnapshotRecord record;
}

sealed class _ChatSnapshotRecovery {
  const _ChatSnapshotRecovery({
    required this.record,
    required this.round,
    this.events = const <AiChatEvent>[],
  });
  final AgentRuntimeChatSnapshotRecord record;
  final int round;
  final List<AiChatEvent> events;
}

final class _ChatRecoveryToolResults extends _ChatSnapshotRecovery {
  const _ChatRecoveryToolResults({
    required super.record,
    required super.round,
    required super.events,
    required this.chatState,
    required this.toolResults,
  });
  final Map<String, Object?> chatState;
  final List<Map<String, Object?>> toolResults;
}

final class _ChatRecoverySuspendInteraction extends _ChatSnapshotRecovery {
  const _ChatRecoverySuspendInteraction({
    required super.record,
    required super.round,
    required super.events,
    required this.chatState,
    required this.toolResults,
    required this.interaction,
  });
  final Map<String, Object?> chatState;
  final List<Map<String, Object?>> toolResults;
  final Map<String, Object?> interaction;
}

final class _ChatRecoveryAwaitingInteraction extends _ChatSnapshotRecovery {
  const _ChatRecoveryAwaitingInteraction({
    required super.record,
    required super.round,
    required this.chatState,
  });
  final Map<String, Object?> chatState;
}

final class _ChatRecoveryFailed extends _ChatSnapshotRecovery {
  const _ChatRecoveryFailed({
    required super.record,
    required super.round,
    required this.code,
    required this.message,
  });
  final String code;
  final String message;
}

final class _ChatRecoveryCancelled extends _ChatSnapshotRecovery {
  const _ChatRecoveryCancelled({
    required super.record,
    required super.round,
    super.events,
  });
}
