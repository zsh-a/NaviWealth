import 'op.dart';

/// FIFO queue of locally-generated ops awaiting server acknowledgement.
///
/// Ordering contract (`docs/sync-protocol.md` §5.2): ops returned by
/// [peekBatch] MUST be in `client_hlc` ascending order. The server
/// rejects unordered batches with `ops_unordered`.
abstract class OutboxStore {
  /// Number of ops currently queued (for status display).
  Future<int> depth();

  /// Append an op. Idempotent on `op_id`.
  Future<void> enqueue(Op op);

  /// Peek up to [maxOps] ops or until cumulative encoded size would exceed
  /// [maxBytes]. Always at least one op if anything is queued (we'd rather
  /// take a per-op `payload_too_large` than block forever).
  Future<List<Op>> peekBatch({int maxOps = 500, int maxBytes = 1024 * 1024});

  /// Mark these op_ids as acknowledged by the server. Removes them.
  Future<void> ack(Iterable<String> opIds);

  /// Record a non-recoverable per-op failure and remove the op from the
  /// outbox so it's never retried.
  Future<void> recordFailure({
    required String opId,
    required String code,
    String? message,
    String? payload,
  });

  /// Bump the attempts counter for the given ops (for diagnostics, not
  /// for retry logic — the engine alone owns retry timing).
  Future<void> bumpAttempts(Iterable<String> opIds);
}
