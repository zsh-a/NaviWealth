part of 'frb_chat_runner.dart';

/// Owns only host tool dispatch persistence. The native state/snapshot is
/// preserved as an opaque object; Rust remains the continuation authority.
final class _FrbChatToolJournal {
  _FrbChatToolJournal({
    required AgentRuntimeChatSnapshotStore? store,
    required this.turnId,
    required this.tools,
    required this.toolLineHandler,
    required this.cancelToken,
  }) : store = turnId == null || turnId.isEmpty ? null : store;
  final AgentRuntimeChatSnapshotStore? store;
  final String? turnId;
  final List<Map<String, Object?>> tools;
  final AgentRuntimeToolLineHandler? toolLineHandler;
  final CancelToken? cancelToken;
  AgentRuntimeChatSnapshotRecord? _record;

  Future<_ChatSnapshotRecovery?> recover() async {
    final persistence = store;
    if (persistence == null) return null;
    final record = await persistence.loadResumable(turnId!);
    if (record == null) return null;
    final recovered = await _recoverChatSnapshot(
      record: record,
      store: persistence,
      toolLineHandler: toolLineHandler,
      allowedToolNames: _toolNames(tools),
      cancelToken: cancelToken,
    );
    _record = recovered.record;
    return recovered;
  }

  Future<void> save(Map<String, Object?> snapshot) async {
    final persistence = store;
    if (persistence == null) return;
    _record = await persistence.save(
      snapshot: snapshot,
      expectedRevision: _record?.revision,
    );
  }

  Future<void> markDispatch(AgentRuntimeToolCall call) async {
    final record = _record;
    if (record == null) return;
    await save(
      _withDispatchState(
        record.snapshot,
        callId: call.stringId,
        status: 'dispatching',
      ),
    );
  }

  Future<void> recordResult(_ToolDispatchOutcome outcome) async {
    final record = _record;
    if (record == null) return;
    await save(
      _withDispatchState(
        record.snapshot,
        callId: outcome.call.stringId,
        status: 'completed',
        result: outcome.result.toChatToolResult(),
      ),
    );
  }

  Future<void> recordCancellation(_ToolDispatchOutcome outcome) async {
    final record = _record;
    if (record == null) return;
    final persisted = await _persistCancelledDispatch(
      snapshot: record.snapshot,
      snapshotRecord: record,
      store: store!,
      call: outcome.call,
      replayPolicy: _replayPolicyForTool(tools, outcome.call.name),
    );
    _record = persisted.record;
  }
}
