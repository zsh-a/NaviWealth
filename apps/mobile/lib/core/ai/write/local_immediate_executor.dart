/// Undo-stack manager for [LocalImmediateWrite] envelopes.
///
/// Phase 2-B baseline: in-memory only. Each registered write carries
/// a `revert` closure the caller hands in at apply time; the executor
/// keeps it alive for [defaultUndoWindow] before dropping it. UI
/// surfaces show a snackbar / toast that calls back into [undo] before
/// the window expires.
///
/// Phase 2.5 will swap the in-memory list for a Drift-backed table
/// keyed by undo token, so the affordance survives an app restart.
/// Until then a process exit drops outstanding undos — acceptable
/// because the user-visible window is 30 seconds and the underlying
/// mutation already replicated through the normal OpLog path.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../contracts/contracts.dart';

const Duration defaultUndoWindow = Duration(seconds: 30);

/// One outstanding undo entry. Surfaced by [LocalImmediateWriteExecutor.recent]
/// for UI inspection (snackbar, devtools); the executor itself does not
/// rely on this shape internally.
class UndoEntry {
  const UndoEntry({
    required this.token,
    required this.kindLabel,
    required this.summaryZh,
    required this.expiresAt,
  });

  final String token;
  final String kindLabel;
  final String summaryZh;
  final DateTime expiresAt;
}

class LocalImmediateWriteExecutor {
  LocalImmediateWriteExecutor({DateTime Function()? now, Uuid? uuid})
    : _now = now ?? DateTime.now,
      _uuid = uuid ?? const Uuid();

  final DateTime Function() _now;
  final Uuid _uuid;
  final List<_Pending> _pending = <_Pending>[];

  /// Register an already-applied local write. Returns the envelope
  /// (carrying the undo token + expiry) so the caller can hand it to
  /// the AiTrace and snackbar UI.
  ///
  /// The caller is responsible for actually applying the mutation
  /// before calling this — the executor only manages the inverse. A
  /// failure inside [revert] when invoked is the caller's problem.
  Future<LocalImmediateWrite> register({
    required String kindLabel,
    required String summaryZh,
    required Future<void> Function() revert,
    Duration window = defaultUndoWindow,
  }) async {
    prune();
    final token = _uuid.v4();
    final expiresAt = _now().toUtc().add(window);
    _pending.add(
      _Pending(
        token: token,
        kindLabel: kindLabel,
        summaryZh: summaryZh,
        revert: revert,
        expiresAt: expiresAt,
      ),
    );
    return LocalImmediateWrite(
      proposalId: _uuid.v4(),
      kindLabel: kindLabel,
      summaryZh: summaryZh,
      // Wave 31: device-side executor → ProposalSource.device.
      source: ProposalSource.device,
      undo: UndoToken(
        token: token,
        expiresAtIso: expiresAt.toIso8601String(),
      ),
    );
  }

  /// Run the inverse for [token]. Returns:
  ///  * `true` if the undo entry existed, was unexpired, and the
  ///    revert ran (the caller can show 'Undone' confirmation).
  ///  * `false` if the token is unknown OR the entry has expired
  ///    OR was already consumed.
  Future<bool> undo(String token) async {
    prune();
    final idx = _pending.indexWhere((p) => p.token == token);
    if (idx < 0) return false;
    final pending = _pending.removeAt(idx);
    await pending.revert();
    return true;
  }

  /// Drop expired entries. Idempotent. Called automatically before
  /// every [register] / [undo] / [recent] / [pendingCount] call so
  /// callers don't have to schedule it.
  void prune() {
    final cutoff = _now().toUtc();
    _pending.removeWhere((p) => !p.expiresAt.isAfter(cutoff));
  }

  /// Snapshot of currently-undoable entries, newest first.
  List<UndoEntry> recent() {
    prune();
    return <UndoEntry>[
      for (var i = _pending.length - 1; i >= 0; i--)
        UndoEntry(
          token: _pending[i].token,
          kindLabel: _pending[i].kindLabel,
          summaryZh: _pending[i].summaryZh,
          expiresAt: _pending[i].expiresAt,
        ),
    ];
  }

  int get pendingCount {
    prune();
    return _pending.length;
  }
}

class _Pending {
  _Pending({
    required this.token,
    required this.kindLabel,
    required this.summaryZh,
    required this.revert,
    required this.expiresAt,
  });

  final String token;
  final String kindLabel;
  final String summaryZh;
  final Future<void> Function() revert;
  final DateTime expiresAt;
}

final localImmediateWriteExecutorProvider =
    Provider<LocalImmediateWriteExecutor>(
      (ref) => LocalImmediateWriteExecutor(),
    );
