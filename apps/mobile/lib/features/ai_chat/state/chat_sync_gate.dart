import 'dart:async';

import '../../../core/sync/clock.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../core/sync/sync_engine.dart';

/// Outcome of `ChatSyncGate.awaitFlush()` — the controller uses this to
/// decide whether to render the staleness notice (FIR-71 §"失败兜底").
enum ChatGateOutcome {
  /// No pending ops in the outbox. Proceed to chat without delay.
  clean,

  /// Pending ops were drained successfully before the deadline.
  synced,

  /// Push failed or didn't finish within [ChatSyncGate.timeout]. Caller
  /// should still call the model but warn the user that the data may
  /// not include their most recent edits.
  degraded,
}

/// Gate that runs immediately before every chat send: if there are any
/// unsynced local writes, kick the SyncEngine so cross-device state
/// has the best chance to settle before the model reads local Drift.
///
/// The gate is best-effort. We bound the wait to [timeout] (default 5 s)
/// so a flaky network can never block the chat input — the spec's
/// expected experience is "sync usually invisible, never blocking".
///
/// Concurrency: [SyncEngine.run] internally dedupes overlapping calls,
/// so it's safe to invoke this gate while a 30 s polling cycle is in
/// flight; we'll join the running cycle and re-check the outbox depth
/// when it lands.
class ChatSyncGate {
  ChatSyncGate({
    required SyncEngine engine,
    Duration timeout = const Duration(seconds: 5),
    Clock clock = const SystemClock(),
  }) : _engine = engine,
       _timeout = timeout,
       _clock = clock;

  final SyncEngine _engine;
  final Duration _timeout;
  final Clock _clock;

  OutboxStore get _outbox => _engine.outbox;

  /// Returns once the outbox is drained, the deadline has passed, or
  /// the engine reports unrecoverable errors. Never throws — failures
  /// are folded into [ChatGateOutcome.degraded] so the caller has a
  /// single value to switch on.
  Future<ChatGateOutcome> awaitFlush() async {
    int depth;
    try {
      depth = await _outbox.depth();
    } catch (_) {
      // Reading the outbox shouldn't fail in practice, but if it does
      // we don't want to block chat. Treat as clean — the worst case is
      // the user sees the same staleness they would have without this
      // gate at all.
      return ChatGateOutcome.clean;
    }
    if (depth == 0) return ChatGateOutcome.clean;

    final deadline = _clock.now().add(_timeout);

    while (depth > 0) {
      final remaining = deadline.difference(_clock.now());
      if (remaining <= Duration.zero) return ChatGateOutcome.degraded;

      final SyncCycleResult result;
      try {
        result = await _engine.run().timeout(remaining);
      } on TimeoutException {
        return ChatGateOutcome.degraded;
      } catch (_) {
        return ChatGateOutcome.degraded;
      }

      if (!result.success) return ChatGateOutcome.degraded;

      try {
        depth = await _outbox.depth();
      } catch (_) {
        return ChatGateOutcome.degraded;
      }
    }
    return ChatGateOutcome.synced;
  }
}
