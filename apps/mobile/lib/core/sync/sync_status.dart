import 'dart:async';

/// User-facing sync state surfaced by the SyncEngine. The UI layer reads
/// this to render online / offline / syncing / failed indicators
/// (FIR-34 §"同步状态指示").
enum SyncStatus {
  /// Engine has never run yet (cold start before first sync attempt).
  idle,

  /// Local clock thinks we're online and a sync is in flight.
  syncing,

  /// Engine is in idle state with the last attempt successful.
  online,

  /// Last attempt failed with a network-class error; backoff is active.
  offline,

  /// Last attempt failed with a non-recoverable error (auth, version,
  /// 4xx). The user / app must intervene.
  failed,
}

class SyncStatusEvent {
  const SyncStatusEvent({
    required this.status,
    required this.at,
    this.lastError,
    this.lastSuccessAt,
    this.outboxDepth,
    this.conflicts = const SyncConflictDiagnostics.empty(),
  });

  final SyncStatus status;
  final DateTime at;
  final String? lastError;
  final DateTime? lastSuccessAt;
  final int? outboxDepth;
  final SyncConflictDiagnostics conflicts;
}

class SyncConflictDiagnostics {
  const SyncConflictDiagnostics({
    required this.remoteRows,
    required this.appliedRows,
    required this.localWins,
    required this.ignoredRows,
  });

  const SyncConflictDiagnostics.empty()
    : remoteRows = 0,
      appliedRows = 0,
      localWins = 0,
      ignoredRows = 0;

  final int remoteRows;
  final int appliedRows;
  final int localWins;
  final int ignoredRows;

  bool get hasFindings => localWins > 0 || ignoredRows > 0;

  SyncConflictDiagnostics merge(SyncConflictDiagnostics other) {
    return SyncConflictDiagnostics(
      remoteRows: remoteRows + other.remoteRows,
      appliedRows: appliedRows + other.appliedRows,
      localWins: localWins + other.localWins,
      ignoredRows: ignoredRows + other.ignoredRows,
    );
  }
}

/// Broadcasts status transitions. Multi-listener via a broadcast stream;
/// the [current] getter lets late subscribers seed their UI without
/// waiting for the next event.
class SyncStatusBus {
  SyncStatusBus({SyncStatusEvent? initial})
    : _current =
          initial ??
          SyncStatusEvent(status: SyncStatus.idle, at: DateTime.now());

  final StreamController<SyncStatusEvent> _ctrl =
      StreamController<SyncStatusEvent>.broadcast();
  SyncStatusEvent _current;

  Stream<SyncStatusEvent> get stream => _ctrl.stream;

  SyncStatusEvent get current => _current;

  void emit(SyncStatusEvent event) {
    _current = event;
    if (!_ctrl.isClosed) _ctrl.add(event);
  }

  Future<void> close() => _ctrl.close();
}
