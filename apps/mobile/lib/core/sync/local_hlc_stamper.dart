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
    : _clock = DriftLocalClockStore(db);

  final DriftLocalClockStore _clock;
  final String deviceId;

  Future<Hlc> stamp({int? overrideNowMillis}) async {
    final last = await _clock.read() ?? Hlc.zero(deviceId);
    final next = Hlc.tick(
      lastSeen: last,
      nowMillis: overrideNowMillis ?? DateTime.now().millisecondsSinceEpoch,
    );
    await _clock.write(next);
    return next;
  }
}
