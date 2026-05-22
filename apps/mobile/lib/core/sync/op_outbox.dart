import 'op.dart';

/// Append-only log of locally-authored mutations awaiting sync.
///
/// In sync v2 this is a *dirty-pointer log*: the write path enqueues one
/// entry per mutation, and the sync engine reads only the `(table, row_id)`
/// set out of it (see [PendingRows]) to push each row's current state. The
/// historical `op_type` / `fields_diff` are no longer interpreted.
abstract class OutboxStore {
  /// Number of queued entries (for status display).
  Future<int> depth();

  /// Append an entry. Idempotent on `op_id`.
  Future<void> enqueue(Op op);
}

/// One queued local mutation, reduced to a pointer at its row.
class PendingPointer {
  const PendingPointer({
    required this.opId,
    required this.table,
    required this.rowId,
  });
  final String opId;
  final String table;
  final String rowId;
}

/// Read side of the outbox: the set of locally-dirty rows plus a way to
/// snapshot each row's current state for push.
abstract class PendingRows {
  /// Number of queued mutations (for status display and the chat gate).
  Future<int> depth();

  /// All queued mutations as `(opId, table, rowId)` pointers, oldest first.
  Future<List<PendingPointer>> pointers();

  /// A row's current state as a JSON-safe column → value map, or `null` if
  /// the row no longer exists (a stale pointer).
  Future<Map<String, Object?>?> readRow(String table, String rowId);

  /// Delete acknowledged op pointers.
  Future<void> clear(Iterable<String> opIds);
}
