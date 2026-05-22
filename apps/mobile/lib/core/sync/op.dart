import 'dart:convert';

import '../../data/domain/hlc.dart';

/// The set of synced tables (`docs/sync-v2.md` §4). Adding a new value is a
/// data-model change only — the server's row store is schema-agnostic.
const Set<String> kSyncableTables = {
  'accounts',
  'assets',
  'liabilities',
  'fx_rates',
  'tags',
  'goals',
  'devices',
  // FIR-19's domain layer also has these. The server enum will track this
  // set verbatim.
  'amortization_entries',
  'tag_links',
  'categories',
  'settings',
  'users',
  // Beancount-style ledger. JE and posting rows sync independently
  // so a posting-level edit (re-order, fix a typo in a single leg)
  // ships as a single op rather than a JE-wide rewrite. `prices` is
  // the append-only valuation time-series.
  'journal_entries',
  'postings',
  'prices',
  'watchlist_items',
  // Options Income Planner P0 (`docs/options-income.md`). `profile` is a
  // per-user singleton (PK = owner_user_id); `approved_underlyings` is a
  // collection keyed by composite id `<market>:<symbol>`.
  'options_strategy_profile',
  'approved_underlyings',
  // Options Income Planner P3 — trade journal entries.
  'options_trade_journal',
};

enum OpType { insert, update, delete }

extension OpTypeWire on OpType {
  String get wire => name; // values are exactly 'insert' | 'update' | 'delete'
}

/// A locally-authored mutation, queued in the `op_outbox` pending-change log
/// (`docs/sync-v2.md` §7.1). v2 only reads `(tableName, rowId)` back out of
/// it — the row's current state is what gets pushed.
class Op {
  const Op({
    required this.opId,
    required this.tableName,
    required this.rowId,
    required this.opType,
    required this.fieldsDiff,
    required this.hlc,
    required this.deviceId,
  });

  /// UUIDv4. Idempotency key on the server.
  final String opId;

  /// One of [kSyncableTables].
  final String tableName;

  /// Primary key of the row. Composite keys use the canonical
  /// colon-separated form documented in §4.1.
  final String rowId;

  final OpType opType;

  /// `null` only when [opType] is [OpType.delete].
  ///
  /// For `insert`: full column set including PK.
  /// For `update`: partial map of changed columns. Empty diff is invalid
  /// per spec — caller is responsible for filtering no-op updates before
  /// queuing.
  ///
  /// JSON encoding rules (datetime → RFC3339 UTC ms, decimals → string,
  /// etc.) are the responsibility of the **encoder** in the data layer;
  /// values stored here must already be JSON-encodable.
  final Map<String, Object?>? fieldsDiff;

  /// At creation time on the client, this is `client_hlc`. After server
  /// accept, this is `server_hlc`. The `device_id` field always preserves
  /// the original author so peers can suppress echoes.
  final Hlc hlc;

  /// Author's device id (UUID). Stable across the op's lifetime regardless
  /// of who stamped the HLC.
  final String deviceId;

  Map<String, Object?> toJson() => {
    'op_id': opId,
    'table': tableName,
    'row_id': rowId,
    'op_type': opType.wire,
    'fields_diff': fieldsDiff,
    'hlc': hlc.toString(),
    'device_id': deviceId,
  };

  String encode() => jsonEncode(toJson());

  /// Approximate serialised size in bytes — used for body-size capping in
  /// push batches. Computing this lazily avoids JSON-encoding twice on the
  /// hot path.
  int get encodedSizeBytes => utf8.encode(encode()).length;

  @override
  String toString() => 'Op($opType $tableName/$rowId hlc=$hlc dev=$deviceId)';
}

/// Client-side guard called from the repo layer before queuing a mutation.
///
/// Returns `null` when the row is safe to queue, or a short error code when
/// it is not (unknown table, malformed/oversized payload).
String? validateOpForQueue(Op op) {
  if (!kSyncableTables.contains(op.tableName)) {
    return 'unknown_table';
  }
  if (op.opType == OpType.delete) {
    if (op.fieldsDiff != null) return 'bad_request';
    return null;
  }
  if (op.fieldsDiff == null) return 'bad_request';
  if (op.opType == OpType.update && op.fieldsDiff!.isEmpty) {
    return 'empty_update';
  }
  if (op.encodedSizeBytes > 64 * 1024) {
    return 'payload_too_large';
  }
  return null;
}
