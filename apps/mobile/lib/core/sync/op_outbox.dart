/// Append-only dirty-pointer log of locally-authored mutations
/// (`docs/sync-v2.md` §7.1).
///
/// One entry per mutation. The sync engine reads only the `(table, rowId)`
/// set out of it and pushes each row's *current* state — there is no op
/// type, no field diff, nothing else to interpret. Entries are deleted once
/// the server acknowledges the row.
abstract class OutboxStore {
  /// Number of queued entries (for status display).
  Future<int> depth();

  /// Append an entry marking `(table, rowId)` dirty.
  Future<void> enqueue({required String table, required String rowId});
}

/// One queued mutation, reduced to a pointer at its row.
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
