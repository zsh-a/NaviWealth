import 'dart:convert';

import '../../data/domain/hlc.dart';

/// The set of synced tables (`docs/sync-protocol.md` §4.1). Closed enum;
/// adding a new value is a data-model change, not a wire-protocol change.
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
};

enum OpType { insert, update, delete }

extension OpTypeWire on OpType {
  String get wire => name; // values are exactly 'insert' | 'update' | 'delete'
}

OpType parseOpType(String wire) {
  switch (wire) {
    case 'insert':
      return OpType.insert;
    case 'update':
      return OpType.update;
    case 'delete':
      return OpType.delete;
  }
  throw FormatException('Unknown op_type: $wire');
}

/// One mutation: a single row's `insert | update | delete` carrying the
/// authoritative HLC. Wire format is JSON per `docs/sync-protocol.md` §4.
///
/// Two distinct flavours coexist:
///  - Locally-generated ops carry `client_hlc`; the server overwrites with
///    `server_hlc` on accept.
///  - Server-fetched ops carry `server_hlc` directly.
///
/// Both round-trip through this class; the only difference is who stamped
/// the `hlc`.
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

  Op copyWith({Hlc? hlc}) => Op(
    opId: opId,
    tableName: tableName,
    rowId: rowId,
    opType: opType,
    fieldsDiff: fieldsDiff,
    hlc: hlc ?? this.hlc,
    deviceId: deviceId,
  );

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

  static Op fromJson(Map<String, Object?> j) {
    final fieldsDiffRaw = j['fields_diff'];
    Map<String, Object?>? diff;
    if (fieldsDiffRaw == null) {
      diff = null;
    } else if (fieldsDiffRaw is Map<String, Object?>) {
      diff = Map<String, Object?>.from(fieldsDiffRaw);
    } else if (fieldsDiffRaw is Map) {
      diff = fieldsDiffRaw.map((k, v) => MapEntry(k as String, v));
    } else {
      throw const FormatException('fields_diff must be object or null');
    }
    return Op(
      opId: j['op_id'] as String,
      tableName: j['table'] as String,
      rowId: j['row_id'] as String,
      opType: parseOpType(j['op_type'] as String),
      fieldsDiff: diff,
      hlc: Hlc.parse(j['hlc'] as String),
      deviceId: j['device_id'] as String,
    );
  }

  static Op decode(String s) => fromJson(jsonDecode(s) as Map<String, Object?>);

  @override
  String toString() => 'Op($opType $tableName/$rowId hlc=$hlc dev=$deviceId)';
}

/// Validation guard called from the repo layer before queuing the op.
///
/// Returns `null` on success, an error code matching the spec's §5.4 table
/// when invalid (so the caller can drop the op + record to `sync_errors`).
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
