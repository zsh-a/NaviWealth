import 'package:naviwealth/core/sync/drift_sync_storage.dart';

/// Test-only helpers on [InMemoryOutboxStore].
///
/// Sync v2 reduced the outbox to a pure dirty-pointer log — each entry is
/// just `(table, rowId)`. Repository tests only ever inspected what a
/// mutation queued, so this extension surfaces the enqueued pointers in the
/// order they were appended.
extension InMemoryOutboxTestExt on InMemoryOutboxStore {
  /// Queued `(table, rowId)` pointers, oldest first.
  List<({String table, String rowId})> get queued =>
      List.unmodifiable(items);

  /// Drop every queued pointer.
  void clearQueued() => items.clear();
}
