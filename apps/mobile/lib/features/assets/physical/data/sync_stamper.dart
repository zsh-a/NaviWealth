import '../../../../core/sync/cursor_store.dart';
import '../../../../core/sync/op.dart';
import '../../../../core/sync/op_outbox.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/domain/hlc.dart';

/// Pulls an HLC tick + the matching wall time, persists the new local HLC,
/// and exposes a single hook for repos to enqueue a sync `Op` after each
/// row mutation.
///
/// This sits between the per-feature repository code and the sync engine so
/// every feature stamps rows the same way. When FIR-44 lands, accounts /
/// transactions / liabilities will share this exact helper instead of
/// reimplementing the cursor + outbox dance.
class SyncStamper {
  SyncStamper({
    required AppDatabase db,
    required CursorStore cursors,
    required OutboxStore outbox,
    required this.userId,
    required this.deviceId,
  })  : _db = db,
        _cursors = cursors,
        _outbox = outbox;

  final AppDatabase _db;
  final CursorStore _cursors;
  final OutboxStore _outbox;
  final String userId;
  final String deviceId;

  /// Generate the next local HLC and persist it. Call this *inside* the
  /// same transaction that writes the entity row so a crash between the
  /// HLC bump and the row write doesn't leave the local clock dangling.
  Future<({Hlc hlc, DateTime updatedAt})> stamp({DateTime? now}) async {
    final wall = (now ?? DateTime.now().toUtc());
    final last = await _cursors.readLocalHlc() ?? Hlc.zero(deviceId);
    final next = Hlc.tick(
      lastSeen: last,
      nowMillis: wall.millisecondsSinceEpoch,
    );
    await _cursors.writeLocalHlc(next);
    return (hlc: next, updatedAt: wall);
  }

  /// Enqueue a sync op describing a row mutation. Skipped silently when the
  /// op is malformed (the validator returns a code) — that path keeps a
  /// local-only mutation intact while loudly logging via the engine's
  /// `sync_errors` table on the next push attempt.
  Future<void> enqueue({
    required String opId,
    required String tableName,
    required String rowId,
    required OpType opType,
    required Map<String, Object?>? fieldsDiff,
    required Hlc hlc,
  }) async {
    final op = Op(
      opId: opId,
      tableName: tableName,
      rowId: rowId,
      opType: opType,
      fieldsDiff: fieldsDiff,
      hlc: hlc,
      deviceId: deviceId,
    );
    if (validateOpForQueue(op) != null) return;
    await _outbox.enqueue(op);
  }

  /// Run [body] inside a single Drift transaction. Used by repos so the
  /// row mutation, OpLog enqueue, and ancillary writes (e.g. valuation
  /// transaction insert) commit atomically.
  Future<T> runTransaction<T>(Future<T> Function() body) {
    return _db.transaction(body);
  }
}
