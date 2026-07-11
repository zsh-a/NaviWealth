import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/persistence/app_database.dart';
import 'drift_sync_storage.dart';

/// Drift-backed HLC stamper used by every locally-authored mutation.
///
/// Mirrors `SyncEngine.stampHlc` without depending on the engine lifecycle.
/// Cloud sessions pass their backend-issued device id; local-only mode passes
/// the install identity. Both advance the same `sync.local_hlc` cursor, so
/// writes remain ordered while repository availability stays independent of
/// sync initialization and historical backfill work.
class LocalHlcStamper {
  LocalHlcStamper({required AppDatabase db, required this.deviceId})
    : _cursors = DriftCursorStore(db);

  final DriftCursorStore _cursors;
  final String deviceId;

  Future<Hlc> stamp({int? overrideNowMillis}) async {
    final last = await _cursors.readLocalHlc() ?? Hlc.zero(deviceId);
    final next = Hlc.tick(
      lastSeen: last,
      nowMillis: overrideNowMillis ?? DateTime.now().millisecondsSinceEpoch,
    );
    await _cursors.writeLocalHlc(next);
    return next;
  }
}
