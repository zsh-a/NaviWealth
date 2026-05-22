import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';

/// Test-only helpers on [InMemoryOutboxStore].
///
/// Sync v2 dropped `OutboxStore.peekBatch` / `ack` — the engine now reads
/// the dirty-pointer set via [PendingRows] and clears by `op_id`. Repository
/// tests, however, only ever used those methods to *inspect* the ops a
/// mutation queued. This extension keeps that intent without re-coupling the
/// production `OutboxStore` to v1 semantics: `peekBatch` returns the queued
/// ops in HLC order, `ack` drops them by `op_id`.
extension InMemoryOutboxTestExt on InMemoryOutboxStore {
  /// Queued ops, ordered ascending by HLC (oldest first) — the order a
  /// v1 push would have observed.
  Future<List<Op>> peekBatch() async {
    return [...items]..sort((a, b) => a.hlc.compareTo(b.hlc));
  }

  /// Drop the named ops from the queue.
  Future<void> ack(Iterable<String> opIds) async {
    final set = opIds.toSet();
    items.removeWhere((o) => set.contains(o.opId));
  }
}
