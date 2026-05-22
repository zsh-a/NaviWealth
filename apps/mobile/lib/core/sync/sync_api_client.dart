/// Wire types and client interface for sync v2 (`docs/sync-v2.md`).
///
/// v2 syncs the *current state* of each row, not a stream of ops. One
/// `POST /sync` does push and pull in a single round trip.
library;

/// Sync wire-protocol version this client speaks (`docs/sync-v2.md` §5).
const int kSyncProtocolVersion = 2;

/// Hard ceiling on rows per `POST /sync` request (`docs/sync-v2.md` §5.1).
const int kSyncMaxChanges = 500;

/// A single row as it travels on the wire, both directions.
///
/// Outbound (client → server) sets [table], [id], [payload], [version],
/// [deleted]. Inbound (server → client) additionally carries [deviceId]
/// (the authoring device) and [seq] (the cursor value).
class RowChange {
  const RowChange({
    required this.table,
    required this.id,
    required this.payload,
    required this.version,
    required this.deleted,
    this.deviceId = '',
    this.seq = 0,
  });

  /// Syncable table name (the Drift `actualTableName`).
  final String table;

  /// Primary key of the row.
  final String id;

  /// The full row as a JSON-safe column → value map. Carried even for
  /// deleted rows so a device that never saw the row can still materialise
  /// the tombstone (and so a later edit can resurrect it).
  final Map<String, Object?>? payload;

  /// Opaque, lexicographically-ordered LWW token (the row's HLC string).
  final String version;

  final bool deleted;

  /// Authoring device. Server-set on inbound rows; ignored on outbound.
  final String deviceId;

  /// Server-assigned cursor value. Meaningful on inbound rows only.
  final int seq;

  Map<String, Object?> toJson() => {
    'table': table,
    'id': id,
    'payload': payload,
    'version': version,
    'deleted': deleted,
  };

  static RowChange fromJson(Map<String, Object?> j) {
    final rawPayload = j['payload'];
    Map<String, Object?>? payload;
    if (rawPayload is Map) {
      payload = rawPayload.map((k, v) => MapEntry(k.toString(), v));
    }
    return RowChange(
      table: j['table'] as String,
      id: j['id'] as String,
      payload: payload,
      version: j['version'] as String,
      deleted: (j['deleted'] as bool?) ?? false,
      deviceId: (j['device_id'] as String?) ?? '',
      seq: (j['seq'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `POST /sync` response (`docs/sync-v2.md` §5.1).
class SyncResponse {
  const SyncResponse({
    required this.seq,
    required this.changes,
    required this.more,
  });

  /// Cursor the client adopts after applying [changes].
  final int seq;

  /// Rows authored by other devices, newer than the request's `since`.
  final List<RowChange> changes;

  /// `true` ⇔ the client must sync again to drain the backlog.
  final bool more;
}

/// HTTP client for the single `POST /sync` endpoint.
abstract class SyncApiClient {
  /// Push [changes] and pull everything newer than [since] in one round trip.
  Future<SyncResponse> sync({
    required String deviceId,
    required int since,
    required List<RowChange> changes,
  });
}
