import 'op.dart';

/// Applies remote ops fetched via `/sync/pull` to the local materialised
/// tables, with row-level Last-Writer-Wins (`docs/sync-protocol.md` §6).
///
/// Implementations are table-specific: each repo (accounts, assets, …) owns
/// the column ↔ JSON mapping for its rows. The SyncEngine itself stays
/// table-agnostic, so adding a new synced entity is a strict addition to the
/// applier registry and never a SyncEngine change.
abstract class OpApplier {
  /// Apply [ops] in HLC order inside a single transaction. Implementations
  /// MUST be idempotent w.r.t. `op_id` (re-applying the same op leaves
  /// state unchanged) and MUST honour LWW per §6.1.
  Future<void> applyAll(List<Op> ops);
}

/// No-op applier used in tests and as the default until the per-table
/// repos register their adapters. Counting variant exists in tests so
/// scheduler-level assertions can verify dispatch without wiring full
/// table mappers.
class NoopOpApplier implements OpApplier {
  const NoopOpApplier();
  @override
  Future<void> applyAll(List<Op> ops) async {}
}

/// Routes ops by `table_name` to a per-table applier. Lets the SyncEngine
/// stay one applier-shaped while feature teams register handlers
/// independently. Unknown tables are recorded in [unknown] (caller's
/// responsibility to log to `sync_errors`).
class TableRoutingApplier implements OpApplier {
  TableRoutingApplier(this._handlers);

  final Map<String, OpApplier> _handlers;
  final List<Op> unknown = [];

  @override
  Future<void> applyAll(List<Op> ops) async {
    if (ops.isEmpty) return;
    final byTable = <String, List<Op>>{};
    for (final op in ops) {
      final h = _handlers[op.tableName];
      if (h == null) {
        unknown.add(op);
        continue;
      }
      byTable.putIfAbsent(op.tableName, () => []).add(op);
    }
    for (final entry in byTable.entries) {
      await _handlers[entry.key]!.applyAll(entry.value);
    }
  }
}
